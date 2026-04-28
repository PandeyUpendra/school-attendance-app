import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'student_service.dart';

/// Stores pending attendance saves locally when the device is offline.
/// When connectivity returns, call [syncAll] to flush the queue to Firestore.
///
/// Queue format in SharedPreferences key 'attendance_offline_queue':
///   List<Map> where each entry is:
///   {
///     'className': String,
///     'dateKey':   'YYYY-M-D',
///     'rolls':     { '1': 'Present', '2': 'Absent', ... },
///     'queuedAt':  millisecondsSinceEpoch,
///   }
///
/// Duplicate check: if an entry for the same className+dateKey already exists
/// in the queue, it is replaced (last write wins for the same class+day).
class OfflineQueueService {
  static const _queueKey = 'attendance_offline_queue';

  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  // ── Enqueue ────────────────────────────────────────────────────────────────

  Future<void> enqueue({
    required String className,
    required Map<int, String> attendance,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    final list  = raw != null
        ? List<Map<String, dynamic>>.from(
            (jsonDecode(raw) as List).map((e) =>
                Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    final dateKey = _todayKey();

    // Replace existing entry for same class+day (last write wins)
    list.removeWhere((e) =>
        e['className'] == className && e['dateKey'] == dateKey);

    list.add({
      'className': className,
      'dateKey':   dateKey,
      'rolls':     attendance.map((k, v) => MapEntry(k.toString(), v)),
      'queuedAt':  DateTime.now().millisecondsSinceEpoch,
    });

    await prefs.setString(_queueKey, jsonEncode(list));
  }

  // ── Queue size ─────────────────────────────────────────────────────────────

  Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  // ── Sync all pending entries to Firestore ──────────────────────────────────

  /// Returns the number of records successfully synced.
  Future<int> syncAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return 0;

    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) =>
            Map<String, dynamic>.from(e as Map)));

    int synced = 0;
    final failed = <Map<String, dynamic>>[];

    for (final entry in list) {
      try {
        final className = entry['className'] as String;
        final rollsRaw  = Map<String, dynamic>.from(
            entry['rolls'] as Map? ?? {});
        final attendance = rollsRaw.map(
            (k, v) => MapEntry(int.parse(k), v as String));

        // Save to Firestore using the normal service
        // We temporarily override the today-key by saving on the correct date
        final dateKey = entry['dateKey'] as String;
        final parts   = dateKey.split('-');
        final date    = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));

        await StudentService().saveAttendanceForDate(
          className, attendance, date);
        synced++;
      } catch (_) {
        // Keep failed entries for retry
        failed.add(entry);
      }
    }

    // Update queue: remove synced, keep failed
    if (failed.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setString(_queueKey, jsonEncode(failed));
    }

    return synced;
  }

  // ── Load today's cached attendance (if any) ────────────────────────────────

  Future<Map<int, String>?> getCachedAttendance(String className) async {
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getString(_queueKey);
    if (raw == null) return null;

    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) =>
            Map<String, dynamic>.from(e as Map)));

    final dateKey = _todayKey();
    final entry   = list.where((e) =>
        e['className'] == className && e['dateKey'] == dateKey).firstOrNull;

    if (entry == null) return null;

    final rollsRaw = Map<String, dynamic>.from(entry['rolls'] as Map? ?? {});
    return rollsRaw.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  // ── Clear queue ────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  String _todayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }
}
