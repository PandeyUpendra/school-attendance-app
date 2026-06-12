import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/substitution_record.dart';
import 'auth_service.dart';

/// Tracks every substitution event for history and auto-suggest.
///
/// Firestore schema:
///   substitution_history/{auto}  →  SubstitutionRecord doc
class SubstitutionHistoryService {
  static SubstitutionHistoryService? _instance;
  SubstitutionHistoryService._internal();
  factory SubstitutionHistoryService() => _instance ??= SubstitutionHistoryService._internal();
  static set mockInstance(SubstitutionHistoryService? mock) => _instance = mock;

  final _db  = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('substitution_history');

  // ── Log a new substitution ─────────────────────────────────────────────────

  Future<void> logSubstitution(SubstitutionRecord record) async {
    // Stamp schoolId on this root collection for later tenant-filtering
    // (Phase 1 multi-tenancy prep). Read filtering follows the backfill.
    await _col.add({...record.toJson(), 'schoolId': AuthService.currentSchoolId});
  }

  // ── Coordinator: full history, newest first ────────────────────────────────

  Future<List<SubstitutionRecord>> getHistory({int limit = 100}) async {
    // schoolId filter required by the tenant-scoped read rule (needs the
    // schoolId+createdAt composite index in firestore.indexes.json).
    final snap = await _col
        .where('schoolId', isEqualTo: AuthService.currentSchoolId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => SubstitutionRecord.fromDoc(
            d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Teacher: their own duties as substitute ────────────────────────────────

  Future<List<SubstitutionRecord>> getHistoryForTeacher(
      String teacherId, {int limit = 50}) async {
    // Single-field equality filter only — avoids a composite index requirement
    // (which, when missing, throws FAILED_PRECONDITION and would hang the
    // screen). Sort newest-first client-side instead.
    final snap = await _col
        .where('schoolId', isEqualTo: AuthService.currentSchoolId)
        .where('substituteTeacherId', isEqualTo: teacherId)
        .get();
    final records = snap.docs
        .map((d) => SubstitutionRecord.fromDoc(
            d.id, d.data() as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return records.length > limit ? records.sublist(0, limit) : records;
  }

  // ── Auto-suggest: count substitutions per teacher in last [days] days ──────
  // Returns { teacherId → count } — lower count = better candidate

  Future<Map<String, int>> getSubstituteCounts({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    // schoolId filter required by the tenant-scoped read rule (needs the
    // schoolId+date composite index in firestore.indexes.json).
    final snap  = await _col
        .where('schoolId', isEqualTo: AuthService.currentSchoolId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();

    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final tid = (doc.data() as Map<String, dynamic>)['substituteTeacherId']
          as String?;
      if (tid != null && tid.isNotEmpty) {
        counts[tid] = (counts[tid] ?? 0) + 1;
      }
    }
    return counts;
  }

  // ── Delete a history record ────────────────────────────────────────────────

  Future<void> deleteRecord(String id) async {
    await _col.doc(id).delete();
  }

  // ── Stream today's substitutions for a school ──────────────────────────────
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamSubstitutions(String todayKey) {
    return _db
        .collection('schools')
        .doc(AuthService.currentSchoolId)
        .collection('substitutions')
        .doc(todayKey)
        .snapshots();
  }
}
