import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import 'base_firestore_service.dart';

class StudentService extends BaseFirestoreService {
  static final StudentService _instance = StudentService._();
  StudentService._();
  factory StudentService() => _instance;

  CollectionReference<Map<String, dynamic>> _students(String schoolId) =>
      schoolCollection(schoolId, 'students');
  CollectionReference<Map<String, dynamic>> _attendance(String schoolId) =>
      schoolCollection(schoolId, 'attendance');

  // ── Students ──────────────────────────────────────────────────────────────

  Future<List<Student>> getStudents({String? schoolId}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final snap = await _students(sId).get();
    final list = snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
    return list;
  }

  Future<Student?> getStudentById({String? schoolId, required String id}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _students(sId).doc(id).get();
    if (doc.exists && doc.data() != null) {
      return Student.fromJson(Map<String, dynamic>.from(doc.data()!));
    }
    return null;
  }

  Future<List<Student>> getStudentsByClass({
    String? schoolId,
    required String className,
    String section = '',
    String? teacherId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    String effectiveClass = className;
    String effectiveSection = section;

    if (effectiveSection.isEmpty && className.contains(' ')) {
      final parts = className.split(' ');
      final last = parts.last;
      if (last.length <= 5) {
        effectiveSection = last;
        effectiveClass   = parts.sublist(0, parts.length - 1).join(' ');
      }
    }

    Query<Map<String, dynamic>> q =
        _students(sId).where('className', isEqualTo: effectiveClass);
    if (effectiveSection.trim().isNotEmpty) {
      q = q.where('section', isEqualTo: effectiveSection.trim());
    }
    if (teacherId != null && teacherId.isNotEmpty) {
      q = q.where('teacherId', isEqualTo: teacherId);
    }

    final snap = await q.get();
    return snap.docs
        .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
        .toList()
      ..sort((a, b) => a.roll.compareTo(b.roll));
  }

  Stream<List<Student>> watchStudentsByClass({
    String? schoolId,
    required String className,
    String section = '',
    String? teacherId,
  }) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    Query<Map<String, dynamic>> q =
        _students(sId).where('className', isEqualTo: className);
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

  Stream<List<Student>> watchStudents({String? schoolId}) {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    return _students(sId).snapshots().map((snap) {
      final list = snap.docs
          .map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
          .toList()
        ..sort((a, b) => a.roll.compareTo(b.roll));
      return list;
    });
  }

  Future<Student?> getStudentByRoll({
    String? schoolId,
    required String className,
    required int roll,
    String section = '',
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _students(sId).doc(sidFromParts(roll, className, section)).get();
    if (!doc.exists || doc.data() == null) return null;
    return Student.fromJson(Map<String, dynamic>.from(doc.data()!));
  }

  Future<List<Student>> getStudentsByRolls({
    String? schoolId,
    required String className,
    required List<int> rolls,
    String section = '',
  }) async {
    if (rolls.isEmpty) return [];
    final results = await Future.wait(
      rolls.map((r) => getStudentByRoll(schoolId: schoolId, className: className, roll: r, section: section)),
    );
    return results.whereType<Student>().toList();
  }

  Future<String?> addStudent({String? schoolId, required Student student}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final id  = sid(student);
    final doc = await _students(sId).doc(id).get();
    if (doc.exists) {
      final sec = student.section.isNotEmpty ? ' Section ${student.section}' : '';
      return 'Roll number ${student.roll} already exists in ${student.className}$sec.';
    }
    await _students(sId).doc(id).set(student.toJson());
    return null;
  }

  Future<void> updateStudent({String? schoolId, required Student updated}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _students(sId)
        .doc(sid(updated))
        .set(updated.toJson());
  }

  Future<void> removeStudent({
    String? schoolId,
    required int roll,
    required String className,
    String section = '',
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    await _students(sId).doc(sidFromParts(roll, className, section)).delete();
    await _cascadeDeleteAttendance(sId, roll, className, section: section);
  }

  Future<void> _cascadeDeleteAttendance(String schoolId, int roll, String className,
      {String section = ''}) async {
    final attKey = section.trim().isEmpty
        ? className
        : '$className ${section.trim()}';
    final prefix = '${attKey.replaceAll(' ', '_')}_';

    final snap = await _attendance(schoolId)
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
        .where(FieldPath.documentId, isLessThan: '$prefix')
        .get();

    if (snap.docs.isEmpty) return;

    final batch = db.batch();
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

  Future<Map<int, String>> loadTodayAttendance({String? schoolId, required String className}) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _attendance(sId).doc(todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final rolls = Map<String, dynamic>.from(
        (doc.data()!['rolls'] as Map?) ?? {});
    return rolls.map((k, v) {
      if (v is bool) return MapEntry(int.parse(k), v ? 'Present' : 'Absent');
      return MapEntry(int.parse(k), v as String);
    });
  }

  Future<Map<int, String>> loadAttendanceByDate({
    String? schoolId,
    required String className,
    required DateTime date,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final key = '${className.replaceAll(' ', '_')}_${date.year}-${date.month}-${date.day}';
    final doc = await _attendance(sId).doc(key).get();
    if (!doc.exists || doc.data() == null) return {};
    final rolls = Map<String, dynamic>.from(
        (doc.data()!['rolls'] as Map?) ?? {});
    return rolls.map((k, v) {
      if (v is bool) return MapEntry(int.parse(k), v ? 'Present' : 'Absent');
      return MapEntry(int.parse(k), v as String);
    });
  }

  Future<void> saveAttendance({
    String? schoolId,
    required String className,
    required Map<int, String> attendance,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final rolls = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance(sId)
        .doc(todayKey(className))
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  Future<void> saveAttendanceForDate({
    String? schoolId,
    required String className,
    required Map<int, String> attendance,
    required DateTime date,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final prefix = className.replaceAll(' ', '_');
    final key    = '${prefix}_${date.year}-${date.month}-${date.day}';
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance(sId)
        .doc(key)
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  // ── Reasons ────────────────────────────────────────────────────────────────

  Future<void> saveReasons({
    String? schoolId,
    required String className,
    required Map<int, String> reasons,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (reasons.isEmpty) return;
    final raw = reasons.map((k, v) => MapEntry(k.toString(), v));
    await _attendance(sId).doc(todayKey(className)).set(
      {'reasons': raw, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<Map<int, String>> loadTodayReasons({
    String? schoolId,
    required String className,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _attendance(sId).doc(todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['reasons'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  // ── Coordinator summary ───────────────────────────────────────────────────

  Future<List<ClassSummary>> loadTodayFullSummary({
    String? schoolId,
    required List<String> classes,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (classes.isEmpty) return [];

    // Optimize: Fetch only students belonging to the requested classes.
    // Use whereIn to avoid fetching all students in the school.
    final List<Student> allRelevantStudents = [];
    for (var i = 0; i < classes.length; i += 30) {
      final chunk = classes.sublist(
        i, i + 30 > classes.length ? classes.length : i + 30);
      final snap = await _students(sId).where('className', whereIn: chunk).get();
      allRelevantStudents.addAll(
        snap.docs.map((d) => Student.fromJson(Map<String, dynamic>.from(d.data())))
      );
    }

    final comboSet = <String>{};
    final byCombo  = <String, List<Student>>{};
    final comboParts = <String, Map<String, String>>{};

    for (final s in allRelevantStudents) {
      final combo = s.section.trim().isEmpty
          ? s.className
          : '${s.className} ${s.section.trim()}';
      comboSet.add(combo);
      byCombo.putIfAbsent(combo, () => []).add(s);
      comboParts[combo] = {'class': s.className, 'section': s.section};
    }

    final combos = comboSet.toList()..sort();

    final attendanceDocs = await Future.wait(
      combos.map((c) => _attendance(sId).doc(todayKey(c)).get()),
    );

    for (final list in byCombo.values) {
      list.sort((a, b) => a.roll.compareTo(b.roll));
    }

    return List.generate(combos.length, (i) {
      final combo    = combos[i];
      final parts    = comboParts[combo]!;
      final doc      = attendanceDocs[i];
      final students = byCombo[combo] ?? [];

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
        className:   parts['class']!,
        section:     parts['section']!,
        total:       students.length,
        present:     present,
        leave:       leave,
        absent:      absent,
        marked:      attendance.isNotEmpty,
        absentLeave: absentLeave,
      );
    });
  }

  Future<Map<int, int>> loadRecentAbsenceDays({
    String? schoolId,
    required String className,
    int days = 14,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final now    = DateTime.now();
    final prefix = className.replaceAll(' ', '_');

    final docs = await Future.wait(
      List.generate(days, (i) {
        final date = now.subtract(Duration(days: i));
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _attendance(sId).doc(key).get();
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

  Future<void> saveCalled({
    String? schoolId,
    required String className,
    required Map<int, bool> called,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    if (called.isEmpty) return;
    final raw = called.map((k, v) => MapEntry(k.toString(), v));
    await _attendance(sId).doc(todayKey(className)).set(
      {'called': raw, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<Map<int, bool>> loadTodayCalled({
    String? schoolId,
    required String className,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final doc = await _attendance(sId).doc(todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw = Map<String, dynamic>.from(
        (doc.data()!['called'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(int.parse(k), v as bool? ?? false));
  }

  Future<Map<int, Map<int, String>>> loadMonthAttendance({
    String? schoolId,
    required String className,
    required int year,
    required int month,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final prefix     = className.replaceAll(' ', '_');
    final daysInMonth = DateTime(year, month + 1, 0).day;

    final docs = await Future.wait(
      List.generate(daysInMonth, (i) {
        final day = i + 1;
        return _attendance(sId).doc('${prefix}_$year-$month-$day').get();
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

  Future<Map<int, int>> loadConsecutiveAbsenceDays({
    String? schoolId,
    required String className,
    int maxDays = 20,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final now    = DateTime.now();
    final prefix = className.replaceAll(' ', '_');

    final docs = await Future.wait(
      List.generate(maxDays, (i) {
        final date = now.subtract(Duration(days: i));
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _attendance(sId).doc(key).get();
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
      String schoolId, int roll, String className, [String section = '']) =>
      _students(schoolId).doc(sidFromParts(roll, className, section)).collection('remarks');

  Future<List<StudentRemark>> getStudentRemarks({
    String? schoolId,
    required String className,
    required int roll,
    String section = '',
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final snap = await _remarksRef(sId, roll, className, section)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs
        .map((d) => StudentRemark.fromJson(
            d.id, Map<String, dynamic>.from(d.data())))
        .toList();
  }

  Future<void> addStudentRemark({
    String? schoolId,
    required String className,
    required int roll,
    required String createdByEmail,
    required String role,
    required String remark,
    String  section   = '',
    String? teacherId,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final trimmed = remark.trim();
    if (trimmed.isEmpty || trimmed.length > 200) {
      throw ArgumentError('Remark must be 1–200 characters.');
    }
    await _remarksRef(sId, roll, className, section).add({
      'createdBy': createdByEmail,
      'role':      role,
      'remark':    trimmed,
      'timestamp': FieldValue.serverTimestamp(),
      if (teacherId != null) 'teacherId': teacherId,
    });
  }

  Future<void> deleteStudentRemark({
    String? schoolId,
    required String className,
    required int roll,
    required String remarkId,
    required String currentUserEmail,
    String section = '',
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final ref = _remarksRef(sId, roll, className, section).doc(remarkId);
    final doc = await ref.get();
    if (!doc.exists) return;
    final data = Map<String, dynamic>.from(doc.data()!);
    if (data['createdBy'] != currentUserEmail) {
      throw StateError('You can only delete your own remarks.');
    }
    await ref.delete();
  }

  Future<Map<String, dynamic>?> loadAttendanceForDate({
    String? schoolId,
    required String className,
    required DateTime date,
  }) async {
    final sId = schoolId ?? BaseFirestoreService.currentSchoolId ?? 'default_school';
    final key =
        '${className.replaceAll(' ', '_')}_${date.year}-${date.month}-${date.day}';
    final doc = await _attendance(sId).doc(key).get();
    if (!doc.exists || doc.data() == null) return null;
    return Map<String, dynamic>.from(doc.data()!);
  }
}


// ── Data classes for summary (public — used by coordinator screens) ──────────

class ClassSummary {
  final String className;
  final String section;
  final int    total, present, leave, absent;
  final bool   marked;
  final List<StudentNote> absentLeave;

  const ClassSummary({
    required this.className,
    this.section = '',
    required this.total,
    required this.present,
    required this.leave,
    required this.absent,
    required this.marked,
    required this.absentLeave,
  });

  /// The full display name (e.g. "Class 6 A" or just "Class 6")
  String get displayName =>
      section.trim().isEmpty ? className : '$className $section';
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
