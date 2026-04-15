import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceService {
  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _attendanceKey(String className, DateTime date) =>
      'attendance_${className}_${_dateKey(date)}';

  static String _datesKey(String className) => 'attendanceDates_$className';

  static Future<void> saveAttendance({
    required String className,
    required DateTime date,
    required Map<int, bool> attendance,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Save attendance map as JSON: {"1": true, "2": false, ...}
    final Map<String, bool> serialized = {
      for (final entry in attendance.entries)
        entry.key.toString(): entry.value,
    };
    await prefs.setString(
      _attendanceKey(className, date),
      jsonEncode(serialized),
    );

    // Track the date in the list of dates for this class
    final datesKey = _datesKey(className);
    final existingDates = prefs.getStringList(datesKey) ?? [];
    final dateStr = _dateKey(date);
    if (!existingDates.contains(dateStr)) {
      existingDates.add(dateStr);
      existingDates.sort();
      await prefs.setStringList(datesKey, existingDates);
    }
  }

  static Future<Map<int, bool>?> loadAttendance({
    required String className,
    required DateTime date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_attendanceKey(className, date));
    if (raw == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(raw);
    return decoded.map((key, value) => MapEntry(int.parse(key), value as bool));
  }

  /// Returns a list of date strings (yyyy-MM-dd) that have saved attendance.
  static Future<List<String>> getSavedDates(String className) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_datesKey(className)) ?? [];
  }

  /// Loads attendance summary (present count, absent count, absent names) for a given date string.
  static Future<Map<String, dynamic>?> loadAttendanceSummary({
    required String className,
    required String dateStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;

    final key = 'attendance_${className}_$dateStr';
    final raw = prefs.getString(key);
    if (raw == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(raw);
    final Map<int, bool> attendance =
        decoded.map((k, v) => MapEntry(int.parse(k), v as bool));

    final int present = attendance.values.where((v) => v).length;
    final int absent = attendance.values.where((v) => !v).length;
    final List<int> absentRolls =
        attendance.entries.where((e) => !e.value).map((e) => e.key).toList();

    return {
      'present': present,
      'absent': absent,
      'absentRolls': absentRolls,
      'attendance': attendance,
    };
  }
}
