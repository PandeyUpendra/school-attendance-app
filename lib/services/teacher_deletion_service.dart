import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/teacher.dart';
import '../utils/app_logger.dart';
import 'auth_service.dart';
import 'timetable_service.dart';

/// Service for the "coordinator requests a teacher deletion, principal or
/// owner approves" workflow.
///
/// Pattern mirrors [StudentService.approveDeletionRequest] but for teachers.
/// Storage:  /schools/{schoolId}/teacher_deletion_requests/{requestId}
/// Rules:    see `firestore.rules` — coordinator creates pending; principal/
///           admin/owner approves or rejects; coordinator can cancel their own.
///
/// Document shape:
///   teacherId          : Teachers collection doc ID
///   teacherName        : convenience for list rendering
///   teacherEmail       : convenience
///   reason             : optional free-text submitted by the coordinator
///   requestedBy        : caller's lowercased email
///   requestedByName    : caller's name (cache for UI)
///   requestedAt        : server timestamp
///   status             : 'pending' | 'approved' | 'rejected' | 'cancelled'
///   reviewedBy         : email of approver/rejecter
///   reviewedByRole     : 'principal' | 'admin' | 'owner'
///   reviewedByName     : cache
///   reviewedAt         : server timestamp
///   rejectionNote      : optional free-text on reject
///   cancelledAt        : server timestamp on cancel
class TeacherDeletionService {
  static final TeacherDeletionService _instance = TeacherDeletionService._();
  TeacherDeletionService._();
  factory TeacherDeletionService() => _instance;

  static final _db = FirebaseFirestore.instance;
  final _timetableService = TimetableService();

  CollectionReference<Map<String, dynamic>> _collection(String schoolId) =>
      _db.collection('schools').doc(schoolId).collection('teacher_deletion_requests');

  // ── Coordinator: request deletion ───────────────────────────────────────

  /// Files a deletion request for [teacher]. Returns the new request id.
  ///
  /// Fails (permission-denied) if the caller is not a coordinator of
  /// [schoolId], or if a pending request for the same teacher already exists
  /// (we enforce this client-side; rules accept the duplicate but the UI
  /// would then show two badges — guard early instead).
  Future<String> requestDeletion({
    required String schoolId,
    required Teacher teacher,
    required String requestedBy,
    String? requestedByName,
    String? reason,
  }) async {
    // Reject duplicate pending requests for the same teacher.
    final dup = await _collection(schoolId)
        .where('teacherId', isEqualTo: teacher.id)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (dup.docs.isNotEmpty) {
      throw StateError('A pending deletion request already exists for this teacher.');
    }

    final ref = await _collection(schoolId).add({
      'teacherId':       teacher.id,
      'teacherName':     teacher.name,
      'teacherEmail':    teacher.email,
      'reason':          (reason ?? '').trim(),
      'requestedBy':     requestedBy.toLowerCase().trim(),
      'requestedByName': requestedByName ?? '',
      'requestedAt':     FieldValue.serverTimestamp(),
      'status':          'pending',
    });
    return ref.id;
  }

  // ── Streams ─────────────────────────────────────────────────────────────

  /// Stream of pending requests for the approval screen.
  Stream<List<Map<String, dynamic>>> streamPending(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// Resolved tab — approved + rejected. Cancelled requests are excluded
  /// (they look like noise to the principal); coordinator sees their own
  /// cancelled via [streamMyRequests].
  Stream<List<Map<String, dynamic>>> streamResolved(String schoolId) =>
      _collection(schoolId)
          .where('status', whereIn: ['approved', 'rejected'])
          .orderBy('reviewedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// All requests filed by [requesterEmail]. Used in the coordinator's
  /// "my requests" view if/when it lands; for now mainly handy for tests.
  Stream<List<Map<String, dynamic>>> streamMyRequests({
    required String schoolId,
    required String requesterEmail,
  }) =>
      _collection(schoolId)
          .where('requestedBy', isEqualTo: requesterEmail.toLowerCase().trim())
          .orderBy('requestedAt', descending: true)
          .snapshots()
          .map(_pack);

  /// Map of teacherId → requestId for currently-pending requests in the
  /// school. The management screen uses this to render the "Deletion
  /// requested" pending badge on each teacher card.
  Stream<Map<String, String>> streamPendingByTeacherId(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((snap) {
        final out = <String, String>{};
        for (final d in snap.docs) {
          final tid = d.data()['teacherId'] as String?;
          if (tid != null && tid.isNotEmpty) out[tid] = d.id;
        }
        return out;
      });

  /// Pending count for dashboard badges.
  Stream<int> streamPendingCount(String schoolId) =>
      _collection(schoolId)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) => s.docs.length);

  // ── Approve / reject / cancel ───────────────────────────────────────────

  /// Approves [requestId] and **atomically removes the teacher** — updates the
  /// deletion request status, deletes the teacher doc, and scrubs every
  /// timetable slot in a single [WriteBatch] (#728). This prevents the
  /// de-sync where the request is marked 'approved' but the teacher record
  /// persists when the Firestore deletion fails partway through.
  ///
  /// Caller must be principal/admin/owner per security rules.
  ///
  /// The Firebase Auth account cleanup runs best-effort AFTER the batch
  /// commits so a transient Auth API failure cannot block the atomic data
  /// cleanup.
  Future<void> approve({
    required String schoolId,
    required String requestId,
    required String reviewerEmail,
    required String reviewerRole,
    String? reviewerName,
  }) async {
    final reqRef = _collection(schoolId).doc(requestId);
    final snap = await reqRef.get();
    if (!snap.exists) throw StateError('Request no longer exists.');
    final data = snap.data()!;
    final teacherId    = data['teacherId']    as String?;
    final teacherEmail = (data['teacherEmail'] as String? ?? '').trim().toLowerCase();

    if (teacherId == null || teacherId.isEmpty) {
      // No teacher to delete — just mark the request approved.
      await reqRef.update({
        'status':         'approved',
        'reviewedBy':     reviewerEmail.toLowerCase().trim(),
        'reviewedByRole': reviewerRole,
        'reviewedByName': reviewerName ?? '',
        'reviewedAt':     FieldValue.serverTimestamp(),
      });
      return;
    }

    // ── Build atomic WriteBatch ────────────────────────────────────────────
    // Note: WriteBatch does NOT support reads, so we read everything we need
    // before starting the batch.

    // 1. Read the teacher's allowed_users email from the teacher doc (in case
    //    the request's cached email is stale).
    String resolvedTeacherEmail = teacherEmail;
    try {
      final tDoc = await _db
          .collection('schools').doc(schoolId)
          .collection('teachers').doc(teacherId)
          .get();
      if (tDoc.exists && tDoc.data() != null) {
        final te = (tDoc.data()!['email'] as String?)?.trim().toLowerCase() ?? '';
        if (te.isNotEmpty) resolvedTeacherEmail = te;
      }
    } catch (_) {}

    // 2. Read all timetable docs so we can scrub this teacher's slots.
    final ttSnap = await _db
        .collection('schools').doc(schoolId)
        .collection('timetable')
        .get();

    // ── Commit atomic batch ──────────────────────────────────────────────
    final batch = _db.batch();

    // a. Update the deletion request status.
    batch.update(reqRef, {
      'status':         'approved',
      'reviewedBy':     reviewerEmail.toLowerCase().trim(),
      'reviewedByRole': reviewerRole,
      'reviewedByName': reviewerName ?? '',
      'reviewedAt':     FieldValue.serverTimestamp(),
    });

    // b. Delete the teacher document.
    batch.delete(
        _db.collection('schools').doc(schoolId).collection('teachers').doc(teacherId));

    // c. Scrub teacher from every timetable slot.
    for (final doc in ttSnap.docs) {
      final raw = Map<String, dynamic>.from(
          (doc.data()['data'] as Map?) ?? {});
      var dirty = false;
      raw.forEach((day, bellsRaw) {
        final bells = Map<String, dynamic>.from(bellsRaw as Map);
        bells.forEach((bell, entryRaw) {
          final e = Map<String, dynamic>.from(entryRaw as Map);
          if (e['teacherId'] == teacherId) {
            bells[bell] = {'teacherId': null, 'subject': null};
            dirty = true;
          }
        });
        raw[day] = bells;
      });
      if (dirty) batch.set(doc.reference, {'data': raw});
    }

    // d. Remove the allowed_users doc to revoke login access.
    if (resolvedTeacherEmail.isNotEmpty && resolvedTeacherEmail.contains('@')) {
      batch.delete(_db.collection('allowed_users').doc(resolvedTeacherEmail));
    }

    await batch.commit();

    // ── Best-effort: revoke Firebase Auth account ────────────────────────
    // Runs AFTER the batch so a transient Auth API failure cannot rollback
    // the data cleanup. The teacher is already fully removed from Firestore.
    if (resolvedTeacherEmail.isNotEmpty && resolvedTeacherEmail.contains('@')) {
      try {
        await _timetableService.deleteAccountFully(resolvedTeacherEmail);
      } catch (e) {
        // Non-fatal — Firestore data is already clean. Auth account will be
        // unable to resolve a role on next login anyway (allowed_users removed).
        AppLogger.d('TeacherDeletionService',
            'Post-approval Auth cleanup failed for $resolvedTeacherEmail: $e');
      }
    }
  }

  /// Rejects a pending request. [note] is shown back to the coordinator.
  Future<void> reject({
    required String schoolId,
    required String requestId,
    required String reviewerEmail,
    required String reviewerRole,
    String? reviewerName,
    String? note,
  }) async {
    await _collection(schoolId).doc(requestId).update({
      'status':         'rejected',
      'reviewedBy':     reviewerEmail.toLowerCase().trim(),
      'reviewedByRole': reviewerRole,
      'reviewedByName': reviewerName ?? '',
      'reviewedAt':     FieldValue.serverTimestamp(),
      'rejectionNote':  (note ?? '').trim(),
    });
  }

  /// Coordinator cancels their own pending request. The rules check that
  /// the caller matches `requestedBy`.
  Future<void> cancelMyRequest({
    required String schoolId,
    required String requestId,
  }) async {
    await _collection(schoolId).doc(requestId).update({
      'status':      'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _pack(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList();

  /// Convenience: returns the current user's session role+email+name from
  /// AuthService. Cached per call site rather than session.
  static Future<Map<String, String>> sessionUser() async {
    final s = await AuthService().getSession();
    if (s == null) return {'role': '', 'email': '', 'name': ''};
    return {
      'role':  (s['role']  as String?) ?? '',
      'email': (s['email'] as String?) ?? '',
      'name':  (s['name']  as String?) ?? '',
    };
  }
}
