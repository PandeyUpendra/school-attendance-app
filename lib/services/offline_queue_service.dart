import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/school_clock.dart';
import 'student_service.dart';

/// Stores pending attendance saves locally when the device is offline.
/// When connectivity returns, call [syncAll] to flush the queue to Firestore.
///
/// Queue format in SharedPreferences key 'attendance_offline_queue':
///   List<Map> where each entry is:
///   {
///     'className': String,
///     'dateKey':   'YYYY-MM-DD',
///     'rolls':     { '1': 'Present', '2': 'Absent', ... },
///     'queuedAt':  millisecondsSinceEpoch,
///   }
///
/// Duplicate check: if an entry for the same className+dateKey already exists
/// in the queue, it is replaced (last write wins for the same class+day).
class OfflineQueueService {
  static const _queueKey = 'attendance_offline_queue';

  /// A queued entry is abandoned once it has failed this many sync attempts or
  /// is older than [_maxAgeDays] — so a permanently-rejected record (e.g. a
  /// deleted class) stops re-failing on every connectivity change (#66).
  static const _maxAttempts = 5;
  static const _maxAgeDays  = 21;

  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  // ── Enqueue ────────────────────────────────────────────────────────────────

  /// Queues attendance for [className] on [date] (defaults to today). Passing
  /// the actual date being edited keeps backdated attendance taken offline from
  /// being saved under today's date on sync (#63).
  Future<void> enqueue({
    required String className,
    required Map<int, String> attendance,
    DateTime? date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    final list  = raw != null
        ? List<Map<String, dynamic>>.from(
            (jsonDecode(raw) as List).map((e) =>
                Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    // Default "today" to the school timezone so an offline mark queues under the
    // same calendar day the online path would use (#43).
    final dateKey = _dateKey(date ?? SchoolClock.now());

    // Replace existing entry for same class+day (last write wins)
    list.removeWhere((e) =>
        e['className'] == className && e['dateKey'] == dateKey);

    list.add({
      'className': className,
      'dateKey':   dateKey,
      'rolls':     attendance.map((k, v) => MapEntry(k.toString(), v)),
      'queuedAt':  DateTime.now().millisecondsSinceEpoch,
      'attempts':  0,
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

  Future<Map<String, int>> pendingCountsByClass() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    if (raw == null) return {};
    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) =>
            Map<String, dynamic>.from(e as Map)));
    final counts = <String, int>{};
    for (final entry in list) {
      final className = entry['className'] as String? ?? '';
      if (className.isNotEmpty) {
        counts[className] = (counts[className] ?? 0) + 1;
      }
    }
    return counts;
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
    final nowMs  = DateTime.now().millisecondsSinceEpoch;

    for (final entry in list) {
      try {
        final className = entry['className'] as String;
        final rollsRaw  = Map<String, dynamic>.from(
            entry['rolls'] as Map? ?? {});
        final attendance = <int, String>{};
        rollsRaw.forEach((k, v) {
          final r = int.tryParse(k);
          if (r != null) {
            attendance[r] = v as String;
          }
        });

        // Save to Firestore using the normal service
        // We temporarily override the today-key by saving on the correct date
        final dateKey = entry['dateKey'] as String;
        final parts   = dateKey.split('-');
        final year    = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? SchoolClock.now().year) : SchoolClock.now().year;
        final month   = parts.length > 1 ? (int.tryParse(parts[1]) ?? SchoolClock.now().month) : SchoolClock.now().month;
        final day     = parts.length > 2 ? (int.tryParse(parts[2]) ?? SchoolClock.now().day) : SchoolClock.now().day;
        final date    = DateTime(year, month, day);

        await StudentService.instance.saveAttendanceForDate(
          className: className, attendance: attendance, date: date);
        synced++;
      } catch (_) {
        // Bump the attempt count and re-queue for retry — UNLESS the entry has
        // exhausted its attempts or aged out, in which case it is abandoned so
        // a permanently-rejected record can't re-fail forever (#66).
        final attempts = ((entry['attempts'] as num?)?.toInt() ?? 0) + 1;
        final queuedAt = (entry['queuedAt'] as num?)?.toInt() ?? nowMs;
        final ageDays  = (nowMs - queuedAt) / (24 * 60 * 60 * 1000);
        if (attempts < _maxAttempts && ageDays <= _maxAgeDays) {
          failed.add({...entry, 'attempts': attempts});
        }
        // else: drop the entry (give up).
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

  Future<Map<int, String>?> getCachedAttendance(String className,
      {DateTime? date}) async {
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getString(_queueKey);
    if (raw == null) return null;

    final list = List<Map<String, dynamic>>.from(
        (jsonDecode(raw) as List).map((e) =>
            Map<String, dynamic>.from(e as Map)));

    final dateKey = _dateKey(date ?? SchoolClock.now());
    final entry   = list.where((e) =>
        e['className'] == className && e['dateKey'] == dateKey).firstOrNull;

    if (entry == null) return null;

    final rollsRaw = Map<String, dynamic>.from(entry['rolls'] as Map? ?? {});
    final attendance = <int, String>{};
    rollsRaw.forEach((k, v) {
      final r = int.tryParse(k);
      if (r != null) {
        attendance[r] = v as String;
      }
    });
    return attendance;
  }

  // ── Clear queue ────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  /// Delegates to [SchoolClock.dateKey] so all date keys are ISO 8601
  /// zero-padded (`YYYY-MM-DD`) and lexicographically sortable (#109).
  String _dateKey(DateTime d) => SchoolClock.dateKey(d);
}
