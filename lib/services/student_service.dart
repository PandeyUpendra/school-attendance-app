import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import '../models/student_remark.dart';

class StudentService {
  static final _db          = FirebaseFirestore.instance;
  static final _students    = _db.collection('students');
  static final _attendance  = _db.collection('attendance');

  static final StudentService _instance = StudentService._();
  StudentService._();
  factory StudentService() => _instance;

  // Firestore document ID — class name + section + roll, spaces → underscores
  String _sid(int roll, String className, [String section = '']) {
    final base = className.replaceAll(' ', '_');
    final sec = section.trim().replaceAll(' ', '_');
    return sec.isEmpty ? '${base}_$roll' : '${base}_${sec}_$roll';
  }

  // ── Students ──────────────────────────────────────────────────────────────

  Future<List<Student>> getStudents() async {
    final snap = await _students.get();
    final list = snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return list;
  }

  /// Fetch students for a class/section, optionally scoped to one teacher.
  /// Pass [teacherId] to return only students added by that class teacher.
  /// Omit it (or pass null) for coordinator/principal views that need all students.
  ///
  /// Note: if you add a teacherId filter alongside className+section, Firestore
  /// may require a composite index — the console error will include a direct link
  /// to create it.
  Future<List<Student>> getStudentsByClass(String className,
      {String section = '', String? teacherId}) async {
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: className);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    final snap = await q.get();
    final list = snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return list;
  }

  /// Real-time stream of students for a class/section.
  /// Emits a new sorted list on every Firestore change (add / update / delete).
  /// Pass [teacherId] to scope the stream to one class teacher's students only.
  Stream<List<Student>> watchStudentsByClass(String className,
      {String section = '', String? teacherId}) {
    Query<Map<String, dynamic>> q =
        _students.where('className', isEqualTo: className);
    if (section.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: section.trim());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }
    return q.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
          .toList()
        ..sort((a, b) => a.roll.compareTo(b.roll));
      return list;
    });
  }

  /// Real-time stream of ALL students across every class.
  /// Used by coordinator/principal dashboards to detect roster changes.
  Stream<List<Student>> watchStudents() {
    return _students.snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
          .toList()
        ..sort((a, b) => a.roll.compareTo(b.roll));
      return list;
    });
  }

  /// Returns a single student by class + section + roll (used by Guardian Portal).
  Future<Student?> getStudentByRoll(String className, int roll,
      {String section = ''}) async {
    final doc = await _students.doc(_sid(roll, className, section)).get();
    if (!doc.exists || doc.data() == null) return null;
    return Student.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  /// Fetch multiple students by list of rolls within a class.
  /// Fires all doc-gets in parallel via Future.wait() — O(N) reads, no sequential waits.
  Future<List<Student>> getStudentsByRolls(String className, List<int> rolls,
      {String section = ''}) async {
    if (rolls.isEmpty) return [];
    final results = await Future.wait(
      rolls.map((r) => getStudentByRoll(className, r, section: section)),
    );
    return results.whereType<Student>().toList();
  }

  /// Returns null on success, error string on duplicate roll.
  Future<String?> addStudent(Student student) async {
    final id  = _sid(student.roll, student.className, student.section);
    final doc = await _students.doc(id).get();
    if (doc.exists) {
      final sec = student.section.isNotEmpty ? ' Section ${student.section}' : '';
      return 'Roll number ${student.roll} already exists in ${student.className}$sec.';
    }
    await _students.doc(id).set(student.toJson());
    return null;
  }

  Future<void> updateStudent(Student updated) async {
    await _students
        .doc(_sid(updated.roll, updated.className, updated.section))
        .set(updated.toJson());
  }

  Future<void> removeStudent(int roll, String className,
      {String section = ''}) async {
    await _students.doc(_sid(roll, className, section)).delete();
    await _cascadeDeleteAttendance(roll, className, section: section);
  }

  /// Removes a student's roll number from every attendance document in their
  /// class+section. Uses a Firestore document-ID prefix query so only that
  /// class/section's attendance docs are scanned.
  Future<void> _cascadeDeleteAttendance(int roll, String className,
      {String section = ''}) async {
    final attKey = section.trim().isEmpty
        ? className
        : '$className ${section.trim()}';
    final prefix = '${attKey.replaceAll(' ', '_')}_';

    final snap = await _attendance
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
        .where(FieldPath.documentId, isLessThan: '$prefix■')
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in snap.docs) {
      final rolls = Map<String, dynamic>.from(
          (doc.data()['rolls'] as Map?) ?? {});
      if (rolls.containsKey(roll.toString())) {
        batch.update(doc.reference,
            {'rolls.$roll': FieldValue.delete()});
      }
    }
    await batch.commit();
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

  /// Builds today's attendance summary for every class in [classes].
  ///
  /// AttendanceScreen saves docs keyed as:
  ///   • no section  → "ClassName_YYYY-M-D"
  ///   • with section → "ClassName_Section_YYYY-M-D"
  /// Sections are derived from student records so coordinator/principal always
  /// read from the same keys the teacher wrote.
  Future<List<ClassSummary>> loadTodayFullSummary(
      List<String> classes) async {
    if (classes.isEmpty) return [];

    // 1. Fetch all students — needed to derive which sections each class has.
    final allStudentsSnap = await _students.get();

    // Group students by className, sorted by roll.
    final byClass = <String, List<Student>>{};
    for (final doc in allStudentsSnap.docs) {
      final s = Student.fromJson(Map<String, dynamic>.from(doc.data()));
      byClass.putIfAbsent(s.className, () => []).add(s);
    }
    for (final list in byClass.values) {
      list.sort((a, b) => a.roll.compareTo(b.roll));
    }

    // 2. Build attendance doc key(s) per class, mirroring AttendanceScreen._attendanceKey:
    //      no section  → className
    //      section set → "$className $section"
    //    then _todayKey(key) → "${key.replaceAll(' ','_')}_YYYY-M-D"
    final now     = DateTime.now();
    final dateSfx = '_${now.year}-${now.month}-${now.day}';

    final classToKeys = <String, List<String>>{};
    for (final cls in classes) {
      final sections = (byClass[cls] ?? [])
          .map((s) => s.section.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      classToKeys[cls] = sections.isEmpty
          ? ['${cls.replaceAll(' ', '_')}$dateSfx']
          : sections
              .map((sec) => '${cls.replaceAll(' ', '_')}_$sec$dateSfx')
              .toList();
    }

    // 3. Fetch every attendance doc in parallel (one per section per class).
    final allKeys = classToKeys.values.expand((k) => k).toList();
    final allDocs = await Future.wait(
        allKeys.map((k) => _attendance.doc(k).get()));
    final docsByKey = <String, DocumentSnapshot<Map<String, dynamic>>>{
      for (var i = 0; i < allKeys.length; i++) allKeys[i]: allDocs[i],
    };

    // 4. Merge all section docs into one ClassSummary per class.
    return List.generate(classes.length, (i) {
      final cls      = classes[i];
      final students = byClass[cls] ?? [];
      final keys     = classToKeys[cls] ?? [];

      final Map<int, String> attendance = {};
      final Map<int, String> reasons    = {};
      var   anyMarked = false;

      for (final key in keys) {
        final doc = docsByKey[key];
        if (doc == null || !doc.exists || doc.data() == null) continue;
        anyMarked = true;
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
        marked:      anyMarked,
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

  /// Returns roll → number of consecutive school days the student has been
  /// absent or on leave, counting backwards from today.
  /// Days with no attendance record (weekends, holidays) are skipped.
  Future<Map<int, int>> loadConsecutiveAbsenceDays(
      String className, {int maxDays = 20}) async {
    final now    = DateTime.now();
    final prefix = className.replaceAll(' ', '_');

    final docs = await Future.wait(
      List.generate(maxDays, (i) {
        final date = now.subtract(Duration(days: i));
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _attendance.doc(key).get();
      }),
    );

    final streaks = <int, int>{};
    final broken  = <int>{};

    for (final doc in docs) {
      if (!doc.exists || doc.data() == null) continue;
      final rolls = Map<String, dynamic>.from(
          (doc.data()!['rolls'] as Map?) ?? {});
      if (rolls.isEmpty) continue;

      rolls.forEach((rollStr, status) {
        final roll = int.tryParse(rollStr);
        if (roll == null || broken.contains(roll)) return;
        final isAbsent = status == 'Absent' || status == 'Leave' ||
            status == false;
        if (isAbsent) {
          streaks[roll] = (streaks[roll] ?? 0) + 1;
        } else {
          broken.add(roll);
        }
      });
    }
    return streaks;
  }

  // ── Remarks ───────────────────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _remarksRef(
      int roll, String className, [String section = '']) =>
      _students.doc(_sid(roll, className, section)).collection('remarks');

  /// Returns all remarks for a student, newest first.
  Future<List<StudentRemark>> getStudentRemarks(
      String className, int roll, {String section = ''}) async {
    final snap = await _remarksRef(roll, className, section)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => StudentRemark.fromJson(
            d.id, Map<String, dynamic>.from(d.data())))
        .toList();
  }

  /// Adds a remark. Throws [ArgumentError] if remark is empty or > 200 chars.
  Future<void> addStudentRemark(
    String className,
    int roll,
    String createdByEmail,
    String role,
    String remark, {
    String  section   = '',
    String? teacherId,
  }) async {
    final trimmed = remark.trim();
    if (trimmed.isEmpty || trimmed.length > 200) {
      throw ArgumentError('Remark must be 1–200 characters.');
    }
    await _remarksRef(roll, className, section).add({
      'createdBy': createdByEmail,
      'role':      role,
      'remark':    trimmed,
      'timestamp': FieldValue.serverTimestamp(),
      if (teacherId != null) 'teacherId': teacherId,
    });
  }

  /// Deletes a remark. Throws [StateError] if caller is not the author.
  Future<void> deleteStudentRemark(
    String className,
    int roll,
    String remarkId,
    String currentUserEmail, {
    String section = '',
  }) async {
    final ref = _remarksRef(roll, className, section).doc(remarkId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = Map<String, dynamic>.from(doc.data()!);
    if (data['createdBy'] != currentUserEmail) {
      throw StateError('You can only delete your own remarks.');
    }
    await ref.delete();
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
