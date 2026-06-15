import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/utils/app_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/deleted_student.dart';
import '../models/student.dart';
import '../models/student_remark.dart';
import '../models/parental_consent.dart';
import '../models/guardian_provided_details.dart';
import '../models/school_provided_details.dart';
import '../repositories/student_repository.dart';
import '../shared/utils/app_logger.dart';
import '../shared/utils/phone_utils.dart';
import '../shared/utils/school_clock.dart';
import 'audit_log_service.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'notification_service.dart';
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

  static StudentService get instance => _instance ??= StudentService._(FirestoreStudentRepository());

  static set mockInstance(StudentService? mock) => _instance = mock;

  factory StudentService([StudentRepository? repo]) {
    if (repo != null) return StudentService._(repo);
    return _instance ??= StudentService._(FirestoreStudentRepository());
  }

  StudentService._(this._repo);

  // ── Firestore refs (attendance only — students live in the repo) ────────────

  String get _schoolId => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      schoolCollection(_schoolId, 'attendance');

  /// Per-student attendance mirror (H2). The class-day `attendance/{cls}` doc
  /// holds EVERY classmate's status in one document, so a guardian reading it
  /// would see the whole class. To keep guardians scoped to their own child,
  /// the `onAttendanceWritten` Cloud Function mirrors each student's daily
  /// status into `student_attendance/{studentDocId}.days_{YYYY}` (server-side,
  /// Admin SDK; year-partitioned per SCALE-13 to keep the doc bounded).
  /// Guardians read ONLY their child's mirror doc; the class doc is now
  /// staff-only. Doc id = Student.buildDocId(roll, className, section).
  CollectionReference<Map<String, dynamic>> get _studentAttendance =>
      schoolCollection(_schoolId, 'student_attendance');

  // ── Attendance day-doc read cache (#72/#177) ────────────────────────────────
  // Dashboards (coordinator/principal/owner/analytics) recompute recent- and
  // consecutive-absence by fetching ~14–20 day docs PER class on every open,
  // and the same day docs are re-fetched across `loadRecentAbsenceDays`,
  // `loadConsecutiveAbsenceDays` and `loadMonthAttendance`. PAST day docs are
  // effectively immutable (historical edits are lock-gated, #34), so caching
  // them for a short TTL collapses those repeated reads. TODAY's doc is never
  // cached (it mutates as marks come in), and any write invalidates its key.
  static const Duration _dayDocTtl = Duration(seconds: 30);
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

  /// Fetch students for a class/section paginated, optionally scoped to one teacher.
  Future<({List<Student> entries, dynamic cursor})> getStudentsByClassPaginated({
    required String className,
    String section = '',
    String? teacherId,
    required int limit,
    dynamic startAfter,
  }) async {
    final page = await _repo.fetchByClassPaginated(
      className,
      section,
      teacherId: teacherId,
      limit: limit,
      startAfter: startAfter,
    );
    return (entries: _visibleOnly(page.entries), cursor: page.cursor);
  }

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

  /// Real-time, BOUNDED change-detection window over the school's students
  /// (see [StudentRepository.watchAll] — capped, NOT a complete roster). Use it
  /// only to react to roster changes; for a COMPLETE list (exports, reports,
  /// counts) call [getStudents], which cursor-paginates the whole collection.
  Stream<List<Student>> watchStudents({String? schoolId}) =>
      _repo.watchAll().map(_visibleOnly);

  /// Roster-change signal for dashboards (SCALE-03): live per-class visible
  /// enrolment totals from the tiny `class_stats` collection (one doc per
  /// class, maintained server-side by the syncClassStats trigger on every
  /// student create/delete/visibility/class change). Listening to this instead
  /// of [watchStudents] costs O(#classes) docs instead of a 500-student
  /// window, and is EXACT — no cap to outgrow.
  Stream<Map<String, int>> watchClassStatsTotals() =>
      schoolCollection(_schoolId, 'class_stats').snapshots().map((snap) => {
            for (final d in snap.docs)
              d.id: ((d.data()['total'] as num?)?.toInt() ?? 0),
          });

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

  /// Real-time stream of all students for a class/section, including those
  /// marked as pending deletion (but excluding promoted ones).
  Stream<List<Student>> watchAllStudentsByClass({
    required String className,
    String section = '',
    String? teacherId,
  }) {
    return _repo
        .watchByClass(className, section, teacherId: teacherId)
        .map((list) => list.where((s) => !s.promoted).toList());
  }

  /// Live stream of deleted students combined with students pending deletion,
  /// newest first. Pending deletion students are represented as DeletedStudent
  /// objects with a null deletedAt timestamp.
  Stream<List<DeletedStudent>> watchDeletedAndPendingStudents({
    String? className,
    String? section,
  }) {
    final deletedStream = watchDeletedStudents();
    final Stream<List<Student>> activeStream;
    if (className != null && className.isNotEmpty) {
      activeStream = _repo.watchByClass(className, section ?? '');
    } else {
      activeStream = _repo.watchAll();
    }

    final controller = StreamController<List<DeletedStudent>>();
    List<DeletedStudent> lastDeleted = [];
    List<Student> lastPending = [];
    bool deletedEmitted = false;
    bool pendingEmitted = false;

    void emitMerged() {
      if (controller.isClosed) return;
      if (!deletedEmitted || !pendingEmitted) return;
      final pendingList = lastPending
          .where((s) => s.deletionPending && !s.promoted)
          .map((s) => DeletedStudent(
                id: 'pending_${s.id}',
                roll: s.roll,
                name: s.name,
                className: s.className,
                section: s.section,
                teacherId: s.teacherId,
                deletedAt: null,
              ))
          .toList();

      final merged = [...pendingList, ...lastDeleted];
      merged.sort((a, b) {
        if (a.deletedAt == null && b.deletedAt == null) return a.name.compareTo(b.name);
        if (a.deletedAt == null) return -1;
        if (b.deletedAt == null) return 1;
        return b.deletedAt!.compareTo(a.deletedAt!);
      });
      controller.add(merged);
    }

    final sub1 = deletedStream.listen(
      (data) {
        lastDeleted = data;
        deletedEmitted = true;
        emitMerged();
      },
      onError: (Object e, StackTrace st) {
        // If either inner stream errors, propagate the error and close the
        // controller so callers get a proper error event (Issue 23).
        if (!controller.isClosed) {
          controller.addError(e, st);
          controller.close();
        }
      },
    );

    final sub2 = activeStream.listen(
      (data) {
        lastPending = data;
        pendingEmitted = true;
        emitMerged();
      },
      onError: (Object e, StackTrace st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
          controller.close();
        }
      },
    );

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };

    return controller.stream;
  }

  /// Generates a stable cross-year admission id (Issue 18).
  /// Uses UUID v4 to guarantee global uniqueness even across simultaneous
  /// insertions — the previous microsecond-based suffix was not truly random.
  static const _uuid = Uuid();
  static String _newAdmissionId() => 'STU-${_uuid.v4()}';
  
  static String _generateParentInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = math.Random();
    final code = String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    return 'INV-$code';
  }

  String _toTitleCase(String text) {
    if (text.trim().isEmpty) return text;
    return text.trim().split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return '';
      return word.split('-').map((subWord) {
        if (subWord.isEmpty) return '';
        return subWord[0].toUpperCase() + subWord.substring(1).toLowerCase();
      }).join('-');
    }).join(' ');
  }

  /// Returns null on success, error string on duplicate roll.
  Future<String?> addStudent({required Student student}) async {
    // 1. Sanitize fields
    var sanitized = student.copyWith(
      className: _toTitleCase(student.className),
      section: student.section.trim().toUpperCase(),
      name: stripHtml(student.name).trim(),
      fatherName: stripHtml(student.fatherName).trim(),
      motherName: student.motherName != null ? stripHtml(student.motherName!).trim() : null,
      phone: student.phone.isNotEmpty ? normalizePhone(student.phone) : '',
      parentPhone: student.parentPhone != null && student.parentPhone!.isNotEmpty
          ? normalizePhone(student.parentPhone!)
          : null,
      schoolId: _schoolId,
    );

    // 2. Stamp stable admissionId
    if (sanitized.admissionId.trim().isEmpty) {
      sanitized = sanitized.copyWith(admissionId: _newAdmissionId());
    }
    if (sanitized.parentInviteCode == null || sanitized.parentInviteCode!.isEmpty) {
      sanitized = sanitized.copyWith(parentInviteCode: _generateParentInviteCode());
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

  /// Atomically imports multiple students in a Firestore batch, performing local
  /// and database uniqueness validations, creating parental consent records,
  /// and parallelizing post-commit guardian onboarding operations.
  Future<Map<String, dynamic>> addStudentsBulk({
    required List<Student> students,
    required bool assertConsent,
  }) async {
    int addedCount = 0;
    int skippedDbDuplicate = 0;
    int skippedCsvDuplicate = 0;
    int skippedInvalid = 0;

    final List<Student> validStudents = [];
    final Set<String> csvSeen = {};

    // 1. Structural and CSV-level validation
    for (final s in students) {
      if (s.name.trim().isEmpty || s.className.trim().isEmpty || s.roll <= 0) {
        skippedInvalid++;
        continue;
      }

      final key = '${_toTitleCase(s.className)}_${s.section.trim().toUpperCase()}_${s.roll}';
      if (csvSeen.contains(key)) {
        skippedCsvDuplicate++;
        continue;
      }
      csvSeen.add(key);

      validStudents.add(s);
    }

    if (validStudents.isEmpty) {
      return {
        'addedCount': 0,
        'skippedDbDuplicate': 0,
        'skippedCsvDuplicate': skippedCsvDuplicate,
        'skippedInvalid': skippedInvalid,
      };
    }

    // 2. Fetch existing students in database for target class-sections to check duplicate rolls
    final targetClassSections = validStudents.map((s) => (s.className, s.section)).toSet();
    final Map<String, Set<int>> dbExistingRolls = {}; // 'className_section' -> Set of rolls
    await Future.wait(targetClassSections.map((cs) async {
      final key = '${cs.$1}_${cs.$2}';
      try {
        final list = await getStudentsByClass(className: cs.$1, section: cs.$2);
        dbExistingRolls[key] = list.map((student) => student.roll).toSet();
      } catch (e) {
        AppLogger.e('StudentService', 'Failed to fetch existing students for $key: $e', e);
        dbExistingRolls[key] = {};
      }
    }));

    // 3. Database validation
    final List<Student> finalImportList = [];
    for (final s in validStudents) {
      final key = '${_toTitleCase(s.className)}_${s.section.trim().toUpperCase()}';
      final existing = dbExistingRolls[key];
      if (existing != null && existing.contains(s.roll)) {
        skippedDbDuplicate++;
        continue;
      }
      finalImportList.add(s);
    }

    if (finalImportList.isEmpty) {
      return {
        'addedCount': 0,
        'skippedDbDuplicate': skippedDbDuplicate,
        'skippedCsvDuplicate': skippedCsvDuplicate,
        'skippedInvalid': skippedInvalid,
      };
    }

    // 4. Firestore Batch Write
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final List<Student> processedStudents = [];

    for (final s in finalImportList) {
      // Sanitize fields (similar to addStudent)
      var sanitized = s.copyWith(
        className: _toTitleCase(s.className),
        section: s.section.trim().toUpperCase(),
        name: stripHtml(s.name).trim(),
        fatherName: stripHtml(s.fatherName).trim(),
        motherName: s.motherName != null ? stripHtml(s.motherName!).trim() : null,
        phone: s.phone.isNotEmpty ? normalizePhone(s.phone) : '',
        parentPhone: s.parentPhone != null && s.parentPhone!.isNotEmpty
            ? normalizePhone(s.parentPhone!)
            : null,
        schoolId: _schoolId,
      );

      // Stamp stable admissionId
      if (sanitized.admissionId.trim().isEmpty) {
        sanitized = sanitized.copyWith(admissionId: _newAdmissionId());
      }
      if (sanitized.parentInviteCode == null || sanitized.parentInviteCode!.isEmpty) {
        sanitized = sanitized.copyWith(parentInviteCode: _generateParentInviteCode());
      }

      final docId = Student.buildDocId(sanitized.roll, sanitized.className, sanitized.section);
      final studentDocRef = db.collection('schools').doc(_schoolId).collection('students').doc(docId);
      
      final studentToSet = sanitized.copyWith(id: docId);
      batch.set(studentDocRef, studentToSet.toJson());

      // If assertConsent is true, create consent doc under the student's sub-collection
      if (assertConsent) {
        final consentRef = studentDocRef.collection('consents').doc();
        final consent = ParentalConsent(
          id: consentRef.id,
          studentId: docId,
          guardianName: sanitized.fatherName.isNotEmpty ? sanitized.fatherName : 'Parent',
          guardianPhone: sanitized.phone.isNotEmpty ? sanitized.phone : '0000000000',
          guardianEmail: sanitized.guardianEmail,
          consentVersion: kCurrentConsentVersion,
          consentedAt: Timestamp.now(),
          method: ConsentMethod.inPersonSigned,
          scopes: ParentalConsent.defaultScopes(),
        );
        batch.set(consentRef, consent.toJson());
      }

      processedStudents.add(studentToSet);
    }

    // Commit batch write
    await batch.commit();
    addedCount = processedStudents.length;

    // 5. Post-Commit tasks (parallelized)
    final postCommitTasks = <Future<void>>[];
    for (final s in processedStudents) {
      // Emit audit log
      AuditService.emit(
        action: 'create',
        entity: 'student',
        entityId: s.id,
        after: s.toJson(),
      );

      // Guardian account onboarding
      if (s.guardianEmail != null && s.guardianEmail!.trim().isNotEmpty) {
        postCommitTasks.add(() async {
          try {
            await _upsertGuardianAccount(
              email: s.guardianEmail!.trim().toLowerCase(),
              className: s.className,
              roll: s.roll,
              section: s.section,
              name: s.name,
              admissionId: s.admissionId,
            );
          } catch (e) {
            AppLogger.e('StudentService', 'Bulk import guardian account upsert failed for ${s.name}: $e', e);
          }
        }());
      }
    }

    if (postCommitTasks.isNotEmpty) {
      await Future.wait(postCommitTasks);
    }

    return {
      'addedCount': addedCount,
      'skippedDbDuplicate': skippedDbDuplicate,
      'skippedCsvDuplicate': skippedCsvDuplicate,
      'skippedInvalid': skippedInvalid,
    };
  }

  Future<String?> updateStudent({required Student updated}) async {
    // 1. Sanitize fields
    var sanitized = updated.copyWith(
      className: _toTitleCase(updated.className),
      section: updated.section.trim().toUpperCase(),
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
    final svc = TimetableService.instance;
    // No 'school_1' fallback: this WRITES the guardian's allowed_users doc, so
    // a wrong tenant id here permanently provisions the guardian into the
    // wrong school. AuthService.currentSchoolId fails loud (StateError) when
    // the session's school isn't resolved yet (SCALE-06).
    final effectiveSchoolId =
        (schoolId != null && schoolId.isNotEmpty)
            ? schoolId
            : AuthService.currentSchoolId;
    // Empty password ⇒ addAllowedUser mints a strong random temp credential.
    final uid = await svc.addAllowedUser(
      email, '', 'guardian',
      name:         name,
      schoolId:     effectiveSchoolId,
      studentClass: className,
      studentRoll:  roll,
      studentSection: section,
      studentAdmissionId: admissionId,
    );
    await svc.linkGuardianEmail(
      uid:          uid,
      email:        email,
      studentClass: className,
      studentRoll:  roll,
      studentSection: section,
      studentName:  name,
      studentAdmissionId: admissionId,
    );
    // Issue 21: also update the existing allowed_users doc with the new
    // class/section/roll so the guardian's cached session points to the
    // correct class after promotion.
    try {
      await appFunctions.httpsCallable('updateUserMetadata').call(<String, dynamic>{
        'email': email.toLowerCase().trim(),
        'studentClass': className,
        'studentRoll': roll,
        'studentSection': section,
        if (admissionId != null && admissionId.isNotEmpty)
          'studentAdmissionId': admissionId,
      });
    } catch (e) {
      AppLogger.e('StudentService',
          '_upsertGuardianAccount allowed_users update failed (non-fatal): $e', e);
    }
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

    // Issue 27: Guardian link revocation is now a BLOCKING prerequisite before
    // writing the new email. A failure here surfaces to the caller so the admin
    // knows the old guardian still has access and can retry. Previously this was
    // fire-and-forget (try/catch swallowed), leaving the old guardian active.
    if (oldEmail != null &&
        oldEmail.isNotEmpty &&
        oldEmail != email.trim().toLowerCase()) {
      // This will throw if revocation fails — let the caller handle it.
      await TimetableService.instance.removeGuardianLink(
        email:        oldEmail,
        studentClass: className,
        studentRoll:  roll,
        studentSection: section,
      );
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

    // Issue 29: Tombstone is written AFTER a successful cascade so the deleted
    // students history only shows genuinely deleted students. Previously it was
    // written first, which created zombie entries when the cascade failed.
    // Prefer the server-side cascade (#35): the deleteStudent Cloud Function
    // runs the whole cleanup to completion server-side. Fall back to the
    // client cascade if unavailable.
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
          schoolCollection(_schoolId, 'payments')
              .where('className', isEqualTo: className)
              .where('roll', isEqualTo: roll)
              .get(),
          FirebaseFirestore.instance
              .collection('copy_checks')
              .where('schoolId', isEqualTo: _schoolId)
              .where('className', isEqualTo: className)
              .where('section', isEqualTo: section)
              .get(),
        ]);

        final remarksSnap = results[0];
        final attendanceSnap = results[1];
        final notificationsSnap = results[2];
        final teacherNotificationsSnap = results[3];
        final leaveAppsSnap = results[4];
        final examsSnap = results[5];
        final paymentsSnap = results[6];
        final copyChecksSnap = results[7];

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

        // 1. Remarks
        for (final doc in remarksSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 2. Attendance updates
        for (final doc in attendanceSnap.docs) {
          final rolls = Map<String, dynamic>.from((doc.data()['rolls'] as Map?) ?? {});
          if (rolls.containsKey(roll.toString())) {
            batchOps.add((batch) async => batch.update(doc.reference, {'rolls.$roll': FieldValue.delete()}));
          }
        }

        // 3. Notifications
        for (final doc in notificationsSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 4. Leave notifications
        for (final doc in leaveNotificationsMatches) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 5. Leave applications
        for (final doc in leaveAppsMatches) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }

        // 6. Exam results
        for (final examDoc in examsSnap.docs) {
          final ref = schoolCollection(_schoolId, 'exam_results')
              .doc(examDoc.id)
              .collection('students')
              .doc('$roll');
          batchOps.add((batch) async => batch.delete(ref));
        }

        // 7. Fee payments
        for (final doc in paymentsSnap.docs) {
          batchOps.add((batch) async => batch.delete(doc.reference));
        }
        batchOps.add((batch) async => batch.delete(studentNode));

        // 8. Copy check statuses
        for (final ccDoc in copyChecksSnap.docs) {
          final ref = FirebaseFirestore.instance
              .collection('copy_checks')
              .doc(ccDoc.id)
              .collection('statuses')
              .doc('$roll');
          batchOps.add((batch) async => batch.delete(ref));
        }

        // 9. Delete student doc (last to prevent orphaned records in case of failure, #35)
        batchOps.add((batch) async => batch.delete(_studentsRef.doc(studentDocId)));

        // Commit in chunks of up to 450 operations each (Firestore limit is 500;
        // we use 450 for headroom). clamp() ensures we never exceed this limit.
        for (var i = 0; i < batchOps.length; i += 450) {
          final batch = FirebaseFirestore.instance.batch();
          final end = (i + 450).clamp(0, batchOps.length);
          final chunk = batchOps.sublist(i, end);
          for (final op in chunk) {
            await op(batch);
          }
          await batch.commit();
        }
      }
    }

    // Record tombstone AFTER successful cascade so the Deleted Students history
    // only shows truly deleted records. (Issue 29 fix: was written before cascade.)
    // Best-effort — must not abort the deletion if this write fails.
    await _recordDeletedStudent(student);

    AuditService.emit(
      action:   'delete',
      entity:   'student',
      entityId: student.id.isNotEmpty
          ? student.id
          : '${className}_${section}_$roll',
      before: student.toJson(),
      reason: 'principal-approved deletion',
    );

    // 6. Revoke guardian login (best-effort). Retry up to 3 times in case of transient failures.
    final guardianEmail = student.guardianEmail;
    if (guardianEmail != null && guardianEmail.trim().isNotEmpty) {
      const int maxAttempts = 3;
      int attempt = 0;
      bool success = false;
      while (attempt < maxAttempts && !success) {
        try {
          final svc = TimetableService.instance;
          await svc.removeGuardianLink(
            email: guardianEmail,
            studentClass: className,
            studentRoll: roll,
            studentSection: section,
          );
          final remaining = await svc.getGuardianLinks(guardianEmail);
          if (remaining == null || remaining.isEmpty) {
            await svc.removeAllowedUser(guardianEmail);
          }
          success = true;
        } catch (e) {
          attempt++;
          AppLogger.w('StudentService', 'guardian login revoke attempt $attempt failed: $e');
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(milliseconds: 500));
          } else {
            AppLogger.e('StudentService', 'guardian login revoke failed after $maxAttempts attempts (non-fatal): $e', e);
          }
        }
      }
    }
  }

  /// Calls the server-side cascade-delete Cloud Function (#35). Returns true on
  /// success; throws on transport/permission/not-deployed errors so the caller
  /// can fall back to the client cascade.
  Future<bool> _serverDeleteStudent(
      String className, String section, int roll) async {
    final callable = appFunctions.httpsCallable('deleteStudent');
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
      } catch (e, stack) {
        AppLogger.e('StudentService', 'Failed to mark deletion pending for student: $e', e, stack);
      }
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
    try {
      final callable = appFunctions.httpsCallable('approveDeletionRequest');
      final res = await callable.call(<String, dynamic>{
        'schoolId': _schoolId,
        'requestId': requestId,
      });
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        return;
      }
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Cloud approveDeletionRequest failed, falling back to client-side loop: $e', e, stack);
    }

    final data = await _repo.getDeletionRequest(requestId);
    if (data == null) return;
    final list =
        (data['students'] as List?)?.whereType<Map<String, dynamic>>() ?? [];
    final futures = <Future<void>>[];
    for (final s in list) {
      final roll      = (s['roll']      as num?)?.toInt() ?? 0;
      final className = (s['className'] as String?) ?? '';
      final section   = (s['section']   as String?) ?? '';
      if (roll > 0 && className.isNotEmpty) {
        futures.add(removeStudent(roll, className, section: section));
      }
    }
    await Future.wait(futures);
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

  static String _attendanceDocKey(String className, DateTime date) {
    final prefix = className.replaceAll(' ', '_');
    return '${prefix}_${SchoolClock.dateKey(date)}';
  }

  String _todayKey(String className) {
    // Anchor "today" to the school timezone, not the device's (#43).
    final now = SchoolClock.now();
    return _attendanceDocKey(className, now);
  }

  /// Returns 'Present' | 'Absent' | 'Leave' per roll number.
  /// Backward-compatible: old bool values are migrated automatically.
  /// Parses a `rolls` map (roll-string → status) into roll-int → status,
  /// SKIPPING any malformed (non-numeric) key. A single bad key previously
  /// crashed the whole class load via int.parse (#50).
  ///
  /// Handles dual attendance formats (Issue 28):
  ///   - New format: String values  ('Present' | 'Absent' | 'Leave')
  ///   - Old format: bool values    (true → 'Present', false → 'Absent')
  ///   - Unknown:    any other type → '' (unmarked) to fail gracefully.
  static Map<int, String> _parseRolls(Map<String, dynamic> rolls) {
    final out = <int, String>{};
    rolls.forEach((k, v) {
      final roll = int.tryParse(k);
      if (roll == null) return;
      if (v is String) {
        out[roll] = v;          // Current format: 'Present', 'Absent', 'Leave'
      } else if (v is bool) {
        out[roll] = v ? 'Present' : 'Absent';  // Legacy bool format
      }
      // Any other type (null, int, etc.) is silently skipped → '' (unmarked).
    });
    return out;
  }

  Stream<Map<int, String>> watchTodayAttendance({required String className}) {
    return _attendance.doc(_todayKey(className)).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return {};
      final rolls = Map<String, dynamic>.from((doc.data()!['rolls'] as Map?) ?? {});
      return _parseRolls(rolls);
    });
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
    final now = SchoolClock.now();
    final docKey = _attendanceDocKey(className, now);
    final prev   = await _attendance.doc(docKey).get();
    final isUpdate = prev.exists;
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(docKey)
        .set({
          'rolls': rolls,
          'updatedAt': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
        }, SetOptions(merge: true));
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

    final key    = _attendanceDocKey(className, date);
    final prev   = await _attendance.doc(key).get();
    final isUpdate = prev.exists;
    final rolls  = attendance.map((k, v) => MapEntry(k.toString(), v));
    await _attendance
        .doc(key)
        .set({
          'rolls': rolls,
          'updatedAt': FieldValue.serverTimestamp(),
          'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
        }, SetOptions(merge: true));
    _invalidateDayDoc(key);

    AuditService.emit(
      action:   isUpdate ? 'update' : 'create',
      entity:   'attendance',
      entityId: key,
      before:   isUpdate && prev.data() != null
          ? Map<String, dynamic>.from(prev.data()!)
          : null,
      after:    {'rolls': rolls},
      reason:   'historical_edit',
    );
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
      final settings = await TimetableService.instance.getSettings(schoolId: _schoolId);
      final workingDays = (settings['workingDays'] as String?) ?? 'Mon-Sat';
      if (workingDays == 'Mon-Fri') {
        return {DateTime.saturday, DateTime.sunday};
      }
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Error getting settings for non-working weekdays: $e', e, stack);
    }
    return {DateTime.sunday};
  }

  /// Sets [roll] to 'Leave' on [date] unless that day is already 'Present'.
  Future<void> _markLeavePreservingPresent(
      String className, int roll, DateTime date) async {
    final key = _attendanceDocKey(className, date);
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
    final now = SchoolClock.now();
    await _attendance.doc(_todayKey(className)).set(
          {
            'reasons': raw,
            'updatedAt': FieldValue.serverTimestamp(),
            'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
          },
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
  ///
  /// SCALE-02: reads ONLY the maintained rollups — `class_stats` (per-class
  /// visible-enrollment totals, kept by the syncClassStats trigger) and today's
  /// `attendance_summary` docs (per-section counts + the absent/leave detail
  /// list, kept by onAttendanceWritten) — and NEVER the whole student roster.
  /// Reads drop from O(all students in the school) on every dashboard open to
  /// O(#classes + #sections-marked-today), independent of enrolment size.
  ///
  /// Deploy ordering: after deploying the triggers, run the `backfillClassStats`
  /// and `backfillAttendanceSummary` callables once; until then totals read 0
  /// and already-marked classes read as unmarked.
  Future<List<ClassSummary>> loadTodayFullSummary(
      {required List<String> classes, String? schoolId}) async {
    if (classes.isEmpty) return [];
    final todayKey = SchoolClock.todayKey();

    // 1. Per-class visible-enrolment totals (one small collection, no roster).
    //    Counter key = className with spaces → underscores (matches the trigger).
    final statsSnap = await schoolCollection(_schoolId, 'class_stats').get();
    final totalByKey = <String, int>{
      for (final d in statsSnap.docs)
        d.id: ((d.data()['total'] as num?)?.toInt() ?? 0),
    };

    // 2. Today's per-section summaries, found by date alone — no need to know
    //    which sections exist (which previously required the roster).
    final summarySnap = await schoolCollection(_schoolId, 'attendance_summary')
        .where('dateKey', isEqualTo: todayKey)
        .get();

    // 3. Assign each summary to its class by doc-id prefix. The doc id is
    //    "{classSectionPrefix}_{dateKey}"; strip the "_{dateKey}" suffix. A
    //    prefix belongs to the class whose sanitised key it equals (no section)
    //    or whose key + '_' it starts with (sectioned). Longest match wins so a
    //    class "Class 6" never swallows a distinct "Class 6 A".
    final dateSfxLen = todayKey.length + 1; // "_YYYY-MM-DD"
    final classKeys = {for (final c in classes) c: c.replaceAll(' ', '_')};
    final sortedClasses = classes.toList()
      ..sort((a, b) => classKeys[b]!.length.compareTo(classKeys[a]!.length));

    final byClass = <String, List<Map<String, dynamic>>>{
      for (final c in classes) c: <Map<String, dynamic>>[],
    };
    for (final doc in summarySnap.docs) {
      final id = doc.id;
      if (id.length <= dateSfxLen) continue;
      final prefix = id.substring(0, id.length - dateSfxLen);
      for (final cls in sortedClasses) {
        final key = classKeys[cls]!;
        if (prefix == key || prefix.startsWith('${key}_')) {
          byClass[cls]!.add(doc.data());
          break;
        }
      }
    }

    // 4. Merge each class's section summaries into one ClassSummary.
    return classes.map((cls) {
      final total = totalByKey[classKeys[cls]!] ?? 0;
      var present = 0, absent = 0, leave = 0;
      var marked = false;
      final absentLeave = <StudentNote>[];

      for (final data in byClass[cls]!) {
        present += (data['present'] as num?)?.toInt() ?? 0;
        absent  += (data['absent']  as num?)?.toInt() ?? 0;
        leave   += (data['leave']   as num?)?.toInt() ?? 0;
        marked   = marked || (data['marked'] == true);
        for (final e in (data['absentLeave'] as List?) ?? const []) {
          final m = Map<String, dynamic>.from(e as Map);
          absentLeave.add(StudentNote(
            name:   (m['name'] ?? 'Student').toString(),
            roll:   (m['roll'] as num?)?.toInt() ?? 0,
            status: (m['status'] ?? 'Absent').toString(),
            reason: m['reason'] as String?,
            phone:  (m['phone'] ?? '').toString(),
          ));
        }
      }
      absentLeave.sort((a, b) => a.roll.compareTo(b.roll));

      return ClassSummary(
        className:   cls,
        total:       total,
        present:     present,
        leave:       leave,
        absent:      absent,
        marked:      marked,
        absentLeave: absentLeave,
      );
    }).toList();
  }

  /// Returns roll → absent+leave count over the last [days] days (default 14).
  Future<Map<int, int>> loadRecentAbsenceDays(
      {required String className, int days = 14}) async {
    final now    = SchoolClock.now();
    final dates = List.generate(days, (i) => now.subtract(Duration(days: i)));

    await _preloadDaysForDates(className, dates);

    final datas = await Future.wait(
      dates.asMap().entries.map((e) {
        final i    = e.key;
        final date = e.value;
        final key  = _attendanceDocKey(className, date);
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

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadMonthDocs({
    required String className,
    required int year,
    required int month,
  }) async {
    final prefix = className.replaceAll(' ', '_');
    final paddedPrefix = '${prefix}_$year-${month.toString().padLeft(2, '0')}-';
    
    final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries = [
      _attendance
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: paddedPrefix)
          .where(FieldPath.documentId, isLessThanOrEqualTo: '$paddedPrefix\uf8ff')
          .get()
    ];
    
    if (month < 10) {
      final legacyPrefix = '${prefix}_$year-$month-';
      queries.add(
        _attendance
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: legacyPrefix)
            .where(FieldPath.documentId, isLessThanOrEqualTo: '$legacyPrefix\uf8ff')
            .get()
      );
    }
    
    final snaps = await Future.wait(queries);
    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final snap in snaps) {
      allDocs.addAll(snap.docs);
    }
    
    final seenIds = <String>{};
    final uniqueDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final now = SchoolClock.now();
    final today = DateTime(now.year, now.month, now.day);
    
    for (final doc in allDocs) {
      if (seenIds.add(doc.id)) {
        uniqueDocs.add(doc);
        
        // Populate cache for past days
        final parts = doc.id.split('_');
        if (parts.isNotEmpty) {
          final dateStr = parts.last;
          final dateParts = dateStr.split('-');
          if (dateParts.length == 3) {
            final y = int.tryParse(dateParts[0]);
            final m = int.tryParse(dateParts[1]);
            final d = int.tryParse(dateParts[2]);
            if (y != null && m != null && d != null) {
              final date = DateTime(y, m, d);
              if (date.isBefore(today)) {
                final cacheKey = '$_schoolId/${doc.id}';
                _dayDocCache[cacheKey] = _DayDocEntry(doc.data(), DateTime.now());
              }
            }
          }
        }
      }
    }
    return uniqueDocs;
  }

  Future<void> _preloadDaysForDates(String className, List<DateTime> dates) async {
    final monthsToFetch = <String, MapEntry<int, int>>{};
    for (final date in dates) {
      final key = '${date.year}_${date.month}';
      monthsToFetch[key] = MapEntry(date.year, date.month);
    }
    
    await Future.wait(
      monthsToFetch.values.map((entry) => _loadMonthDocs(
        className: className,
        year: entry.key,
        month: entry.value,
      ))
    );
  }

  /// Loads every attendance document for a class in a given month.
  /// Returns: { day → { roll → status } }
  Future<Map<int, Map<int, String>>> loadMonthAttendance(
      {required String className,
      required int year,
      required int month,
      String? schoolId}) async {
    final docs = await _loadMonthDocs(
      className: className,
      year: year,
      month: month,
    );

    final result = <int, Map<int, String>>{};
    for (final doc in docs) {
      final key = doc.id;
      final parts = key.split('_');
      if (parts.isEmpty) continue;
      final dateStr = parts.last;
      final dateParts = dateStr.split('-');
      if (dateParts.length != 3) continue;
      final y = int.tryParse(dateParts[0]);
      final m = int.tryParse(dateParts[1]);
      final d = int.tryParse(dateParts[2]);
      if (y != year || m != month || d == null) continue;

      final rolls = Map<String, dynamic>.from((doc.data()['rolls'] as Map?) ?? {});
      if (rolls.isEmpty) continue;
      result[d] = _parseRolls(rolls);
    }
    return result;
  }

  // ── Guardian-scoped attendance reads (H2) ──────────────────────────────────
  // These read the per-student mirror (`student_attendance/{studentDocId}`)
  // rather than the class-day doc, so a guardian only ever sees their OWN
  // child. They return the SAME shapes as the staff methods (keyed by roll) so
  // the guardian UI is unchanged. The matching firestore.rules grant a guardian
  // read of `student_attendance/{id}` only when id == their child's doc id.

  /// Extracts the dateKey→status map for one calendar [year] from a
  /// `student_attendance` mirror doc. Reads the year partition `days_{year}`
  /// (SCALE-13) and overlays it on any legacy flat `days` map, so docs written
  /// before partitioning — or seen mid-migration — still resolve. The partition
  /// takes precedence on key collisions.
  static Map<String, dynamic> _mirrorDaysForYear(
      Map<String, dynamic> data, String year) {
    final out = <String, dynamic>{};
    final legacy = data['days'];
    if (legacy is Map) out.addAll(Map<String, dynamic>.from(legacy));
    final partition = data['days_$year'];
    if (partition is Map) out.addAll(Map<String, dynamic>.from(partition));
    return out;
  }

  /// Today's status for one student → `{ roll: status }` (empty if unmarked).
  Future<Map<int, String>> loadTodayAttendanceForStudent({
    required String studentDocId,
    required int roll,
  }) async {
    final doc = await _studentAttendance.doc(studentDocId).get();
    if (!doc.exists || doc.data() == null) return {};
    final todayKey = SchoolClock.todayKey();
    final days = _mirrorDaysForYear(doc.data()!, todayKey.substring(0, 4));
    final status = days[todayKey];
    return (status is String && status.isNotEmpty) ? {roll: status} : {};
  }

  /// Live stream of today's status for one student → `{ roll: status }`.
  Stream<Map<int, String>> watchTodayAttendanceForStudent({
    required String studentDocId,
    required int roll,
  }) {
    return _studentAttendance.doc(studentDocId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return <int, String>{};
      final todayKey = SchoolClock.todayKey();
      final days = _mirrorDaysForYear(doc.data()!, todayKey.substring(0, 4));
      final status = days[todayKey];
      return (status is String && status.isNotEmpty)
          ? {roll: status}
          : <int, String>{};
    });
  }

  /// Month calendar for one student → `{ day → { roll: status } }`, matching
  /// [loadMonthAttendance]'s shape but containing only this child.
  Future<Map<int, Map<int, String>>> loadMonthAttendanceForStudent({
    required String studentDocId,
    required int roll,
    required int year,
    required int month,
  }) async {
    final doc = await _studentAttendance.doc(studentDocId).get();
    if (!doc.exists || doc.data() == null) return {};
    final days = _mirrorDaysForYear(doc.data()!, year.toString());
    final out = <int, Map<int, String>>{};
    days.forEach((dateKey, status) {
      if (status is! String || status.isEmpty) return;
      final parts = dateKey.split('-'); // padded 'YYYY-MM-DD'
      if (parts.length != 3) return;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y != year || m != month || d == null) return;
      out[d] = {roll: status};
    });
    return out;
  }

  /// Returns roll → number of consecutive school days absent/on leave,
  /// counting backwards from today. Days with no record are skipped.
  Future<Map<int, int>> loadConsecutiveAbsenceDays(String className,
      {int maxDays = 20}) async {
    final now    = SchoolClock.now();

    // 1. Get working days settings to determine weekends dynamically
    String workingDaysSetting = 'Mon-Sat';
    try {
      final settings = await TimetableService.instance.getSettings(schoolId: _schoolId);
      workingDaysSetting = (settings['workingDays'] as String?) ?? 'Mon-Sat';
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Error getting settings for consecutive absence: $e', e, stack);
    }

    // Build ordered list of (index, date) pairs — today first, past last.
    // Future.wait preserves order so the streak walk below sees days
    // newest → oldest.
    final dates = List.generate(maxDays, (i) => now.subtract(Duration(days: i)));

    await _preloadDaysForDates(className, dates);

    final datas = await Future.wait(
      dates.asMap().entries.map((e) {
        final i    = e.key;
        final date = e.value;
        final key  = _attendanceDocKey(className, date);
        return _dayDocData(key, cacheable: i != 0); // i==0 is today
      }),
    );

    return calculateStreaksFromData(
      dates: dates,
      datas: datas,
      workingDaysSetting: workingDaysSetting,
    );
  }

  /// Core consecutive-absence streak calculation logic, extracted for pure unit testing.
  static Map<int, int> calculateStreaksFromData({
    required List<DateTime> dates,
    required List<Map<String, dynamic>?> datas,
    required String workingDaysSetting,
  }) {
    final streaks = <int, int>{};
    final broken  = <int>{};
    bool firstWorkingDaySeen = false;

    for (int i = 0; i < datas.length; i++) {
      final date = dates[i];
      final data = datas[i];

      // Sunday is always a non-working day.
      // Saturday is a non-working day only if workingDays setting is 'Mon-Fri'.
      final isWeekend = date.weekday == DateTime.sunday ||
          (date.weekday == DateTime.saturday && workingDaysSetting == 'Mon-Fri');

      if (isWeekend) {
        continue;
      }

      if (!firstWorkingDaySeen) {
        firstWorkingDaySeen = true;
        if (data == null) {
          // If the most recent working day is unmarked, no one can have an active streak.
          return {};
        }
        final rolls = Map<String, dynamic>.from((data['rolls'] as Map?) ?? {});
        if (rolls.isEmpty) {
          return {};
        }
        rolls.forEach((rollStr, status) {
          final roll = int.tryParse(rollStr);
          if (roll == null) return;
          final isAbsent =
              status == 'Absent' || status == 'Leave' || status == false;
          if (isAbsent) {
            streaks[roll] = 1;
          } else {
            broken.add(roll);
          }
        });
        continue;
      }

      if (data == null) {
        // Missing doc on a working day: break all currently active streaks
        final currentlyStreaking = streaks.keys
            .where((r) => !broken.contains(r))
            .toList();
        broken.addAll(currentlyStreaking);
        continue;
      }

      final rolls = Map<String, dynamic>.from((data['rolls'] as Map?) ?? {});
      
      // If rolls is empty on a working day, it also breaks all active streaks
      if (rolls.isEmpty) {
        final currentlyStreaking = streaks.keys
            .where((r) => !broken.contains(r))
            .toList();
        broken.addAll(currentlyStreaking);
        continue;
      }

      // Check all rolls currently in an active streak. If they are not marked absent/leave on this day,
      // or if they are missing from the rolls map, break their streak.
      final activeStreakRolls = streaks.keys
          .where((r) => !broken.contains(r))
          .toList();
      for (final roll in activeStreakRolls) {
        final status = rolls[roll.toString()];
        final isAbsent = status != null &&
            (status == 'Absent' || status == 'Leave' || status == false);
        if (isAbsent) {
          streaks[roll] = streaks[roll]! + 1;
        } else {
          broken.add(roll);
        }
      }
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
    final key = _attendanceDocKey(className, date);
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
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Error in cascade delete student notifications: $e', e, stack);
    }
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
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Error in cascade delete student leave notifications: $e', e, stack);
    }
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

    try {
      final studentDoc = await _studentsRef.doc(studentId).get();
      if (studentDoc.exists && studentDoc.data() != null) {
        final data = studentDoc.data()!;
        final className = data['className'] as String? ?? '';
        final studentName = data['name'] as String? ?? '';
        if (className.isNotEmpty && studentName.isNotEmpty) {
          await NotificationService().addGuardianCorrectionSubmitted(
            className: className,
            studentName: studentName,
          );
        }
      }
    } catch (e, stack) {
      AppLogger.e('StudentService', 'Failed to send guardian correction notification: $e', e, stack);
    }
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
