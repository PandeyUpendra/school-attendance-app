import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../shared/utils/school_clock.dart';
import 'student_service.dart';
import '../models/exam.dart';
import '../models/homework.dart';
import 'exam_service.dart';
import 'homework_service.dart';

/// Stores pending attendance, marks, and homework saves locally when the device is offline.
/// When connectivity returns, call [syncAll] to flush the queues to Firestore.
class OfflineQueueService {
  static const _queueKey = 'attendance_offline_queue';
  static const _marksQueueKey = 'marks_offline_queue';
  static const _homeworkQueueKey = 'homework_offline_queue';

  /// A queued entry is abandoned once it has failed this many sync attempts or
  /// is older than [_maxAgeDays].
  static const _maxAttempts = 5;
  static const _maxAgeDays  = 21;

  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  final List<Future<dynamic> Function()> _syncQueue = [];
  bool _syncRunning = false;

  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _syncQueue.add(() async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    _runSyncQueue();
    return completer.future;
  }

  void _runSyncQueue() async {
    if (_syncRunning) return;
    _syncRunning = true;
    while (_syncQueue.isNotEmpty) {
      final task = _syncQueue.removeAt(0);
      try {
        await task();
      } catch (_) {}
    }
    _syncRunning = false;
  }

  // ── Attendance Enqueue ──────────────────────────────────────────────────────

  /// Queues attendance for [className] on [date] (defaults to today).
  Future<void> enqueue({
    required String className,
    required Map<int, String> attendance,
    DateTime? date,
  }) {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_queueKey);
      final list  = raw != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List).map((e) =>
                  Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];

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
    });
  }

  // ── Exam Results Enqueue ────────────────────────────────────────────────────

  /// Queues exam results for [examId].
  Future<void> enqueueExamResult({
    required String examId,
    required ExamResult result,
  }) {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_marksQueueKey);
      final list  = raw != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List).map((e) =>
                  Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];

      // Replace existing entry for same student+exam (last write wins)
      list.removeWhere((e) =>
          e['examId'] == examId && e['roll'] == result.roll && e['className'] == result.className);

      list.add({
        'examId': examId,
        'roll': result.roll,
        'className': result.className,
        'result': result.toJson(),
        'queuedAt': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      });

      await prefs.setString(_marksQueueKey, jsonEncode(list));
    });
  }

  // ── Homework Enqueue ────────────────────────────────────────────────────────

  /// Queues homework posting.
  Future<void> enqueueHomework({
    required String schoolId,
    required Homework homework,
  }) {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_homeworkQueueKey);
      final list  = raw != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List).map((e) =>
                  Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];

      list.add({
        'schoolId': schoolId,
        'homework': _serializeHomeworkForQueue(homework),
        'queuedAt': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      });

      await prefs.setString(_homeworkQueueKey, jsonEncode(list));
    });
  }

  // ── Queue sizes ────────────────────────────────────────────────────────────

  Future<int> pendingAttendanceCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_queueKey);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  Future<int> pendingMarksCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_marksQueueKey);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  Future<int> pendingHomeworkCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString(_homeworkQueueKey);
    if (raw == null) return 0;
    return (jsonDecode(raw) as List).length;
  }

  Future<int> pendingCount() async {
    return (await pendingAttendanceCount()) +
        (await pendingMarksCount()) +
        (await pendingHomeworkCount());
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
    int synced = 0;
    synced += await _syncAttendanceQueue();
    synced += await _syncMarksQueue();
    synced += await _syncHomeworkQueue();
    return synced;
  }

  Future<int> _syncAttendanceQueue() {
    return synchronized(() async {
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
          final attempts = ((entry['attempts'] as num?)?.toInt() ?? 0) + 1;
          final queuedAt = (entry['queuedAt'] as num?)?.toInt() ?? nowMs;
          final ageDays  = (nowMs - queuedAt) / (24 * 60 * 60 * 1000);
          if (attempts < _maxAttempts && ageDays <= _maxAgeDays) {
            failed.add({...entry, 'attempts': attempts});
          }
        }
      }

      if (failed.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setString(_queueKey, jsonEncode(failed));
      }

      return synced;
    });
  }

  Future<int> _syncMarksQueue() {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_marksQueueKey);
      if (raw == null || raw.isEmpty) return 0;

      final list = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) =>
              Map<String, dynamic>.from(e as Map)));

      int synced = 0;
      final failed = <Map<String, dynamic>>[];
      final nowMs  = DateTime.now().millisecondsSinceEpoch;

      for (final entry in list) {
        try {
          final examId = entry['examId'] as String;
          final resultData = Map<String, dynamic>.from(entry['result'] as Map);
          final result = ExamResult.fromDoc(resultData);

          await ExamService().saveResult(examId: examId, result: result);
          synced++;
        } catch (_) {
          final attempts = ((entry['attempts'] as num?)?.toInt() ?? 0) + 1;
          final queuedAt = (entry['queuedAt'] as num?)?.toInt() ?? nowMs;
          final ageDays  = (nowMs - queuedAt) / (24 * 60 * 60 * 1000);
          if (attempts < _maxAttempts && ageDays <= _maxAgeDays) {
            failed.add({...entry, 'attempts': attempts});
          }
        }
      }

      if (failed.isEmpty) {
        await prefs.remove(_marksQueueKey);
      } else {
        await prefs.setString(_marksQueueKey, jsonEncode(failed));
      }

      return synced;
    });
  }

  Future<int> _syncHomeworkQueue() {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_homeworkQueueKey);
      if (raw == null || raw.isEmpty) return 0;

      final list = List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) =>
              Map<String, dynamic>.from(e as Map)));

      int synced = 0;
      final failed = <Map<String, dynamic>>[];
      final nowMs  = DateTime.now().millisecondsSinceEpoch;

      for (final entry in list) {
        try {
          final schoolId = entry['schoolId'] as String;
          final hwData = Map<String, dynamic>.from(entry['homework'] as Map);
          final homework = _deserializeHomeworkFromQueue(hwData);

          await HomeworkService().postHomework(schoolId, homework);
          synced++;
        } catch (_) {
          final attempts = ((entry['attempts'] as num?)?.toInt() ?? 0) + 1;
          final queuedAt = (entry['queuedAt'] as num?)?.toInt() ?? nowMs;
          final ageDays  = (nowMs - queuedAt) / (24 * 60 * 60 * 1000);
          if (attempts < _maxAttempts && ageDays <= _maxAgeDays) {
            failed.add({...entry, 'attempts': attempts});
          }
        }
      }

      if (failed.isEmpty) {
        await prefs.remove(_homeworkQueueKey);
      } else {
        await prefs.setString(_homeworkQueueKey, jsonEncode(failed));
      }

      return synced;
    });
  }

  // ── Load cached attendance ─────────────────────────────────────────────────

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

  // ── Clear queues ───────────────────────────────────────────────────────────

  Future<void> clearAll() {
    return synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_queueKey);
      await prefs.remove(_marksQueueKey);
      await prefs.remove(_homeworkQueueKey);
    });
  }

  String _dateKey(DateTime d) => SchoolClock.dateKey(d);

  // ── Serialization Helpers ──────────────────────────────────────────────────

  Map<String, dynamic> _serializeHomeworkForQueue(Homework hw) => {
        'id': hw.id,
        'teacherId': hw.teacherId,
        'teacherName': hw.teacherName,
        'className': hw.className,
        'subject': hw.subject,
        'title': hw.title,
        'description': hw.description,
        'dueDate': hw.dueDate.toIso8601String(),
        'postedAt': hw.postedAt.toIso8601String(),
        'isReviewed': hw.isReviewed,
      };

  Homework _deserializeHomeworkFromQueue(Map<String, dynamic> json) => Homework(
        id: json['id'] as String? ?? '',
        teacherId: json['teacherId'] as String? ?? '',
        teacherName: json['teacherName'] as String? ?? '',
        className: json['className'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        dueDate: DateTime.parse(json['dueDate'] as String),
        postedAt: DateTime.parse(json['postedAt'] as String),
        isReviewed: json['isReviewed'] as bool? ?? false,
      );
}
