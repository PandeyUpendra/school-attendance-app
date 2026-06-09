import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/deleted_student.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import '../models/guardian_provided_details.dart';
import '../models/school_provided_details.dart';
import '../repositories/student_repository.dart';
import '../utils/app_logger.dart';
import '../utils/phone_utils.dart';
import '../utils/school_clock.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'timetable_service.dart';

String stripHtml(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

String normalizePhone(String phone) => PhoneUtils.normalize(phone);

class AttendanceLockedException implements Exception {
  final String message;
  AttendanceLockedException([this.message = 'Attendance is locked for this date.']);
  @override
  String toString() => message;
}


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

  // ── Attendance day-doc read cache (#72/#177) ────────────────────────────────
  // Dashboards (coordinator/principal/owner/analytics) recompute recent- and
  // consecutive-absence by fetching ~14–20 day docs PER class on every open,
  // and the same day docs are re-fetched across `loadRecentAbsenceDays`,
  // `loadConsecutiveAbsenceDays` and `loadMonthAttendance`. PAST day docs are
  // effectively immutable (historical edits are lock-gated, #34), so caching
  // them for a short TTL collapses those repeated reads. TODAY's doc is never
  // cached (it mutates as marks come in), and any write invalidates its key.
  static const Duration _dayDocTtl = Duration(seconds: 120);
  static final Map<String, _DayDocEntry> _dayDocCache = {};

  /// Fetches an attendance day doc's data, served from the short-TTL cache when
  /// [cacheable] (i.e. a past day). Returns null when the doc doesn't exist.
  Future<Map<String, dynamic>?> _dayDocData(String key,
      {required bool cacheable}) async {
    // Namespace by school — an owner can switch schools in-session and class
    // names + date keys would otherwise collide across tenants.
    final cacheKey = '$_schoolId/$key';
    if (cacheable) {
      final hit = _dayDocCache[cacheKey];
      if (hit != null &&
          DateTime.now().difference(hit.at) < _dayDocTtl) {
        return hit.data;
      }
    }
    final doc  = await _attendance.doc(key).get();
    final data = doc.exists ? doc.data() : null;
    if (cacheable) _dayDocCache[cacheKey] = _DayDocEntry(data, DateTime.now());
    return data;
  }

  /// Drops a day-doc from the cache after a write so the next read is fresh.
  void _invalidateDayDoc(String key) => _dayDocCache.remove('$_schoolId/$key');

  /// Direct students reference — used only by cascade-delete helpers.
  /// All normal CRUD goes through [_repo].
  CollectionReference<Map<String, dynamic>> get _studentsRef =>
      schoolCollection(_schoolId, 'students');

  // (generateGuardianPassword removed — it was dead and misleading: guardians
  // now get a strong random temp credential via generateSecurePassword inside
  // TimetableService.addAllowedUser, set their own password via the invite
  // link, and the password is never stored. Review #150.)

  // ── Students ────────────────────────────────────────────────────────────────

  /// Strips out students that have been marked for deletion so they vanish
  /// from every role-based roster and detail screen (teacher, coordinator,
  /// principal, analytics, fees, …). The principal's deletion-requests screen
  /// reads the separate `student_deletion_requests` collection, so approvals
  /// keep working; and internal lookups (`removeStudent`, guardian portal) go
  /// straight to the repository, bypassing this filter.
  static List<Student> _visibleOnly(List<Student> students) =>
      students.where((s) => !s.deletionPending && !s.promoted).toList();

  Future<List<Student>> getStudents() async =>
      _visibleOnly(await _repo.fetchAll());

  /// Every (visible) student whose guardian email matches [email]. Lets a
  /// guardian with more than one child see all of them after a single login.
  /// Uses a server-side equality query (guardian emails are stored lower-cased)
  /// so it stays cheap and works under guardian-scoped read rules. Sorted by
  /// name for a stable child-switcher order.
  Future<List<Student>> getStudentsByGuardianEmail(String email) async {
    final norm = email.trim().toLowerCase();
    if (norm.isEmpty) return [];
    final snap =
        await _studentsRef.where('guardianEmail', isEqualTo: norm).get();
    final list = snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = d.id;
      return Student.fromJson(data);
    }).toList();
    final visible = _visibleOnly(list)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return visible;
  }

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
  }) async =>
      _visibleOnly(
          await _repo.fetchByClass(className, section, teacherId: teacherId));

  /// Fetches raw student records for a class/section (including promoted and deletion pending).
  Future<List<Student>> getStudentsByClassRaw({
    required String className,
    String section = '',
  }) async =>
      _repo.fetchByClass(className, section);

  /// Real-time stream of students for a class/section.
  /// Emits a new sorted list on every Firestore change (add / update / delete).
  Stream<List<Student>> watchStudentsByClass({
    required String className,
    String section = '',
    String? teacherId,
    String? schoolId,
  }) =>
      _repo
          .watchByClass(className, section, teacherId: teacherId)
          .map(_visibleOnly);

  /// Real-time stream of ALL students across every class.
  Stream<List<Student>> watchStudents({String? schoolId}) =>
      _repo.watchAll().map(_visibleOnly);

  /// Returns a single student by class + section + roll (used by Guardian Portal).
  /// Returns null for students marked for deletion so no role can open their
  /// details. Internal flows (`removeStudent`, `setGuardianEmail`) read the
  /// repository directly and are unaffected.
  Future<Student?> getStudentByRoll(String className, int roll,
      {String section = ''}) async {
    final student = await _repo.fetchByRoll(className, section, roll);
    if (student == null || student.deletionPending) return null;
    return student;
  }

  /// Fetch multiple students by list of rolls within a class.
  Future<List<Student>> getStudentsByRolls(
          String className, List<int> rolls, {String section = ''}) async =>
      _visibleOnly(await _repo.fetchByRolls(className, section, rolls));

  // ── Deleted students (read-only history) ────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _deletedStudentsRef =>
      schoolCollection(_schoolId, 'deleted_students');

  /// Live stream of removed-student tombstones across the school, newest
  /// first. Ordering is by `deletedAt` only (no composite index needed);
  /// per-class scoping (class teacher → own class) and class-wise grouping
  /// (coordinator / principal) are done in the UI.
  Stream<List<DeletedStudent>> watchDeletedStudents() {
    // Bound the read: order newest-first server-side and cap the result, so a
    // school that has deleted thousands of students over the years doesn't pull
    // and sort the entire collection on the client every snapshot (#119). The
    // "Deleted Students" UI only needs recent tombstones.
    return _deletedStudentsRef
        .orderBy('deletedAt', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DeletedStudent.fromJson(d.id, d.data()))
            .toList());
  }

  /// Generates a stable cross-year admission id (#70). Format: STU-<ms>-<rand>.
  static String _newAdmissionId() {
    final ms   = DateTime.now().microsecondsSinceEpoch;
    final rand = (ms % 100000).toString().padLeft(5, '0');
    return 'STU-$ms-$rand';
  }

  /// Returns null on success, error string on duplicate roll.
  Future<String?> addStudent({required Student student}) async {
    // 1. Sanitize fields
    var sanitized = student.copyWith(
      name: stripHtml(student.name).trim(),
      fatherName: stripHtml(student.fatherName).trim(),
      motherName: student.motherName != null ? stripHtml(student.motherName!).trim() : null,
      phone: student.phone.isNotEmpty ? normalizePhone(student.phone) : '',
      parentPhone: student.parentPhone != null && student.parentPhone!.isNotEmpty
          ? normalizePhone(student.parentPhone!)
          : null,
    );

    // 2. Stamp stable admissionId
    if (sanitized.admissionId.trim().isEmpty) {
      sanitized = sanitized.copyWith(admissionId: _newAdmissionId());
    }

    // 3. Atomically add student checking duplicates
    final error = await _repo.addStudentUnique(sanitized);
    if (error != null) {
      return error;
    }

    final docId = Student.buildDocId(sanitized.roll, sanitized.className, sanitized.section);
    AuditService.emit(
      action:   'create',
      entity:   'student',
      entityId: docId,
      after: sanitized.copyWith(id: docId).toJson(),
    );

    // If a guardian email is provided, create their Firebase Auth account.
    if (sanitized.guardianEmail != null &&
        sanitized.guardianEmail!.trim().isNotEmpty) {
      await _upsertGuardianAccount(
        email:     sanitized.guardianEmail!.trim().toLowerCase(),
        className: sanitized.className,
        roll:      sanitized.roll,
        section:   sanitized.section,
        name:      sanitized.name,
        admissionId: sanitized.admissionId,
      );
    }
    return null;
  }

  Future<String?> updateStudent({required Student updated}) async {
    // 1. Sanitize fields
    var sanitized = updated.copyWith(
      name: stripHtml(updated.name).trim(),
      fatherName: stripHtml(updated.fatherName).trim(),
      motherName: updated.motherName != null ? stripHtml(updated.motherName!).trim() : null,
      phone: updated.phone.isNotEmpty ? normalizePhone(updated.phone) : '',
      parentPhone: updated.parentPhone != null && updated.parentPhone!.isNotEmpty
          ? normalizePhone(updated.parentPhone!)
          : null,
    );

    // 2. Fetch before state to check key changes
    final oldDocId = sanitized.id;
    if (oldDocId.isEmpty) {
      await _repo.upsert(sanitized);
      return null;
    }

    final before = await _repo.fetchById(oldDocId);
    if (before == null) {
      await _repo.upsert(sanitized);
      return null;
    }

    // 3. Guard: admissionId must remain unique across the school (#40).
    //    Only check when the admissionId actually changed (saves a DB round-trip
    //    for the common case where it's unchanged).
    final adm = sanitized.admissionId.trim();
    if (adm.isNotEmpty && adm != before.admissionId.trim()) {
      if (await _repo.existsByAdmissionId(adm, excludeDocId: oldDocId)) {
        return 'Admission ID "$adm" is already assigned to another student.';
      }
    }

    final changedId = sanitized.roll != before.roll ||
        sanitized.className != before.className ||
        sanitized.section != before.section;

    if (changedId) {
      // Check duplicate roll on target
      final newDocId = Student.buildDocId(sanitized.roll, sanitized.className, sanitized.section);
      if (await _repo.existsByRoll(sanitized.className, sanitized.section, sanitized.roll)) {
        final sec = sanitized.section.isNotEmpty ? ' Section ${sanitized.section}' : '';
        return 'Roll number ${sanitized.roll} already exists in ${sanitized.className}$sec.';
      }

      // Upsert under new ID and delete old document
      await _repo.upsert(sanitized.copyWith(id: newDocId));
      await _repo.delete(oldDocId);
      sanitized = sanitized.copyWith(id: newDocId);
    } else {
      await _repo.upsert(sanitized);
    }

    AuditService.emit(
      action:   'update',
      entity:   'student',
      entityId: sanitized.id,
      before: before.toJson(),
      after:  sanitized.toJson(),
    );
    return null;
  }

  /// Marks the source-class record as promoted (#70) so it leaves active rosters
  /// while its attendance/fee history stays intact under the old class.
  Future<void> markPromoted(Student student) async {
    await _repo.upsert(student.copyWith(promoted: true));
    // Stale-notification window (#39): promotion archives the source record in
    // place, leaving its guardian-targeted notices ('guardian:{oldClass}:{roll}')
    // behind. If a future admission reuses that vacated class+roll, it would
    // inherit the previous child's notices. Purge them now — the guardian has
    // moved to the new class record and these old notices are no longer theirs.
    // Best-effort: a failure here never blocks the promotion.
    try {
      await _cascadeDeleteStudentNotifications(student.className, student.roll);
      await _cascadeDeleteStudentLeaveNotifications(
          student.className, student.roll, student.name);
    } catch (e) {
      AppLogger.e('StudentService', 'promote notification purge failed: $e', e);
    }
    AuditService.emit(
      action:   'update',
      entity:   'student',
      entityId: student.id.isNotEmpty
          ? student.id
          : '${student.className}_${student.section}_${student.roll}',
      reason:   'promoted to next class',
    );
  }

  /// Atomically promotes a batch of students and parallelizes post-promotion tasks.
  Future<void> promoteStudents(
    List<Student> newStudents,
    List<Student> oldStudents,
  ) async {
    if (newStudents.isEmpty) return;
    assert(newStudents.length == oldStudents.length);

    // 1. Database write (atomic batch)
    await _repo.promoteStudentsAtomic(newStudents, oldStudents);

    // 2. Parallel post-promotion tasks
    final tasks = <Future<void>>[];
    for (var i = 0; i < newStudents.length; i++) {
      final ns = newStudents[i];
      final os = oldStudents[i];

      // Audit log for creation of target student record
      final nsDocId = Student.buildDocId(ns.roll, ns.className, ns.section);
      AuditService.emit(
        action: 'create',
        entity: 'student',
        entityId: nsDocId,
        after: ns.copyWith(id: nsDocId).toJson(),
      );

      // Audit log for archiving/promotion of source student record
      final osDocId = os.id.isNotEmpty
          ? os.id
          : Student.buildDocId(os.roll, os.className, os.section);
      AuditService.emit(
        action: 'update',
        entity: 'student',
        entityId: osDocId,
        before: os.toJson(),
        after: os.copyWith(promoted: true).toJson(),
        reason: 'promoted to next class',
      );

      // Guardian account upsert (async best-effort)
      if (ns.guardianEmail != null && ns.guardianEmail!.trim().isNotEmpty) {
        tasks.add(() async {
          try {
            await _upsertGuardianAccount(
              email: ns.guardianEmail!.trim().toLowerCase(),
              className: ns.className,
              roll: ns.roll,
              section: ns.section,
              name: ns.name,
              admissionId: ns.admissionId,
            );
          } catch (e) {
            AppLogger.e('StudentService',
                'promote guardian account upsert failed: $e', e);
          }
        }());
      }

      // Purge stale notifications (async best-effort)
      tasks.add(() async {
        try {
          await _cascadeDeleteStudentNotifications(os.className, os.roll);
          await _cascadeDeleteStudentLeaveNotifications(
              os.className, os.roll, os.name);
        } catch (e) {
          AppLogger.e('StudentService', 'promote notification purge failed: $e', e);
        }
      }());
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
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
    String?         admissionId,
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
    // Empty password ⇒ addAllowedUser mints a strong random temp credential.
    // Previously every guardian shared the hardcoded 'TmpParent@2024!', so any
    // guardian who never reset could be impersonated by anyone (review #6).
    await svc.addAllowedUser(
      email, '', 'guardian',
      name:         name,
      schoolId:     effectiveSchoolId,
      studentClass: className,
      studentRoll:  roll,
      studentAdmissionId: admissionId,
    );
    await svc.linkGuardianEmail(
      email:        email,
      studentClass: className,
      studentRoll:  roll,
      studentName:  name,
      studentAdmissionId: admissionId,
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
        admissionId: existing?.admissionId,
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

    // 2. Record a tombstone so the deleted student stays visible in the
    //    read-only "Deleted Students" history (best-effort — must not abort
    //    the deletion if the write fails). Written client-side regardless of
    //    which cascade path runs.
    await _recordDeletedStudent(student);

    // 3. Prefer the server-side cascade (#35): the deleteStudent Cloud Function
    //    runs the whole cleanup to completion server-side, so an interruption
    //    can't leave orphaned fee/exam records in class totals. Fall back to the
    //    client cascade if the function is unavailable or errors, so deletion
    //    never regresses.
    bool serverDone = false;
    try {
      serverDone = await _serverDeleteStudent(className, section, roll);
    } catch (e) {
      AppLogger.e('StudentService',
          'server deleteStudent failed, falling back to client cascade: $e', e);
    }

    if (!serverDone) {
      if (_repo is! FirestoreStudentRepository) {
        await _repo.delete(student.id);
      } else {
        final studentDocId = student.id;
        final audience = 'guardian:$className:$roll';
        final attKey = section.trim().isEmpty ? className : '$className ${section.trim()}';
        final prefix = '${attKey.replaceAll(' ', '_')}_';
        final wantTitle = 'Leave request: ${student.name}';
        final wantSection = section.trim();
        final studentNode = schoolCollection(_schoolId, 'fee_payments')
            .doc(className.replaceAll(' ', '_'))
            .collection('students')
            .doc('$roll');

        // Fetch everything in parallel
        final results = await Future.wait([
          _studentsRef.doc(studentDocId).collection('remarks').get(),
          _attendance
              .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
              .where(FieldPath.documentId, isLessThan: '$prefix■')
              .get(),
          schoolCollection(_schoolId, 'notifications')
              .where('audience', isEqualTo: audience)
              .get(),
          schoolCollection(_schoolId, 'notifications')
              .where('audience', isEqualTo: 'class_teacher:$className')
              .get(),
          schoolCollection(_schoolId, 'leave_applications')
              .where('applicantType', isEqualTo: 'guardian')
              .where('studentClass', isEqualTo: className)
              .where('studentRoll', isEqualTo: roll)
              .get(),
          schoolCollection(_schoolId, 'exams')
              .where('className', isEqualTo: className)
              .get(),
          studentNode.collection('payments').get(),
        ]);

        final remarksSnap = results[0];
        final attendanceSnap = results[1];
        final notificationsSnap = results[2];
        final teacherNotificationsSnap = results[3];
        final leaveAppsSnap = results[4];
        final examsSnap = results[5];
        final paymentsSnap = results[6];

        // Filters client-side
        final leaveNotificationsMatches = teacherNotificationsSnap.docs.where((d) {
          final data = d.data();
          if (data['type'] != 'student_leave_submitted') return false;
          final r = (data['studentRoll'] as num?)?.toInt();
          return r != null ? r == roll : data['title'] == wantTitle;
        }).toList();

        final leaveAppsMatches = wantSection.isEmpty
            ? leaveAppsSnap.docs
            : leaveAppsSnap.docs.where((d) =>
                ((d.data()['studentSection'] as String?) ?? '').trim() == wantSection)
                .toList();

        final batchOps = <Future<void> Function(WriteBatch)>[];

        // 1. Delete student doc
        batchOps.add((batch) async => batch.delete(_studentsRef.doc(studentDocId)));

        // 2. Remarks
        for (final doc in remarksSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 3. Attendance updates
        for (final doc in attendanceSnap.docs) {
          final rolls = Map<String, dynamic>.from((doc.data()['rolls'] as Map?) ?? {});
          if (rolls.containsKey(roll.toString())) {
            batchOps.add((batch) async => batch.update(doc.reference, {'rolls.$roll': FieldValue.delete()}));
          }
        }

        // 4. Notifications
        for (final doc in notificationsSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 5. Leave notifications
        for (final doc in leaveNotificationsMatches) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 6. Leave applications
        for (final doc in leaveAppsMatches) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 7. Exam results
        for (final examDoc in examsSnap.docs) {
          final ref = schoolCollection(_schoolId, 'exam_results')
              .doc(examDoc.id)
              .collection('students')
              .doc('$roll');
          batchOps.add((batch) async => batch.delete(ref));
        }

        // 8. Fee payments
        for (final doc in paymentsSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }
        batchOps.add((batch) async => batch.delete(studentNode));

        // Commit in chunks of 450
        for (var i = 0; i < batchOps.length; i += 450) {
          final batch = FirebaseFirestore.instance.batch();
          final chunk = batchOps.sublist(i, i + 450 > batchOps.length ? batchOps.length : i + 450);
          for (final op in chunk) {
            await op(batch);
          }
          await batch.commit();
        }
      }
    }

    AuditService.emit(
      action:   'delete',
      entity:   'student',
      entityId: student.id.isNotEmpty
          ? student.id
          : '${className}_${section}_$roll',
      before: student.toJson(),
      reason: 'principal-approved deletion',
    );

    // 6. Revoke guardian login (best-effort — never block the deletion on it).
    final guardianEmail = student.guardianEmail;
    if (guardianEmail != null && guardianEmail.trim().isNotEmpty) {
      try {
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
      } catch (e) {
        AppLogger.e('StudentService',
            'guardian login revoke failed (non-fatal): $e', e);
      }
    }
  }

  /// Calls the server-side cascade-delete Cloud Function (#35). Returns true on
  /// success; throws on transport/permission/not-deployed errors so the caller
  /// can fall back to the client cascade.
  Future<bool> _serverDeleteStudent(
      String className, String section, int roll) async {
    final callable = FirebaseFunctions.instance.httpsCallable('deleteStudent');
    final res = await callable.call(<String, dynamic>{
      'schoolId':  _schoolId,
      'className': className,
      'section':   section,
      'roll':      roll,
    });
    final data = res.data;
    return data is Map && data['ok'] == true;
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

  /// Marks/unmarks a batch of students (as `[{roll, className, section}]`) as
  /// awaiting deletion approval. Called with `true` right after a teacher files
  /// a deletion request so the list shows them as deactivated, and with `false`
  /// when the request is rejected so they reactivate. Failures per-student are
  /// swallowed so one bad record can't abort the whole batch.
  Future<void> markStudentsDeletionPending(
    List<Map<String, dynamic>> students,
    bool value,
  ) async {
    await Future.wait(students.map((s) async {
      final roll      = (s['roll']      as num?)?.toInt() ?? 0;
      final className = (s['className'] as String?) ?? '';
      final section   = (s['section']   as String?) ?? '';
      if (roll <= 0 || className.isEmpty) return;
      try {
        await _repo.setDeletionPending(roll, className, section, value);
      } catch (_) {/* non-fatal — request is already filed */}
    }));
  }

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

  /// Principal rejects a deletion request — reactivates the affected students
  /// (clears their `deletionPending` flag) before marking the request rejected.
  Future<void> rejectDeletionRequest(String requestId,
      {String rejectionNote = ''}) async {
    final data = await _repo.getDeletionRequest(requestId);
    if (data != null) {
      final list = (data['students'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [];
      await markStudentsDeletionPending(list, false);
    }
    await _repo.updateDeletionRequestStatus(requestId, 'rejected',
        rejectionNote: rejectionNote);
  }

  // ── Attendance ──────────────────────────────────────────────────────────────
  //
  // NOTE: attendance operations still talk to Firestore directly.
  //       They will migrate to AttendanceRepository in a follow-up PR.

  String _todayKey(String className) {
    // Anchor "today" to the school timezone, not the device's (#43).
    final now = SchoolClock.now();
    return '${className.replaceAll(' ', '_')}_${now.year}-${now.month}-${now.day}';
  }

  /// Returns 'Present' | 'Absent' | 'Leave' per roll number.
  /// Backward-compatible: old bool values are migrated automatically.
  /// Parses a `rolls` map (roll-string → status) into roll-int → status,
  /// SKIPPING any malformed (non-numeric) key. A single bad key previously
  /// crashed the whole class load via int.parse (#50).
  static Map<int, String> _parseRolls(Map<String, dynamic> rolls) {
    final out = <int, String>{};
    rolls.forEach((k, v) {
      final roll = int.tryParse(k);
      if (roll == null) return;
      out[roll] = v is bool ? (v ? 'Present' : 'Absent') : v.toString();
    });
    return out;
  }

  Future<Map<int, String>> loadTodayAttendance(
      {required String className}) async {
    final doc = await _attendance.doc(_todayKey(className)).get();
    if (!doc.exists || doc.data() == null) return {};
    final rolls = Map<String, dynamic>.from(
        (doc.data()!['rolls'] as Map?) ?? {});
    return _parseRolls(rolls);
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
    _invalidateDayDoc(docKey);
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
    final session = await AuthService().getSession();
    final role = session?['role'] as String?;
    const mgmt = ['coordinator', 'principal', 'admin', 'owner', 'ownerPrincipal'];
    if (!mgmt.contains(role)) {
      final days = SchoolClock.today()
          .difference(DateTime(date.year, date.month, date.day))
          .inDays;
      if (days > 7) {
        throw AttendanceLockedException(
            'Attendance for this date is locked. Only management can edit historical records older than 7 days.');
      }
    }

    final prefix = className.replaceAll(' ', '_');
    final key    = '${prefix}_${date.year}-${date.month}-${date.day}';
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(key)
        .set({'rolls': rolls, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
    _invalidateDayDoc(key);
  }

  /// Marks a student as 'Leave' for every day in the given range.
  ///
  /// Non-working days are skipped based on the school's configured working week
  /// (`workingDays` = 'Mon-Sat' or 'Mon-Fri', #44) — so a Mon-Fri school no
  /// longer gets a spurious Saturday 'Leave'. Arbitrary one-off holidays from
  /// the calendar are still not consulted (would need the holiday list here).
  ///
  /// A day already recorded as 'Present' is NOT overwritten (#45): the student
  /// was actually in school that day, and an approved leave must not erase a
  /// real attendance record. Days that are unmarked or marked Absent are set to
  /// Leave. Uses merge so other students are untouched.
  Future<void> markLeaveForDateRange({
    required String className,
    required int roll,
    required DateTime startDate,
    required int numberOfDays,
  }) async {
    final offDays = await _nonWorkingWeekdays();
    // Each date writes to a distinct attendance document, so the per-day
    // read+conditional-write operations are independent — run them in parallel.
    final futures = <Future<void>>[];
    for (int i = 0; i < numberOfDays; i++) {
      final date = startDate.add(Duration(days: i));
      if (offDays.contains(date.weekday)) continue;
      futures.add(_markLeavePreservingPresent(className, roll, date));
    }
    await Future.wait(futures);
  }

  /// Weekday numbers (DateTime.monday..sunday) that are NOT school days,
  /// derived from the school's `workingDays` setting. Defaults to Sunday-only
  /// (Mon-Sat) when the setting is missing or unrecognised.
  Future<Set<int>> _nonWorkingWeekdays() async {
    try {
      final settings = await TimetableService().getSettings(schoolId: _schoolId);
      final workingDays = (settings['workingDays'] as String?) ?? 'Mon-Sat';
      if (workingDays == 'Mon-Fri') {
        return {DateTime.saturday, DateTime.sunday};
      }
    } catch (_) {/* fall through to the safe default */}
    return {DateTime.sunday};
  }

  /// Sets [roll] to 'Leave' on [date] unless that day is already 'Present'.
  Future<void> _markLeavePreservingPresent(
      String className, int roll, DateTime date) async {
    final key =
        '${className.replaceAll(' ', '_')}_${date.year}-${date.month}-${date.day}';
    final doc = await _attendance.doc(key).get();
    if (doc.exists && doc.data() != null) {
      final rolls =
          Map<String, dynamic>.from((doc.data()!['rolls'] as Map?) ?? {});
      final cur = rolls[roll.toString()];
      final curStatus = cur is bool ? (cur ? 'Present' : 'Absent') : cur;
      if (curStatus == 'Present') return; // don't erase a recorded presence
    }
    await saveAttendanceForDate(
      className: className,
      attendance: {roll: 'Leave'},
      date: date,
    );
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
    final out = <int, String>{};
    raw.forEach((k, v) {
      final roll = int.tryParse(k);
      if (roll != null) out[roll] = v.toString();
    });
    return out;
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
    final now     = SchoolClock.now();
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
          final roll = int.tryParse(k);
          if (roll == null) return;
          attendance[roll] =
              v is bool ? (v ? 'Present' : 'Absent') : v.toString();
        });
        reasonsRaw.forEach((k, v) {
          final roll = int.tryParse(k);
          if (roll != null) reasons[roll] = v.toString();
        });
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
    final now    = SchoolClock.now();
    final prefix = className.replaceAll(' ', '_');

    final datas = await Future.wait(
      List.generate(days, (i) {
        final date = now.subtract(Duration(days: i));
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _dayDocData(key, cacheable: i != 0); // i==0 is today
      }),
    );

    final result = <int, int>{};
    for (final data in datas) {
      if (data == null) continue;
      final rolls = Map<String, dynamic>.from((data['rolls'] as Map?) ?? {});
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
    final out = <int, bool>{};
    raw.forEach((k, v) {
      final roll = int.tryParse(k);
      if (roll != null) out[roll] = v as bool? ?? false;
    });
    return out;
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
    final now         = SchoolClock.now();
    final today       = DateTime(now.year, now.month, now.day);

    final datas = await Future.wait(
      List.generate(daysInMonth, (i) {
        final day = i + 1;
        // Cache strictly-past days only; today (and any future day in the
        // current month) is always read fresh.
        final cacheable = DateTime(year, month, day).isBefore(today);
        return _dayDocData('${prefix}_$year-$month-$day', cacheable: cacheable);
      }),
    );

    final result = <int, Map<int, String>>{};
    for (var i = 0; i < datas.length; i++) {
      final data = datas[i];
      if (data == null) continue;
      final rolls = Map<String, dynamic>.from((data['rolls'] as Map?) ?? {});
      if (rolls.isEmpty) continue;
      result[i + 1] = _parseRolls(rolls);
    }
    return result;
  }

  /// Returns roll → number of consecutive school days absent/on leave,
  /// counting backwards from today. Days with no record are skipped.
  Future<Map<int, int>> loadConsecutiveAbsenceDays(String className,
      {int maxDays = 20}) async {
    final now    = SchoolClock.now();
    final prefix = className.replaceAll(' ', '_');

    // Build ordered list of (index, date) pairs — today first, past last.
    // Future.wait preserves order so the streak walk below sees days
    // newest → oldest.
    final dates = List.generate(maxDays, (i) => now.subtract(Duration(days: i)));
    final datas = await Future.wait(
      dates.asMap().entries.map((e) {
        final i    = e.key;
        final date = e.value;
        final key  = '${prefix}_${date.year}-${date.month}-${date.day}';
        return _dayDocData(key, cacheable: i != 0); // i==0 is today
      }),
    );

    final streaks = <int, int>{};
    final broken  = <int>{};

    for (int i = 0; i < datas.length; i++) {
      final date = dates[i];
      final data = datas[i];

      // Skip weekend days — Sat (6) and Sun (7) are not school days and
      // must never break or extend a streak (#42).
      if (date.weekday == DateTime.saturday ||
          date.weekday == DateTime.sunday) { continue; }

      if (data == null) {
        // Missing doc on a weekday:
        //   • Within the last 7 days: attendance SHOULD have been taken —
        //     treat as "no one absent that day" → breaks any active streak.
        //   • Older than 7 days: could be a public holiday / closed day —
        //     skip (don't penalise or reward).
        if (i < 7) {
          // A missing recent weekday doc means the teacher didn't mark
          // anyone absent — that implies students were present.
          // Add every student currently in a streak to the broken set.
          final currentlyStreaking = streaks.keys
              .where((r) => !broken.contains(r))
              .toList();
          broken.addAll(currentlyStreaking);
        }
        continue;
      }

      final rolls = Map<String, dynamic>.from((data['rolls'] as Map?) ?? {});
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

  /// Writes a read-only tombstone for [student] into `deleted_students` so the
  /// removal is preserved in the "Deleted Students" history. Best-effort: a
  /// failure here is logged and skipped — it must not abort the deletion.
  Future<void> _recordDeletedStudent(Student student) async {
    try {
      await _deletedStudentsRef.add(DeletedStudent(
        roll:          student.roll,
        name:          student.name,
        className:     student.className,
        section:       student.section,
        guardianEmail: student.guardianEmail,
        teacherId:     student.teacherId,
      ).toJson());
    } catch (e) {
      AppLogger.e('StudentService', 'deleted-student tombstone failed: $e', e);
    }
  }

  /// Deletes all notifications addressed to this student's guardian.
  Future<void> _cascadeDeleteStudentNotifications(
      String className, int roll) async {
    try {
      final audience = 'guardian:$className:$roll';
      final snap = await schoolCollection(_schoolId, 'notifications')
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

  /// Purges leave-request notifications tied to this student.
  ///
  /// The "leave submitted" notice is addressed to the class teacher
  /// (`audience: class_teacher:{class}`), so it is NOT keyed by roll and is
  /// missed by [_cascadeDeleteStudentNotifications] (which targets the
  /// guardian audience — that path already removes the "leave resolved"
  /// notices). Here we scope to the class-teacher channel and delete the
  /// entries belonging to the deleted student by the `studentRoll` field
  /// stamped on the document, falling back to the student name in the title
  /// for legacy notices written before that field existed.
  Future<void> _cascadeDeleteStudentLeaveNotifications(
      String className, int roll, String studentName) async {
    try {
      final snap = await schoolCollection(_schoolId, 'notifications')
          .where('audience', isEqualTo: 'class_teacher:$className')
          .get();
      final wantTitle = 'Leave request: $studentName';
      final matches = snap.docs.where((d) {
        final data = d.data();
        if (data['type'] != 'student_leave_submitted') return false;
        final r = (data['studentRoll'] as num?)?.toInt();
        // Newer notices carry the roll; legacy ones fall back to the name.
        return r != null ? r == roll : data['title'] == wantTitle;
      }).toList();
      if (matches.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in matches) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Guardian / School Detail Updates Synced Workflows ──────────────────────────

  CollectionReference<Map<String, dynamic>> _guardianDetailsRef(String studentId) =>
      _studentsRef.doc(studentId).collection('guardianProvidedDetails');

  CollectionReference<Map<String, dynamic>> _schoolDetailsRef(String studentId) =>
      _studentsRef.doc(studentId).collection('schoolProvidedDetails');

  Future<void> submitGuardianProvidedDetails(
      String studentId, GuardianProvidedDetails details) async {
    final ref = _guardianDetailsRef(studentId);
    await ref.add(details.toJson());
  }

  Stream<List<GuardianProvidedDetails>> watchGuardianProvidedDetails(String studentId) {
    return _guardianDetailsRef(studentId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => GuardianProvidedDetails.fromJson(d.id, d.data()))
            .toList());
  }

  Future<void> updateGuardianProvidedDetailsStatus(
      String studentId, String detailId, String status,
      {String remarks = ''}) async {
    await _guardianDetailsRef(studentId).doc(detailId).update({
      'status': status,
      'remarks': remarks,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> submitSchoolProvidedDetails(
      String studentId, SchoolProvidedDetails details) async {
    final ref = _schoolDetailsRef(studentId);
    await ref.add(details.toJson());
  }

  Stream<List<SchoolProvidedDetails>> watchSchoolProvidedDetails(String studentId) {
    return _schoolDetailsRef(studentId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SchoolProvidedDetails.fromJson(d.id, d.data()))
            .toList());
  }

  Future<void> updateSchoolProvidedDetailsStatus(
      String studentId, String detailId, String status,
      {String remarks = ''}) async {
    await _schoolDetailsRef(studentId).doc(detailId).update({
      'status': status,
      'remarks': remarks,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}


/// Cache entry for a past attendance day doc (#72/#177). [data] is null when the
/// doc does not exist (a no-attendance day) — cached too so we don't re-fetch
/// known-empty days.
class _DayDocEntry {
  final Map<String, dynamic>? data;
  final DateTime at;
  const _DayDocEntry(this.data, this.at);
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
