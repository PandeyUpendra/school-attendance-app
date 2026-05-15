import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/student.dart';
import '../models/attendance_status.dart';
import 'firestore_service.dart';

/// Feature 2: Generates a CSV of attendance data and shares it via the
/// platform share sheet (WhatsApp, Email, Drive, etc.).
class ExportService {
  static Future<void> exportClassAttendance({
    required String className,
    required String schoolId,
    required List<Student> students,
  }) async {
    // 1. Get all attendance dates
    List<String> dates = [];
    if (schoolId.isNotEmpty) {
      dates = await FirestoreService.getAttendanceDates(
          schoolId: schoolId, classId: className);
    }
    // No local fallback available — dates come from Firestore only.

    // 2. Build CSV header
    final buffer = StringBuffer();
    buffer.write('Roll,Name,Parent Phone');
    for (final d in dates) {
      buffer.write(',$d');
    }
    buffer.writeln(',Present,Absent,On Leave,%');

    // 3. Per-student rows
    for (final student in students) {
      int present = 0, absent = 0, leave = 0;
      final row = StringBuffer(
          '${student.roll},"${student.name}","${student.parentPhone ?? ''}"');

      for (final date in dates) {
        Map<int, AttendanceStatus>? att;
        if (schoolId.isNotEmpty) {
          att = await FirestoreService.loadAttendance(
              schoolId: schoolId, classId: className, date: date);
        }
        // No local fallback — Firestore is the source of truth.

        final status = att?[student.roll] ?? AttendanceStatus.absent;
        row.write(',${status.code}');
        if (status.isPresent) {
          present++;
        } else if (status.isLeave) {
          leave++;
        } else {
          absent++;
        }
      }

      final total = dates.length;
      final pct =
          total > 0 ? (present / total * 100).toStringAsFixed(1) : '0.0';
      row.write(',$present,$absent,$leave,$pct%');
      buffer.writeln(row.toString());
    }

    // 4. Save to temp file
    final dir = await getTemporaryDirectory();
    final safeName =
        className.replaceAll(' ', '_').replaceAll('/', '_').replaceAll('-', '');
    final file = File('${dir.path}/${safeName}_attendance.csv');
    await file.writeAsString(buffer.toString());

    // 5. Share
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: '$className — Attendance Report',
    );
  }
}
