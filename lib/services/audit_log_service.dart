import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

// ─── AuditEntry model ─────────────────────────────────────────────────────────

class AuditEntry {
  final String   id;
  final String   action;   // 'create' | 'update' | 'delete'
  final String   entity;   // 'student' | 'attendance' | 'fee_payment' | ...
  final String   entityId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final String?  reason;
  final String   actorUid;
  final String   actorName;
  final String   actorRole;
  final DateTime timestamp;
  final String?  deletedReason; // soft-delete field

  const AuditEntry({
    required this.id,
    required this.action,
    required this.entity,
    required this.entityId,
    this.before,
    this.after,
    this.reason,
    required this.actorUid,
    required this.actorName,
    required this.actorRole,
    required this.timestamp,
    this.deletedReason,
  });

  factory AuditEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d  = doc.data() ?? {};
    final ts = d['timestamp'];
    return AuditEntry(
      id:            doc.id,
      action:        (d['action']    as String?) ?? '',
      entity:        (d['entity']    as String?) ?? '',
      entityId:      (d['entityId']  as String?) ?? '',
      before:        d['before'] != null
          ? Map<String, dynamic>.from(d['before'] as Map)
          : null,
      after:         d['after'] != null
          ? Map<String, dynamic>.from(d['after'] as Map)
          : null,
      reason:        d['reason']     as String?,
      actorUid:      (d['actorUid']  as String?) ?? '',
      actorName:     (d['actorName'] as String?) ?? 'Unknown',
      actorRole:     (d['actorRole'] as String?) ?? '',
      timestamp:     ts is Timestamp ? ts.toDate() : DateTime.now(),
      deletedReason: d['deletedReason'] as String?,
    );
  }
}

// ─── AuditService ─────────────────────────────────────────────────────────────

/// Append-only audit trail for sensitive operations.
///
/// Firestore path: schools/{sid}/audit_logs/{autoId}
///
/// Guaranteed:
///   • Fire-and-forget via [emit] — never blocks the calling thread.
///   • [log] is awaitable for tests or one-off needs.
///   • Actor info is auto-populated from [AuthService] + Firebase Auth.
///   • Before/after payloads are sanitised (Timestamps → ISO strings,
///     nested maps recursively cleaned) so Firestore never rejects them.
class AuditService extends BaseFirestoreService {
  static final AuditService _instance = AuditService._();
  AuditService._();
  factory AuditService() => _instance;

  // ── Path helper ────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _col(String sid) =>
      db.collection('schools').doc(sid).collection('audit_logs');

  // ── Fire-and-forget entry point ────────────────────────────────────────────

  /// Writes an audit log entry without blocking the caller.
  /// Any write failure is swallowed and printed to the debug console.
  static void emit({
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? reason,
  }) {
    AuditService()
        .log(
          action:   action,
          entity:   entity,
          entityId: entityId,
          before:   before,
          after:    after,
          reason:   reason,
        )
        .catchError((Object e) => debugPrint('[AuditService] emit failed: $e'));
  }

  // ── Awaitable core ─────────────────────────────────────────────────────────

  /// Writes one audit log entry.
  ///
  /// Reads actor information from the current Firebase Auth user and the
  /// local [AuthService] session so callers don't have to pass it.
  Future<void> log({
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? reason,
  }) async {
    try {
      final session  = await AuthService().getSession() ?? {};
      final fbUser   = FirebaseAuth.instance.currentUser;
      final actorUid  = fbUser?.uid
          ?? (session['email'] as String?)
          ?? 'unknown';
      final actorName = (session['name']  as String?)
          ?? fbUser?.email
          ?? actorUid;
      final actorRole = (session['role']  as String?) ?? 'unknown';
      final sid       = AuthService.currentSchoolId;

      await _col(sid).add({
        'action':    action,
        'entity':    entity,
        'entityId':  entityId,
        if (before != null) 'before': _sanitize(before),
        if (after  != null) 'after':  _sanitize(after),
        if (reason != null) 'reason': reason,
        'actorUid':  actorUid,
        'actorName': actorName,
        'actorRole': actorRole,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AuditService] log failed: $e');
    }
  }

  // ── Payload sanitiser ──────────────────────────────────────────────────────

  /// Recursively converts Firestore-unfriendly values so the payload can be
  /// stored as a nested map.  Timestamps → ISO-8601 strings; Timestamps in
  /// sub-maps handled recursively; anything else kept as-is.
  static Map<String, dynamic> _sanitize(Map<String, dynamic> raw) {
    return raw.map((k, v) => MapEntry(k, _sanitizeValue(v)));
  }

  static dynamic _sanitizeValue(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime)  return v.toIso8601String();
    if (v is Map)       return _sanitize(Map<String, dynamic>.from(v));
    if (v is List)      return v.map(_sanitizeValue).toList();
    return v;
  }

  // ── Query helpers (used by AuditLogScreen) ─────────────────────────────────

  /// Returns the first page of [limit] entries, newest first.
  Future<({List<AuditEntry> entries, DocumentSnapshot? cursor})> fetchPage({
    int limit = 50,
    String? entityFilter,
    String? actorFilter,
    DateTime? from,
    DateTime? to,
    DocumentSnapshot? after,
  }) async {
    final sid = AuthService.currentSchoolId;
    Query<Map<String, dynamic>> q =
        _col(sid).orderBy('timestamp', descending: true);

    if (entityFilter != null && entityFilter.isNotEmpty) {
      q = q.where('entity', isEqualTo: entityFilter);
    }
    if (actorFilter != null && actorFilter.isNotEmpty) {
      q = q.where('actorUid', isEqualTo: actorFilter);
    }
    if (from != null) {
      q = q.where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('timestamp',
          isLessThanOrEqualTo:
              Timestamp.fromDate(to.add(const Duration(days: 1))));
    }
    if (after != null) q = q.startAfterDocument(after);

    q = q.limit(limit);

    final snap = await q.get();
    final entries = snap.docs.map(AuditEntry.fromDoc).toList();
    final cursor  = snap.docs.isNotEmpty ? snap.docs.last : null;
    return (entries: entries, cursor: cursor);
  }

  /// Fetches ALL entries matching the given filters (for CSV export).
  /// Batches internally; capped at 2 000 rows to protect memory.
  Future<List<AuditEntry>> fetchAll({
    String? entityFilter,
    String? actorFilter,
    DateTime? from,
    DateTime? to,
  }) async {
    final all    = <AuditEntry>[];
    DocumentSnapshot? cursor;
    const batchSize = 500;

    while (all.length < 2000) {
      final page = await fetchPage(
        limit:        batchSize,
        entityFilter: entityFilter,
        actorFilter:  actorFilter,
        from:         from,
        to:           to,
        after:        cursor,
      );
      all.addAll(page.entries);
      cursor = page.cursor;
      if (page.entries.length < batchSize) break;
    }
    return all;
  }
}
