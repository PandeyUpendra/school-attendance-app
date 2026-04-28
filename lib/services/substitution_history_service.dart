import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/substitution_record.dart';

/// Tracks every substitution event for history and auto-suggest.
///
/// Firestore schema:
///   substitution_history/{auto}  →  SubstitutionRecord doc
class SubstitutionHistoryService {
  static final SubstitutionHistoryService _instance =
      SubstitutionHistoryService._internal();
  factory SubstitutionHistoryService() => _instance;
  SubstitutionHistoryService._internal();

  final _db  = FirebaseFirestore.instance;
  CollectionReference get _col => _db.collection('substitution_history');

  // ── Log a new substitution ─────────────────────────────────────────────────

  Future<void> logSubstitution(SubstitutionRecord record) async {
    await _col.add(record.toJson());
  }

  // ── Coordinator: full history, newest first ────────────────────────────────

  Future<List<SubstitutionRecord>> getHistory({int limit = 100}) async {
    final snap = await _col
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
    final snap = await _col
        .where('substituteTeacherId', isEqualTo: teacherId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => SubstitutionRecord.fromDoc(
            d.id, d.data() as Map<String, dynamic>))
        .toList();
  }

  // ── Auto-suggest: count substitutions per teacher in last [days] days ──────
  // Returns { teacherId → count } — lower count = better candidate

  Future<Map<String, int>> getSubstituteCounts({int days = 30}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final snap  = await _col
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
}
