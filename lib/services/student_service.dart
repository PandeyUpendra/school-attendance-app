import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';

class StudentService {
  static final _db          = FirebaseFirestore.instance;
  static final _students    = _db.collection('students');
  static final _attendance  = _db.collection('attendance');

  static final StudentService _instance = StudentService._();
  StudentService._();
  factory StudentService() => _instance;

  // Firestore document ID — class name + roll, spaces → underscores
  String _sid(int roll, String className) =>
      '${className.replaceAll(' ', '_')}_$roll';

  // ── Students ──────────────────────────────────────────────────────────────

  Future<List<Student>> getStudents() async {
    final snap = await _students.get();
    final list = snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return list;
  }

  Future<List<Student>> getStudentsByClass(String className) async {
    final snap = await _students
        .where('className', isEqualTo: className)
        .get();
    final list = snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return list;
  }

  /// Returns a single student by class + roll (used by Guardian Portal).
  Future<Student?> getStudentByRoll(String className, int roll) async {
    final doc = await _students.doc(_sid(roll, className)).get();
    if (!doc.exists || doc.data() == null) return null;
    return Student.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  /// Returns null on success, error string on duplicate roll.
  Future<String?> addStudent(Student student) async {
    final id  = _sid(student.roll, student.className);
    final doc = await _students.doc(id).get();
    if (doc.exists) {
      return 'Roll number ${student.roll} already exists in ${student.className}.';
    }
    await _students.doc(id).set(student.toJson());
    return null;
  }

  Future<void> updateStudent(Student updated) async {
    await _students.doc(_sid(updated.roll, updated.className)).set(updated.toJson());
  }

  Future<void> removeStudent(int roll, String className) async {
    await _students.doc(_sid(roll, className)).delete();
  }

  // ── Attendance ─────────────────────────────────────────────────────────────

  String _todayKey(String className) {
    final now = DateTime.now();
    // e.g. "Class_6_2026-4-19"
    return '${className.replaceAll(' ', '_')}_${now.year}-${now.month}-${now.day}';
  }

  /// Returns 'Present' | 'Absent' | 'Leave' per roll number.
  /// Backward-compatible: old bool values are migrated automatically.
  Future<Map<int, String>> loadTodayAttendance(String className) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final rolls = Map<String, dynamic>.from(
        (doc.data()!['rolls'] as Map?) ?? {});
    return rolls.map((k, v) {
      if (v is bool) return MapEntry(int.parse(k), v ? 'Present' : 'Absent');
      return MapEntry(int.parse(k), v as String);
    });
  }

  Future<void> saveAttendance(
      String className, Map<int, String> attendance) async {
    final rolls = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(_todayKey(className))
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  /// Save attendance for a specific date (used by offline sync).
  Future<void> saveAttendanceForDate(
      String className, Map<int, String> attendance, DateTime date) async {
    final prefix = className.replaceAll(' ', '_');
    final key    = '${prefix}_${date.year}-${date.month}-${date.day}';
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(key)
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  // ── Reasons (call notes after follow-up) ──────────────────────────────────

  Future<void> saveReasons(String className, Map<int, String> reasons) async {
    if (reasons.isEmpty) return;
    final raw = reasons.map((k, v) => MapEntry(k.toString(), v));
    await _attendance.doc(_todayKey(className)).set(
      {'reasons': raw, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<Map<int, String>> loadTodayReasons(String className) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['reasons'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  // ── Coordinator summary across all classes ────────────────────────────────

  /// Maximum-speed summary:
  ///   • 1 Firestore query  — fetches ALL students at once (not N per-class queries)
  ///   • N Firestore reads  — one attendance doc per class (contains BOTH rolls AND reasons)
  ///   • All fired in parallel before any await
  ///
  /// For 5 classes: was 15+ reads → now 6 reads total.
  Future<List<ClassSummary>> loadTodayFullSummary(
      List<String> classes) async {
    if (classes.isEmpty) return [];

    // Fire all futures immediately (eager — they run concurrently in parallel)
    final allStudentsFuture = _students.get();          // 1 query for all students
    final attendanceFuture  = Future.wait(              // N doc-gets in parallel
      classes.map((cls) => _attendance.doc(_todayKey(cls)).get()),
    );

    // Await both concurrently
    final allStudentsSnap = await allStudentsFuture;
    final attendanceDocs  = await attendanceFuture;

    // Group students by class (in-memory, zero extra reads)
    final byClass = <String, List<Student>>{};
    for (final doc in allStudentsSnap.docs) {
      final s = Student.fromJson(Map<String, dynamic>.from(doc.data()));
      byClass.putIfAbsent(s.className, () => []).add(s);
    }
    for (final list in byClass.values) {
      list.sort((a, b) => a.roll.compareTo(b.roll));
    }

    // Build each ClassSummary from the already-fetched attendance doc
    return List.generate(classes.length, (i) {
      final cls      = classes[i];
      final doc      = attendanceDocs[i];
      final students = byClass[cls] ?? [];

      final Map<int, String> attendance = {};
      final Map<int, String> reasons    = {};

      if (doc.exists && doc.data() != null) {
        final data       = Map<String, dynamic>.from(doc.data() as Map);
        final rollsRaw   = Map<String, dynamic>.from((data['rolls']   as Map?) ?? {});
        final reasonsRaw = Map<String, dynamic>.from((data['reasons'] as Map?) ?? {});

        rollsRaw.forEach((k, v) {
          attendance[int.parse(k)] =
              v is bool ? (v ? 'Present' : 'Absent') : (v as String);
        });
        reasonsRaw.forEach((k, v) => reasons[int.parse(k)] = v as String);
      }

      final present = students.where((s) => attendance[s.roll] == 'Present').length;
      final leave   = students.where((s) => attendance[s.roll] == 'Leave').length;
      final absent  = students.where((s) => attendance[s.roll] == 'Absent').length;

      final absentLeave = students
          .where((s) =>
              attendance[s.roll] == 'Absent' ||
              attendance[s.roll] == 'Leave')
          .map((s) => StudentNote(
                name:   s.name,
                roll:   s.roll,
                status: attendance[s.roll] ?? 'Absent',
                reason: reasons[s.roll],
                phone:  s.phone,
              ))
          .toList();

      return ClassSummary(
        className:   cls,
        total:       students.length,
        present:     present,
        leave:       leave,
        absent:      absent,
        marked:      attendance.isNotEmpty,
        absentLeave: absentLeave,
      );
    });
  }

  /// Returns roll → absent+leave count over the last [days] days (default 14).
  /// Parallel Firestore reads — all days fetched simultaneously.
  Future<Map<int, int>> loadRecentAbsenceDays(
      String className, {int days = 14}) async {
    final now    = DateTime.now();
    final prefix = className.replaceAll(' ', '_');

    // Fetch all docs in parallel
    final docs = await Future.wait(
      List.generate(days, (i) {
        final date = now.subtract(Duration(days: i));
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _attendance.doc(key).get();
      }),
    );

    final result = <int, int>{};
    for (final doc in docs) {
      if (!doc.exists || doc.data() == null) continue;
      final rolls = Map<String, dynamic>.from(
          (doc.data()!['rolls'] as Map?) ?? {});
      rolls.forEach((rollStr, status) {
        if (status == 'Absent' || status == 'Leave' || status == false) {
          final roll = int.tryParse(rollStr);
          if (roll != null) result[roll] = (result[roll] ?? 0) + 1;
        }
      });
    }
    return result;
  }

  // ── Call tracking ──────────────────────────────────────────────────────────

  /// Save which students have been called (roll → true/false).
  Future<void> saveCalled(String className, Map<int, bool> called) async {
    if (called.isEmpty) return;
    final raw = called.map((k, v) => MapEntry(k.toString(), v));
    await _attendance.doc(_todayKey(className)).set(
      {'called': raw, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<Map<int, bool>> loadTodayCalled(String className) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['called'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(int.parse(k), v as bool? ?? false));
  }

  /// Loads every attendance document for a class in a given month.
  /// Returns: { day → { roll → 'Present'|'Absent'|'Leave' } }
  /// Only days that have any records are included (i.e. days school was open).
  /// All day-reads are fired in parallel — max 31 Firestore reads.
  Future<Map<int, Map<int, String>>> loadMonthAttendance(
      String className, int year, int month) async {
    final prefix     = className.replaceAll(' ', '_');
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final docs = await Future.wait(
      List.generate(daysInMonth, (i) {
        final day = i + 1;
        return _attendance.doc('${prefix}_$year-$month-$day').get();
      }),
    );

    final result = <int, Map<int, String>>{};
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (!doc.exists || doc.data() == null) continue;
      final rolls = Map<String, dynamic>.from(
          (doc.data()!['rolls'] as Map?) ?? {});
      if (rolls.isEmpty) continue;
      result[i + 1] = rolls.map((k, v) {
        if (v is bool) return MapEntry(int.parse(k), v ? 'Present' : 'Absent');
        return MapEntry(int.parse(k), v as String);
      });
    }
    return result;
  }

  /// Load attendance doc for a specific date (for history).
  Future<Map<String, dynamic>?> loadAttendanceForDate(
      String className, DateTime date) async {
    final key =
        '${className.replaceAll(' ', '_')}_${date.year}-${date.month}-${date.day}';
    final doc = await _attendance.doc(key).get();
    if (!doc.exists || doc.data() == null) return null;
    return Map<String, dynamic>.from(doc.data()!);
  }
}

// ── Data classes for summary (public — used by coordinator screens) ──────────

class ClassSummary {
  final String className;
  final int    total, present, leave, absent;
  final bool   marked;
  final List<StudentNote> absentLeave;

  const ClassSummary({
    required this.className,
    required this.total,
    required this.present,
    required this.leave,
    required this.absent,
    required this.marked,
    required this.absentLeave,
  });
}

class StudentNote {
  final String  name;
  final int     roll;
  final String  status;
  final String? reason;
  final String  phone;
  const StudentNote({
    required this.name,
    required this.roll,
    required this.status,
    required this.reason,
    required this.phone,
  });
}
