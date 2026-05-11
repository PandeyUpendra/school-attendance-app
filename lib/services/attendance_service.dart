import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student.dart';
import '../models/attendance_status.dart';

class AttendanceService {
  static String _studentsKey(String className) => 'students_$className';

  // ── Photo ────────────────────────────────────────────────────────────────

  /// Copies a picked photo to permanent app storage and returns the new path.
  static Future<String> saveStudentPhoto(
      String sourcePath, String className, int roll) async {
    final dir = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${dir.path}/student_photos');
    if (!photosDir.existsSync()) photosDir.createSync(recursive: true);

    final dest = '${photosDir.path}/${className}_$roll.jpg'
        .replaceAll(' ', '_');
    await File(sourcePath).copy(dest);
    return dest;
  }

  // ── Students ─────────────────────────────────────────────────────────────

  static Future<void> saveStudents(
      String className, List<Student> students) async {
    final prefs = await SharedPreferences.getInstance();
    final data = students
        .map((s) => {
              'roll': s.roll,
              'name': s.name,
              'parentPhone': s.parentPhone,
              'photoPath': s.photoPath,
              'photoUrl': s.photoUrl,
            })
        .toList();
    await prefs.setString(_studentsKey(className), jsonEncode(data));
  }

  static Future<List<Student>?> loadStudents(String className) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_studentsKey(className));
    if (raw == null) return null;

    final List<dynamic> decoded = jsonDecode(raw);
    return decoded
        .map((e) => Student.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── Attendance ───────────────────────────────────────────────────────────

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _attendanceKey(String className, DateTime date) =>
      'attendance_${className}_${_dateKey(date)}';

  static String _datesKey(String className) => 'attendanceDates_$className';

  /// Saves attendance using single-letter status codes ('P', 'A', 'L').
  static Future<void> saveAttendance({
    required String className,
    required DateTime date,
    required Map<int, AttendanceStatus> attendance,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, String> serialized = {
      for (final entry in attendance.entries)
        entry.key.toString(): entry.value.code,
    };
    await prefs.setString(
      _attendanceKey(className, date),
      jsonEncode(serialized),
    );

    final datesKey = _datesKey(className);
    final existingDates = prefs.getStringList(datesKey) ?? [];
    final dateStr = _dateKey(date);
    if (!existingDates.contains(dateStr)) {
      existingDates.add(dateStr);
      existingDates.sort();
      await prefs.setStringList(datesKey, existingDates);
    }
  }

  /// Loads attendance with backward-compatible bool → AttendanceStatus parsing.
  static Future<Map<int, AttendanceStatus>?> loadAttendance({
    required String className,
    required DateTime date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_attendanceKey(className, date));
    if (raw == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(raw);
    return decoded.map((key, value) =>
        MapEntry(int.parse(key), AttendanceStatus.fromValue(value)));
  }

  static Future<List<String>> getSavedDates(String className) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_datesKey(className)) ?? [];
  }

  static Future<Map<String, dynamic>?> loadAttendanceSummary({
    required String className,
    required String dateStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'attendance_${className}_$dateStr';
    final raw = prefs.getString(key);
    if (raw == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(raw);
    final Map<int, AttendanceStatus> attendance =
        decoded.map((k, v) => MapEntry(int.parse(k), AttendanceStatus.fromValue(v)));

    final int present =
        attendance.values.where((v) => v.isPresent).length;
    final int absent =
        attendance.values.where((v) => v.isAbsent).length;
    final int leave =
        attendance.values.where((v) => v.isLeave).length;

    return {
      'present': present,
      'absent': absent,
      'leave': leave,
      'attendance': attendance,
    };
  }
}
