import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';
import '../models/student_remark.dart';
import '../repositories/student_repository.dart';
import '../utils/app_logger.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'timetable_service.dart';

/// High-level orchestration layer for all student-related operations.
///
/// This service owns:
///   • Business-rule validation (duplicate roll check, remark length guard)
///   • Cross-collection orchestration (cascade-delete attendance on student
///     removal, revoke guardian access, approval workflows)
///   • All attendance operations (will migrate to AttendanceRepository in a
///     future PR — see docs/ARCHITECTURE.md)
///
/// Pure data access (CRUD + streaming of the `students` collection) is
/// delegated to [StudentRepository]. Inject a [FakeStudentRepository] for
/// unit tests; the default is [FirestoreStudentRepository].
class StudentService extends BaseFirestoreService {
  final StudentRepository _repo;

  // ── Singleton / factory ─────────────────────────────────────────────────────

  static StudentService? _instance;

  /// Default factory — returns the process-level singleton backed by Firestore.
  ///
  /// Pass [repo] to obtain a **fresh, non-singleton** instance. This is the
  /// intended injection point for unit tests:
  /// ```dart
  /// final service = StudentService(FakeStudentRepository());
  /// ```
  factory StudentService([StudentRepository? repo]) {
    if (repo != null) return StudentService._(repo);
    return _instance ??= StudentService._(FirestoreStudentRepository());
  }

  StudentService._(this._repo);

  // ── Firestore refs (attendance only — students live in the repo) ────────────

  String get _schoolId => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      schoolCollection(_schoolId, 'attendance');

  /// Direct students reference — used only by cascade-delete helpers.
  /// All normal CRUD goes through [_repo].
  CollectionReference<Map<String, dynamic>> get _studentsRef =>
      schoolCollection(_schoolId, 'students');

  // ── Password generator ───────────────────────────────────────────────────────

  /// Generates a readable 8-char password (no 0/O/1/I to avoid confusion).
  static String generateGuardianPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Students ────────────────────────────────────────────────────────────────

  Future<List<Student>> getStudents() => _repo.fetchAll();

  /// Fetch students for a class/section, optionally scoped to one teacher.
  /// Pass [teacherId] to return only students added by that class teacher.
  /// Omit it (or pass null) for coordinator/principal views that need all
  /// students.
  ///
  /// Note: using [teacherId] alongside className+section may require a
  /// composite Firestore index — the console error includes a creation link.
  Future<List<Student>> getStudentsByClass({
    required String className,
    String section = '',
    String? teacherId,
    String? schoolId,
  }) =>
      _repo.fetchByClass(className, section, teacherId: teacherId);

  /// Real-time stream of students for a class/section.
  /// Emits a new sorted list on every Firestore change (add / update / delete).
  Stream<List<Student>> watchStudentsByClass({
    required String className,
    String section = '',
    String? teacherId,
    String? schoolId,
  }) =>
      _repo.watchByClass(className, section, teacherId: teacherId);

  /// Real-time stream of ALL students across every class.
  Stream<List<Student>> watchStudents({String? schoolId}) => _repo.watchAll();

  /// Returns a single student by class + section + roll (used by Guardian Portal).
  Future<Student?> getStudentByRoll(String className, int roll,
          {String section = ''}) =>
      _repo.fetchByRoll(className, section, roll);

  /// Fetch multiple students by list of rolls within a class.
  Future<List<Student>> getStudentsByRolls(
          String className, List<int> rolls, {String section = ''}) =>
      _repo.fetchByRolls(className, section, rolls);

  /// Returns null on success, error string on duplicate roll.
  Future<String?> addStudent({required Student student}) async {
    if (await _repo.existsByRoll(
        student.className, student.section, student.roll)) {
      final sec =
          student.section.isNotEmpty ? ' Section ${student.section}' : '';
      return 'Roll number ${student.roll} already exists in '
          '${student.className}$sec.';
    }
    await _repo.upsert(student);
    AuditService.emit(
      action:   'create',
      entity:   'student',
      entityId: student.id.isNotEmpty
          ? student.id
          : '${student.className}_${student.section}_${student.roll}',
      after: student.toJson(),
    );
    // If a guardian email is provided, create their Firebase Auth account.
    if (student.guardianEmail != null &&
        student.guardianEmail!.trim().isNotEmpty) {
      await _upsertGuardianAccount(
        email:     student.guardianEmail!.trim().toLowerCase(),
        className: student.className,
        roll:      student.roll,
        section:   student.section,
        name:      student.name,
      );
    }
    return null;
  }

  Future<void> updateStudent({required Student updated}) async {
    final before = await _repo.fetchByRoll(
        updated.className, updated.section, updated.roll);
    await _repo.upsert(updated);
    AuditService.emit(
      action:   'update',
      entity:   'student',
      entityId: updated.id.isNotEmpty
          ? updated.id
          : '${updated.className}_${updated.section}_${updated.roll}',
      before: before?.toJson(),
      after:  updated.toJson(),
    );
  }

  /// Creates/updates a Firebase Auth account + allowed_users entry for a guardian.
  /// If the account already exists, the link is re-registered (idempotent).
  Future<void> _upsertGuardianAccount({
    required String email,
    required String className,
    required int    roll,
    String          section  = '',
    String?         name,
    String?         schoolId,
  }) async {
    final svc = TimetableService();
    // schoolId must be stamped on every allowed_users write — the security
    // rules require it on each role-scoped branch. Caller may pass a school
    // explicitly (e.g. when acting cross-school); fall back to the current
    // session's school. Without this the guardian-create from Add Student
    // got rejected as permission-denied and the form locked at "Saving…".
    final effectiveSchoolId =
        (schoolId != null && schoolId.isNotEmpty)
            ? schoolId
            : (BaseFirestoreService.currentSchoolId ?? 'school_1');
    await svc.addAllowedUser(
      email, 'TmpParent@2024!', 'guardian',
      name:         name,
      schoolId:     effectiveSchoolId,
      studentClass: className,
      studentRoll:  roll,
    );
    await svc.linkGuardianEmail(
      email:        email,
      studentClass: className,
      studentRoll:  roll,
      studentName:  name,
    );
  }

  /// Sets/updates the guardian email and creates a Firebase Auth account so
  /// the guardian can log in. Revokes the old email's student link when
  /// the address changes.
  Future<void> setGuardianEmail(
    String  className,
    int     roll,
    String  email, {
    String  section     = '',
    String? studentName,
  }) async {
    // Fetch current guardian email to detect a change.
    final existing  = await _repo.fetchByRoll(className, section, roll);
    final oldEmail  = existing?.guardianEmail;

    // Best-effort: revoke the old guardian's link and provision the new
    // guardian's allowed_users / Auth entry. A failure here (network, no
    // Firebase initialised in tests, REST error) is non-fatal — the primary
    // effect of this method is persisting the email on the student record,
    // and the admin can resend the invite later if the auth side missed.
    if (oldEmail != null &&
        oldEmail.isNotEmpty &&
        oldEmail != email.trim().toLowerCase()) {
      try {
        await TimetableService().removeGuardianLink(
          email:        oldEmail,
          studentClass: className,
          studentRoll:  roll,
        );
      } catch (e) {
        AppLogger.e('StudentService',
            'removeGuardianLink failed for $oldEmail (non-fatal): $e', e);
      }
    }

    try {
      await _upsertGuardianAccount(
        email:     email.trim().toLowerCase(),
        className: className,
        roll:      roll,
        section:   section,
        name:      studentName,
      );
    } catch (e) {
      AppLogger.e('StudentService',
          '_upsertGuardianAccount failed (non-fatal): $e', e);
    }

    // Persist the email on the student record (primary effect).
    await _repo.setGuardianEmail(className, section, roll,
        email.trim().toLowerCase());
  }

  /// Permanently deletes a student AND revokes their guardian's login access.
  /// Called only after principal approval — teachers must use
  /// [submitDeletionRequest].
  Future<void> removeStudent(int roll, String className,
      {String section = ''}) async {
    // 1. Read the student record (needed for guardian email).
    final student = await _repo.fetchByRoll(className, section, roll);
    if (student == null) return; // already deleted — idempotent

    // 2. Delete remarks subcollection before the student document.
    await _cascadeDeleteRemarks(student.id);

    // 3. Delete student document.
    await _repo.delete(student.id);

    // 4. Cascade-delete attendance, notifications, exam results, fee records.
    await _cascadeDeleteAttendance(roll, className, section: section);
    await _cascadeDeleteStudentNotifications(className, roll);
    await _cascadeDeleteExamResults(className, roll);
    await _cascadeDeleteFeePayments(className, roll);

    AuditService.emit(
      action:   'delete',
      entity:   'student',
      entityId: student.id.isNotEmpty
          ? student.id
          : '${className}_${section}_$roll',
      before: student.toJson(),
      reason: 'principal-approved deletion',
    );

    // 5. Revoke guardian login.
    final guardianEmail = student.guardianEmail;
    if (guardianEmail != null && guardianEmail.trim().isNotEmpty) {
      final svc = TimetableService();
      await svc.removeGuardianLink(
        email: guardianEmail,
        studentClass: className,
        studentRoll: roll,
      );
      final remaining = await svc.getGuardianLinks(guardianEmail);
      if (remaining == null || remaining.isEmpty) {
        await svc.removeAllowedUser(guardianEmail);
      }
    }
  }

  // ── Deletion requests (teacher → principal approval flow) ───────────────────

  /// Teacher submits a request to delete one or more students.
  Future<void> submitDeletionRequest({
    required String teacherId,
    required String teacherName,
    required String teacherEmail,
    required List<Map<String, dynamic>> students,
    String reason = '',
  }) =>
      _repo.submitDeletionRequest(
        teacherId: teacherId,
        teacherName: teacherName,
        teacherEmail: teacherEmail,
        students: students,
        reason: reason,
      );

  /// Real-time stream of pending deletion request count — used for the
  /// principal dashboard badge.
  Stream<int> streamPendingDeletionCount() =>
      _repo.streamPendingDeletionCount();

  /// Returns all pending deletion requests, newest first.
  Future<List<Map<String, dynamic>>> getPendingDeletionRequests() =>
      _repo.getPendingDeletionRequests();

  /// Principal approves a deletion request: deletes each student and their
  /// guardian access, then marks the request as approved.
  Future<void> approveDeletionRequest(String requestId) async {
    final data = await _repo.getDeletionRequest(requestId);
    if (data == null) return;
    final list =
        (data['students'] as List?)?.whereType<Map<String, dynamic>>() ?? [];
    for (final s in list) {
      final roll      = (s['roll']      as num?)?.toInt() ?? 0;
      final className = (s['className'] as String?) ?? '';
      final section   = (s['section']   as String?) ?? '';
      if (roll > 0 && className.isNotEmpty) {
        await removeStudent(roll, className, section: section);
      }
    }
    await _repo.updateDeletionRequestStatus(requestId, 'approved');
  }

  /// Principal rejects a deletion request.
  Future<void> rejectDeletionRequest(String requestId,
          {String rejectionNote = ''}) =>
      _repo.updateDeletionRequestStatus(requestId, 'rejected',
          rejectionNote: rejectionNote);

  // ── Attendance ──────────────────────────────────────────────────────────────
  //
  // NOTE: attendance operations still talk to Firestore directly.
  //       They will migrate to AttendanceRepository in a follow-up PR.

  String _todayKey(String className) {
    final now = DateTime.now();
    return '${className.replaceAll(' ', '_')}_${now.year}-${now.month}-${now.day}';
  }

  /// Returns 'Present' | 'Absent' | 'Leave' per roll number.
  /// Backward-compatible: old bool values are migrated automatically.
  Future<Map<int, String>> loadTodayAttendance(
      {required String className}) async {
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
      {required String className,
      required Map<int, String> attendance}) async {
    final docKey = _todayKey(className);
    final prev   = await _attendance.doc(docKey).get();
    final isUpdate = prev.exists;
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(docKey)
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    AuditService.emit(
      action:   isUpdate ? 'update' : 'create',
      entity:   'attendance',
      entityId: docKey,
      before:   isUpdate && prev.data() != null
          ? Map<String, dynamic>.from(prev.data()!)
          : null,
      after:    {'rolls': rolls},
    );
  }

  /// Save attendance for a specific date (used by offline sync).
  Future<void> saveAttendanceForDate(
      {required String className,
      required Map<int, String> attendance,
      required DateTime date}) async {
    final prefix = className.replaceAll(' ', '_');
    final key    = '${prefix}_${date.year}-${date.month}-${date.day}';
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(key)
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  /// Marks a student as 'Leave' for every day in the given range.
  /// Sundays are skipped. Uses merge so other students are untouched.
  Future<void> markLeaveForDateRange({
    required String className,
    required int roll,
    required DateTime startDate,
    required int numberOfDays,
  }) async {
    for (int i = 0; i < numberOfDays; i++) {
      final date = startDate.add(Duration(days: i));
      if (date.weekday == DateTime.sunday) continue;
      await saveAttendanceForDate(
        className: className,
        attendance: {roll: 'Leave'},
        date: date,
      );
    }
  }

  // ── Reasons (call notes after follow-up) ───────────────────────────────────

  Future<void> saveReasons(
      {required String className,
      required Map<int, String> reasons}) async {
    if (reasons.isEmpty) return;
    final raw = reasons.map((k, v) => MapEntry(k.toString(), v));
    await _attendance.doc(_todayKey(className)).set(
          {'reasons': raw, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
  }

  Future<Map<int, String>> loadTodayReasons(
      {required String className}) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw =
        Map<String, dynamic>.from((doc.data()!['reasons'] as Map?) ?? {});
    return raw.map((k, v) => MapEntry(int.parse(k), v as String));
  }

  // ── Coordinator summary across all classes ─────────────────────────────────

  /// Builds today's attendance summary for every class in [classes].
  Future<List<ClassSummary>> loadTodayFullSummary(
      {required List<String> classes, String? schoolId}) async {
    if (classes.isEmpty) return [];

    // 1. Fetch all students via repository.
    final allStudents = await _repo.fetchAll();

    // Group students by className, sorted by roll.
    final byClass = <String, List<Student>>{};
    for (final s in allStudents) {
      byClass.putIfAbsent(s.className, () => []).add(s);
    }
    for (final list in byClass.values) {
      list.sort((a, b) => a.roll.compareTo(b.roll));
    }

    // 2. Build attendance doc key(s) per class.
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

    // 3. Fetch every attendance doc in parallel.
    final allKeys = classToKeys.values.expand((k) => k).toList();
    final allDocs =
        await Future.wait(allKeys.map((k) => _attendance.doc(k).get()));
    final docsByKey =
        <String, DocumentSnapshot<Map<String, dynamic>>>{
      for (var i = 0; i < allKeys.length; i++) allKeys[i]: allDocs[i],
    };

    // 4. Merge section docs into one ClassSummary per class.
    return List.generate(classes.length, (i) {
      final cls      = classes[i];
      final students = byClass[cls] ?? [];
      final keys     = classToKeys[cls] ?? [];

      final attendance = <int, String>{};
      final reasons    = <int, String>{};
      var   anyMarked  = false;

      for (final key in keys) {
        final doc = docsByKey[key];
        if (doc == null || !doc.exists || doc.data() == null) continue;
        anyMarked  = true;
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final rollsRaw   =
            Map<String, dynamic>.from((data['rolls']   as Map?) ?? {});
        final reasonsRaw =
            Map<String, dynamic>.from((data['reasons'] as Map?) ?? {});
        rollsRaw.forEach((k, v) {
          attendance[int.parse(k)] =
              v is bool ? (v ? 'Present' : 'Absent') : (v as String);
        });
        reasonsRaw
            .forEach((k, v) => reasons[int.parse(k)] = v as String);
      }

      final present =
          students.where((s) => attendance[s.roll] == 'Present').length;
      final leave =
          students.where((s) => attendance[s.roll] == 'Leave').length;
      final absent =
          students.where((s) => attendance[s.roll] == 'Absent').length;

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
  Future<Map<int, int>> loadRecentAbsenceDays(
      {required String className, int days = 14}) async {
    final now    = DateTime.now();
    final prefix = className.replaceAll(' ', '_');

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

  Future<void> saveCalled(
      {required String className,
      required Map<int, bool> called}) async {
    if (called.isEmpty) return;
    final raw = called.map((k, v) => MapEntry(k.toString(), v));
    await _attendance.doc(_todayKey(className)).set(
          {'called': raw, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
  }

  Future<Map<int, bool>> loadTodayCalled(
      {required String className}) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final raw =
        Map<String, dynamic>.from((doc.data()!['called'] as Map?) ?? {});
    return raw
        .map((k, v) => MapEntry(int.parse(k), v as bool? ?? false));
  }

  /// Loads every attendance document for a class in a given month.
  /// Returns: { day → { roll → status } }
  Future<Map<int, Map<int, String>>> loadMonthAttendance(
      {required String className,
      required int year,
      required int month,
      String? schoolId}) async {
    final prefix      = className.replaceAll(' ', '_');
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
        if (v is bool) {
          return MapEntry(int.parse(k), v ? 'Present' : 'Absent');
        }
        return MapEntry(int.parse(k), v as String);
      });
    }
    return result;
  }

  /// Returns roll → number of consecutive school days absent/on leave,
  /// counting backwards from today. Days with no record are skipped.
  Future<Map<int, int>> loadConsecutiveAbsenceDays(String className,
      {int maxDays = 20}) async {
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
        final isAbsent =
            status == 'Absent' || status == 'Leave' || status == false;
        if (isAbsent) {
          streaks[roll] = (streaks[roll] ?? 0) + 1;
        } else {
          broken.add(roll);
        }
      });
    }
    return streaks;
  }

  // ── Remarks ─────────────────────────────────────────────────────────────────

  /// Returns all remarks for a student, newest first.
  Future<List<StudentRemark>> getStudentRemarks(
          String className, int roll, {String section = ''}) =>
      _repo.fetchRemarks(className, roll, section: section);

  /// Adds a remark. Throws [ArgumentError] if remark is empty or > 200 chars.
  Future<void> addStudentRemark(
    String className,
    int roll,
    String createdByEmail,
    String role,
    String remark, {
    String section = '',
    String? teacherId,
    String type = 'negative',
    bool whatsappSent = false,
  }) async {
    final trimmed = remark.trim();
    if (trimmed.isEmpty || trimmed.length > 200) {
      throw ArgumentError('Remark must be 1–200 characters.');
    }
    await _repo.addRemark(
      className:    className,
      roll:         roll,
      createdBy:    createdByEmail,
      role:         role,
      remark:       trimmed,
      section:      section,
      teacherId:    teacherId,
      type:         type,
      whatsappSent: whatsappSent,
    );
  }

  /// Deletes a remark. Throws [StateError] if caller is not the author.
  Future<void> deleteStudentRemark({
    required String className,
    required int roll,
    required String remarkId,
    required String currentUserEmail,
    String section = '',
  }) =>
      _repo.deleteRemark(
        className:        className,
        roll:             roll,
        remarkId:         remarkId,
        currentUserEmail: currentUserEmail,
        section:          section,
      );

  /// Load attendance doc for a specific date (for history).
  Future<Map<String, dynamic>?> loadAttendanceForDate(
      {required String className, required DateTime date}) async {
    final key =
        '${className.replaceAll(' ', '_')}_${date.year}-${date.month}-${date.day}';
    final doc = await _attendance.doc(key).get();
    if (!doc.exists || doc.data() == null) return null;
    return Map<String, dynamic>.from(doc.data()!);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Deletes every remark in the student's `remarks` subcollection.
  Future<void> _cascadeDeleteRemarks(String studentDocId) async {
    try {
      final snap =
          await _studentsRef.doc(studentDocId).collection('remarks').get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Deletes all notifications addressed to this student's guardian.
  Future<void> _cascadeDeleteStudentNotifications(
      String className, int roll) async {
    try {
      final audience = 'guardian:$className:$roll';
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('audience', isEqualTo: audience)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Deletes the student's result document in every exam for their class.
  Future<void> _cascadeDeleteExamResults(
      String className, int roll) async {
    try {
      final examsSnap = await FirebaseFirestore.instance
          .collection('exams')
          .where('className', isEqualTo: className)
          .get();
      if (examsSnap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final examDoc in examsSnap.docs) {
        batch.delete(FirebaseFirestore.instance
            .collection('exam_results')
            .doc(examDoc.id)
            .collection('students')
            .doc('$roll'));
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Deletes fee payment records for the student.
  Future<void> _cascadeDeleteFeePayments(
      String className, int roll) async {
    try {
      final studentNode = FirebaseFirestore.instance
          .collection('fee_payments')
          .doc(className)
          .collection('students')
          .doc('$roll');
      final paymentsSnap =
          await studentNode.collection('payments').get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in paymentsSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(studentNode);
      await batch.commit();
    } catch (_) {}
  }

  /// Removes [roll] from every attendance document in [className]/[section].
  /// Uses a Firestore document-ID prefix query to limit the scan scope.
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

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final rolls =
          Map<String, dynamic>.from((doc.data()['rolls'] as Map?) ?? {});
      if (rolls.containsKey(roll.toString())) {
        batch.update(doc.reference,
            {'rolls.$roll': FieldValue.delete()});
      }
    }
    await batch.commit();
  }
}

// ── Data classes for summary (public — used by coordinator screens) ───────────

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

  String get displayName => className;
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
