import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/attendance_status.dart';
import 'base_firestore_service.dart';

/// Service for managing student attendance.
/// Follows Clean Architecture by separating Firestore logic from UI.
class AttendanceService extends BaseFirestoreService {
  static final AttendanceService _instance = AttendanceService._();
  AttendanceService._();
  factory AttendanceService() => _instance;

  CollectionReference<Map<String, dynamic>> _attendanceCol(String schoolId) =>
      db.collection('schools').doc(schoolId).collection('attendance');

  /// Saves attendance for a class on a specific date.
  /// Uses a standardized key format: {classId}_{date}
  Future<void> saveAttendance({
    required String schoolId,
    required String classId,
    required DateTime date,
    required Map<int, AttendanceStatus> attendance,
  }) async {
    final dateStr = _formatDate(date);
    final docId = '${classId}_$dateStr';

    final data = {
      'classId': classId,
      'date': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
      'rolls': {
        for (final e in attendance.entries) e.key.toString(): e.value.code,
      },
    };

    try {
      await _attendanceCol(schoolId).doc(docId).set(data, SetOptions(merge: true));
    } catch (e, stack) {
      handleError(e, stack);
      rethrow;
    }
  }

  /// Loads attendance for a class on a specific date.
  Future<Map<int, AttendanceStatus>?> loadAttendance({
    required String schoolId,
    required String classId,
    required DateTime date,
  }) async {
    final dateStr = _formatDate(date);
    final docId = '${classId}_$dateStr';

    try {
      final doc = await _attendanceCol(schoolId).doc(docId).get();
      if (!doc.exists || doc.data() == null) return null;

      final rolls = doc.data()!['rolls'] as Map<String, dynamic>?;
      if (rolls == null) return null;

      return rolls.map(
          (k, v) => MapEntry(int.parse(k), AttendanceStatus.fromValue(v)));
    } catch (e, stack) {
      handleError(e, stack);
      return null;
    }
  }

  /// Gets a stream of attendance for a class on a specific date.
  Stream<Map<int, AttendanceStatus>?> watchAttendance({
    required String schoolId,
    required String classId,
    required DateTime date,
  }) {
    final dateStr = _formatDate(date);
    final docId = '${classId}_$dateStr';

    return _attendanceCol(schoolId).doc(docId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      final rolls = doc.data()!['rolls'] as Map<String, dynamic>?;
      if (rolls == null) return null;
      return rolls.map(
          (k, v) => MapEntry(int.parse(k), AttendanceStatus.fromValue(v)));
    });
  }

  /// Generates a summary for a class on a specific date.
  Future<Map<String, dynamic>?> getAttendanceSummary({
    required String schoolId,
    required String classId,
    required DateTime date,
  }) async {
    final att = await loadAttendance(
        schoolId: schoolId, classId: classId, date: date);
    if (att == null) return null;

    return {
      'present': att.values.where((v) => v.isPresent).length,
      'absent': att.values.where((v) => v.isAbsent).length,
      'leave': att.values.where((v) => v.isLeave).length,
      'total': att.length,
      'data': att,
    };
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
