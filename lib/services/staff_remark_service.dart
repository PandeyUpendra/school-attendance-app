import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/staff_remark.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Staff remark / feedback store.
///
/// All remarks live at `schools/{schoolId}/staff_remarks/{remarkId}`. Streams
/// avoid Firestore `orderBy` (which would force a composite index alongside the
/// `where` filters) and sort newest-first in Dart instead — mirroring
/// [StaffTaskService].
class StaffRemarkService extends BaseFirestoreService {
  static final StaffRemarkService _instance = StaffRemarkService._();
  factory StaffRemarkService() => _instance;
  StaffRemarkService._();

  CollectionReference<Map<String, dynamic>> get _remarks =>
      schoolCollection(AuthService.currentSchoolId, 'staff_remarks');

  // ── Writer ──────────────────────────────────────────────────────────────

  Future<void> addRemark(StaffRemark remark) async {
    final ref = _remarks.doc();
    await ref.set(remark.toJson());
  }

  Future<void> deleteRemark(String id) => _remarks.doc(id).delete();

  // ── Readers ─────────────────────────────────────────────────────────────

  /// Remarks given TO a teacher (addressed by teacherId), newest first.
  Stream<List<StaffRemark>> streamForTeacher(String teacherId) => _remarks
      .where('toTeacherId', isEqualTo: teacherId)
      .snapshots()
      .map(_sorted);

  /// Remarks given TO a coordinator (addressed by email), newest first.
  Stream<List<StaffRemark>> streamForCoordinator(String email) => _remarks
      .where('toEmail', isEqualTo: email)
      .where('toRole', isEqualTo: 'coordinator')
      .snapshots()
      .map(_sorted);

  /// Remarks GIVEN BY a member of management, newest first.
  Stream<List<StaffRemark>> streamGivenBy(String email) => _remarks
      .where('fromEmail', isEqualTo: email)
      .snapshots()
      .map(_sorted);

  // ── Helpers ─────────────────────────────────────────────────────────────

  List<StaffRemark> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs
        .map((d) => StaffRemark.fromJson(d.id, d.data()))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }
}
