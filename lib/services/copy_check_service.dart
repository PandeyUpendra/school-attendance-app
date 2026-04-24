import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/copy_check.dart';
import '../models/timetable_entry.dart';
import 'timetable_service.dart';

/// Manages copy-checking sessions.
///
/// Schema:
///   copy_checks/{checkId}             → CopyCheck doc
///   copy_checks/{checkId}/statuses/{roll} → CopyStatus doc
class CopyCheckService {
  static final _db    = FirebaseFirestore.instance;
  static final _coll  = _db.collection('copy_checks');

  static final CopyCheckService _instance = CopyCheckService._();
  CopyCheckService._();
  factory CopyCheckService() => _instance;

  CollectionReference _statuses(String checkId) =>
      _coll.doc(checkId).collection('statuses');

  // ── Teacher's classes from timetable ──────────────────────────────────────

  /// Returns { className → subject } for all classes the teacher appears in.
  Future<Map<String, String>> getClassesForTeacher(String teacherId) async {
    final tt      = await TimetableService().getTimetable();
    final result  = <String, String>{};
    for (final clsEntry in tt.entries) {
      for (final dayEntry in clsEntry.value.entries) {
        for (final bellEntry in dayEntry.value.entries) {
          final entry = bellEntry.value;
          if (entry.teacherId == teacherId) {
            result.putIfAbsent(clsEntry.key, () => entry.subject ?? '');
          }
        }
      }
    }
    return result;
  }

  // ── Copy checks ────────────────────────────────────────────────────────────

  /// Get all checking sessions for a teacher in a class.
  Future<List<CopyCheck>> getChecks({
    required String teacherId,
    String? className,
  }) async {
    Query q = _coll.where('teacherId', isEqualTo: teacherId);
    if (className != null) {
      q = q.where('className', isEqualTo: className);
    }
    final snap = await q.get();
    final list = snap.docs
        .map((d) =>
            CopyCheck.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => b.checkDate.compareTo(a.checkDate));
    return list;
  }

  /// Get ALL checking sessions — for coordinator overview.
  Future<List<CopyCheck>> getAllChecks({String? className}) async {
    Query q = _coll;
    if (className != null) {
      q = q.where('className', isEqualTo: className);
    }
    final snap = await q.get();
    return snap.docs
        .map((d) =>
            CopyCheck.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => b.checkDate.compareTo(a.checkDate));
  }

  Future<String> createCheck(CopyCheck check) async {
    final ref = await _coll.add(check.toJson());
    return ref.id;
  }

  Future<void> deleteCheck(String checkId) async {
    await _coll.doc(checkId).delete();
  }

  // ── Student statuses ───────────────────────────────────────────────────────

  Future<List<CopyStatus>> getStatuses(String checkId) async {
    final snap = await _statuses(checkId).get();
    return snap.docs
        .map((d) => CopyStatus.fromDoc(Map<String, dynamic>.from(d.data() as Map)))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  Future<void> saveStatuses(
      String checkId, List<CopyStatus> statuses) async {
    final batch = _db.batch();
    for (final s in statuses) {
      batch.set(_statuses(checkId).doc('${s.roll}'), s.toJson());
    }
    await batch.commit();
  }

  /// Returns students whose status is 'incomplete' or 'not_done'.
  Future<List<CopyStatus>> getPendingStatuses(String checkId) async {
    final all = await getStatuses(checkId);
    return all
        .where((s) => s.status == 'incomplete' || s.status == 'not_done')
        .toList();
  }
}
