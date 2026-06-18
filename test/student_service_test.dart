// ignore_for_file: lines_longer_than_80_chars

/// Unit tests for [StudentService] using [FakeStudentRepository].
///
/// No Firebase initialisation needed — all Firestore calls are intercepted
/// by the in-memory fake.  Only methods that delegate to the repository are
/// tested here; attendance methods (which still touch Firestore directly)
/// are covered by integration tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/student.dart';
import 'package:school_app/repositories/student_repository_fake.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/student_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Build a minimal [Student] for test use.
Student _student({
  required int roll,
  String name = 'Test Student',
  String className = 'Class 6',
  String section = '',
  String? teacherId,
  String? guardianEmail,
}) =>
    Student(
      roll:          roll,
      name:          name,
      className:     className,
      section:       section,
      teacherId:     teacherId,
      guardianEmail: guardianEmail,
    );

// ── Test suite ────────────────────────────────────────────────────────────────

void main() {
  late FakeStudentRepository repo;
  late StudentService service;

  setUp(() {
    // Pre-set the school ID so AuthService.currentSchoolId never falls through
    // to FirebaseAuth.instance (which is unavailable in unit tests).
    BaseFirestoreService.currentSchoolId = 'test_school';
    repo    = FakeStudentRepository();
    service = StudentService(repo);
  });

  tearDown(() {
    repo.clear();
    BaseFirestoreService.currentSchoolId = null; // reset
  });

  // ── 1. addStudent — success ──────────────────────────────────────────────────

  test('addStudent returns null and persists the student on success', () async {
    final alice = _student(roll: 1, name: 'Alice', className: 'Class 6');

    final error = await service.addStudent(student: alice);

    expect(error, isNull,
        reason: 'No error should be returned for a new student');

    final fetched =
        await service.getStudentByRoll('Class 6', 1);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Alice');
    expect(fetched.roll, 1);
  });

  // ── 2. addStudent — duplicate roll ──────────────────────────────────────────

  test('addStudent returns error string and does not overwrite on duplicate roll',
      () async {
    final alice = _student(roll: 5, name: 'Alice', className: 'Class 7');
    await service.addStudent(student: alice);

    final bob   = _student(roll: 5, name: 'Bob', className: 'Class 7');
    final error = await service.addStudent(student: bob);

    expect(error, isNotNull,
        reason: 'Duplicate roll must produce an error message');
    expect(error, contains('5'),
        reason: 'Error message should mention the roll number');
    expect(error!.toLowerCase(), contains('already exists'));

    // Original student must be unchanged.
    final fetched =
        await service.getStudentByRoll('Class 7', 5);
    expect(fetched?.name, 'Alice',
        reason: 'Bob must not have replaced Alice');
  });

  // ── 3. getStudentsByClass — filtering and ordering ──────────────────────────

  test('getStudentsByClass returns only matching class, sorted by roll',
      () async {
    repo.seed([
      _student(roll: 3, name: 'Charlie', className: 'Class 8'),
      _student(roll: 1, name: 'Alice',   className: 'Class 8'),
      _student(roll: 2, name: 'Bob',     className: 'Class 9'), // different class
    ]);

    final result = await service.getStudentsByClass(className: 'Class 8');

    expect(result.length, 2,
        reason: 'Should return only Class 8 students');
    expect(result.map((s) => s.roll), orderedEquals([1, 3]),
        reason: 'Results must be sorted by roll ascending');
    expect(result.map((s) => s.name), orderedEquals(['Alice', 'Charlie']));
  });

  // ── 4. getStudentsByClass — teacherId filter ─────────────────────────────────

  test('getStudentsByClass with teacherId returns only that teacher\'s students',
      () async {
    repo.seed([
      _student(roll: 1, name: 'Alice', className: 'Class 6', teacherId: 'T1'),
      _student(roll: 2, name: 'Bob',   className: 'Class 6', teacherId: 'T2'),
      _student(roll: 3, name: 'Carol', className: 'Class 6', teacherId: 'T1'),
    ]);

    final result = await service.getStudentsByClass(
        className: 'Class 6', teacherId: 'T1');

    expect(result.length, 2);
    expect(result.every((s) => s.teacherId == 'T1'), isTrue);
    expect(result.map((s) => s.name), containsAll(['Alice', 'Carol']));
  });

  // ── 5. getStudentByRoll — found / not found ──────────────────────────────────

  test('getStudentByRoll returns the correct student when it exists', () async {
    repo.seed([
      _student(roll: 10, name: 'Diana', className: 'Class 5', section: 'A'),
    ]);

    final found = await service.getStudentByRoll('Class 5', 10,
        section: 'A');
    expect(found, isNotNull);
    expect(found!.name, 'Diana');
  });

  test('getStudentByRoll returns null for a non-existent roll', () async {
    final result = await service.getStudentByRoll('Class 5', 99);
    expect(result, isNull);
  });

  // ── 6. updateStudent — mutation persists ─────────────────────────────────────

  test('updateStudent overwrites existing record', () async {
    repo.seed([_student(roll: 7, name: 'Eve', className: 'Class 6')]);

    final updated = _student(roll: 7, name: 'Eve Nguyen', className: 'Class 6');
    await service.updateStudent(updated: updated);

    final fetched = await service.getStudentByRoll('Class 6', 7);
    expect(fetched?.name, 'Eve Nguyen');
  });

  // ── 7. addStudentRemark — validation ─────────────────────────────────────────

  test('addStudentRemark throws ArgumentError for empty remark', () async {
    repo.seed([_student(roll: 1, className: 'Class 6')]);

    expect(
      () => service.addStudentRemark(
          'Class 6', 1, 'teacher@school.com', 'teacher', ''),
      throwsArgumentError,
    );
  });

  test('addStudentRemark throws ArgumentError when remark exceeds 200 chars',
      () async {
    repo.seed([_student(roll: 1, className: 'Class 6')]);
    final longRemark = 'x' * 201;

    expect(
      () => service.addStudentRemark(
          'Class 6', 1, 'teacher@school.com', 'teacher', longRemark),
      throwsArgumentError,
    );
  });

  // ── 8. addStudentRemark + getStudentRemarks — round-trip ────────────────────

  test('valid remark is persisted and retrievable via getStudentRemarks',
      () async {
    repo.seed([_student(roll: 3, className: 'Class 7')]);

    await service.addStudentRemark(
        'Class 7', 3, 'teacher@school.com', 'teacher', 'Late arrival');

    final remarks =
        await service.getStudentRemarks('Class 7', 3);
    expect(remarks.length, 1);
    expect(remarks.first.remark, 'Late arrival');
    expect(remarks.first.createdBy, 'teacher@school.com');
  });

  // ── 9. watchStudentsByClass — stream emits initial state ────────────────────

  test('watchStudentsByClass stream emits current students', () async {
    repo.seed([
      _student(roll: 1, name: 'Frank', className: 'Class 6'),
      _student(roll: 2, name: 'Grace', className: 'Class 6'),
    ]);

    final stream = service.watchStudentsByClass(className: 'Class 6');
    final first  = await stream.first;

    expect(first.length, 2);
    expect(first.map((s) => s.name), containsAll(['Frank', 'Grace']));
  });

  // ── 10. setGuardianEmail — patch only email field ────────────────────────────

  test('setGuardianEmail updates only the guardianEmail field', () async {
    repo.seed([_student(roll: 4, name: 'Hana', className: 'Class 8')]);

    await service.setGuardianEmail('Class 8', 4, 'parent@gmail.com');

    final s = await service.getStudentByRoll('Class 8', 4);
    expect(s?.guardianEmail, 'parent@gmail.com');
    expect(s?.name, 'Hana', reason: 'Other fields must remain unchanged');
  });

  // ── 11. markStudentsDeletionPending — flags selected students ────────────────

  test('markStudentsDeletionPending flags only the named students', () async {
    repo.seed([
      _student(roll: 1, name: 'Ivy',  className: 'Class 8', section: 'A'),
      _student(roll: 2, name: 'Jack', className: 'Class 8', section: 'A'),
    ]);

    await service.markStudentsDeletionPending([
      {'roll': 1, 'className': 'Class 8', 'section': 'A'},
    ], true);

    // The flag is persisted on the record (read straight from the repository,
    // which is not subject to the service-level deletion filter).
    final ivyRaw  = await repo.fetchByRoll('Class 8', 'A', 1);
    final jackRaw = await repo.fetchByRoll('Class 8', 'A', 2);
    expect(ivyRaw?.deletionPending, isTrue,
        reason: 'Requested student must be flagged for deletion');
    expect(jackRaw?.deletionPending, isFalse,
        reason: 'Untouched student must stay active');

    // …and a flagged student must be invisible to every role-based read path,
    // while the untouched student stays visible.
    final ivy  = await service.getStudentByRoll('Class 8', 1, section: 'A');
    final jack = await service.getStudentByRoll('Class 8', 2, section: 'A');
    expect(ivy, isNull,
        reason: 'A student marked for deletion must not be viewable');
    expect(jack?.deletionPending, isFalse,
        reason: 'Untouched student must remain viewable');

    final roster =
        await service.getStudentsByClass(className: 'Class 8', section: 'A');
    expect(roster.map((s) => s.name), ['Jack'],
        reason: 'Class roster must exclude the student marked for deletion');
  });

  // ── 12. rejectDeletionRequest — reactivates the students ─────────────────────

  test('rejectDeletionRequest clears the deletionPending flag', () async {
    repo.seed([
      _student(roll: 1, name: 'Ivy', className: 'Class 8', section: 'A'),
    ]);

    final students = [
      {'roll': 1, 'name': 'Ivy', 'className': 'Class 8', 'section': 'A'},
    ];
    await service.submitDeletionRequest(
      teacherId: 't1', teacherName: 'T', teacherEmail: 't@x.com',
      students: students,
    );
    await service.markStudentsDeletionPending(students, true);

    final pending = await service.getPendingDeletionRequests();
    expect(pending, hasLength(1));

    await service.rejectDeletionRequest(pending.first['id'] as String);

    final ivy = await service.getStudentByRoll('Class 8', 1, section: 'A');
    expect(ivy?.deletionPending, isFalse,
        reason: 'Rejecting the request must reactivate the student');
  });

  // ── 12b. approveDeletionRequest — deletes the student ───────────────────────

  test('approveDeletionRequest deletes the student and updates status', () async {
    repo.seed([
      _student(roll: 1, name: 'Ivy', className: 'Class 8', section: 'A'),
    ]);

    final students = [
      {'roll': 1, 'name': 'Ivy', 'className': 'Class 8', 'section': 'A'},
    ];
    await service.submitDeletionRequest(
      teacherId: 't1', teacherName: 'T', teacherEmail: 't@x.com',
      students: students,
    );
    await service.markStudentsDeletionPending(students, true);

    final pending = await service.getPendingDeletionRequests();
    expect(pending, hasLength(1));

    await service.approveDeletionRequest(pending.first['id'] as String);

    final ivy = await service.getStudentByRoll('Class 8', 1, section: 'A');
    expect(ivy, isNull,
        reason: 'Approving the request must delete the student record');
  });

  // ── 13. HTML stripping & phone normalization ─────────────────────────────

  test('addStudent and updateStudent strip HTML tags and normalize phone numbers', () async {
    const student = Student(
      roll: 2,
      name: '<b>Alice</b>',
      className: 'Class 6',
      section: 'A',
      fatherName: '<p>John</p>',
      motherName: '<span>Jane</span>',
      phone: '9876543210',
      parentPhone: '09876543211',
    );

    final error = await service.addStudent(student: student);
    expect(error, isNull);

    final fetched = await service.getStudentByRoll('Class 6', 2, section: 'A');
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Alice');
    expect(fetched.fatherName, 'John');
    expect(fetched.motherName, 'Jane');
    expect(fetched.phone, '+919876543210');
    expect(fetched.parentPhone, '+919876543211');
  });

  // ── 14. updateStudent — collision checks on key changes ───────────────────

  test('updateStudent returns error string if roll collision occurs on change', () async {
    final student1 = _student(roll: 1, name: 'Alice', className: 'Class 6');
    final student2 = _student(roll: 2, name: 'Bob', className: 'Class 6');
    await service.addStudent(student: student1);
    await service.addStudent(student: student2);

    final bobOriginal = await service.getStudentByRoll('Class 6', 2);
    expect(bobOriginal, isNotNull);

    // Try to update Bob's roll to 1 (collision)
    final bobWithCollidingRoll = bobOriginal!.copyWith(roll: 1);
    final error = await service.updateStudent(updated: bobWithCollidingRoll);
    expect(error, isNotNull);
    expect(error!.toLowerCase(), contains('already exists'));

    // Verify Bob's record wasn't updated to roll 1
    final unchangedBob = await repo.fetchByRoll('Class 6', '', 2);
    expect(unchangedBob?.name, 'Bob');
  });

  // ── 15. updateStudent — old document cleanup on key changes ───────────────

  test('updateStudent deletes old document and creates new document when key identifying fields change', () async {
    final student = _student(roll: 10, name: 'Charlie', className: 'Class 6', section: 'A');
    final err = await service.addStudent(student: student);
    expect(err, isNull);

    final originalDocId = Student.buildDocId(10, 'Class 6', 'A');
    final oldDoc = await repo.fetchById(originalDocId);
    expect(oldDoc, isNotNull);

    // Update class and section
    final updatedStudent = oldDoc!.copyWith(className: 'Class 7', section: 'B');
    final updateErr = await service.updateStudent(updated: updatedStudent);
    expect(updateErr, isNull);

    // Verify old document is deleted
    final deletedDoc = await repo.fetchById(originalDocId);
    expect(deletedDoc, isNull);

    // Verify new document exists
    final newDocId = Student.buildDocId(10, 'Class 7', 'B');
    final newDoc = await repo.fetchById(newDocId);
    expect(newDoc, isNotNull);
    expect(newDoc!.className, 'Class 7');
    expect(newDoc.section, 'B');
    expect(newDoc.name, 'Charlie');
  });

  // ── 16. Student.fromJson — graceful handling ──────────────────────────────

  test('Student.fromJson handles malformed JSON gracefully', () {
    final malformed = <String, dynamic>{
      'roll': 'not-an-int',
      'name': 12345, // not a string
      'className': null,
      'feeAmount': 'invalid-double',
      'birthMonth': 'invalid-month',
    };

    final student = Student.fromJson(malformed);
    expect(student, isNotNull);
    expect(student.roll, 0);
    expect(student.name, 'Corrupted Profile');
    expect(student.className, '');
  });

  // ── 17. removeStudent — cascade delete on fake repository ──────────────────

  test('removeStudent deletes student from fake repository', () async {
    final alice = _student(roll: 1, name: 'Alice', className: 'Class 6');
    await service.addStudent(student: alice);

    var fetched = await service.getStudentByRoll('Class 6', 1);
    expect(fetched, isNotNull);

    await service.removeStudent(1, 'Class 6');

    fetched = await service.getStudentByRoll('Class 6', 1);
    expect(fetched, isNull);
  });

  // ── 18. updateStudent — admissionId duplicate guard (#40) ─────────────────

  test('updateStudent rejects duplicate admissionId collision (#40)', () async {
    final alice = _student(roll: 1, name: 'Alice', className: 'Class 6')
        .copyWith(admissionId: 'ADM-001');
    final bob   = _student(roll: 2, name: 'Bob', className: 'Class 6')
        .copyWith(admissionId: 'ADM-002');
    await service.addStudent(student: alice);
    await service.addStudent(student: bob);

    // Try to change Bob's admissionId to Alice's
    final aliceDoc = await repo.fetchByRoll('Class 6', '', 1);
    final bobDoc   = await repo.fetchByRoll('Class 6', '', 2);
    expect(aliceDoc, isNotNull);
    expect(bobDoc, isNotNull);

    final collidingBob = bobDoc!.copyWith(admissionId: 'ADM-001');
    final error = await service.updateStudent(updated: collidingBob);

    expect(error, isNotNull,
        reason: 'updateStudent must reject a duplicate admissionId');
    expect(error!.toLowerCase(), contains('already assigned'),
        reason: 'Error message must explain the conflict');

    // Bob's admissionId must remain ADM-002
    final unchangedBob = await repo.fetchByRoll('Class 6', '', 2);
    expect(unchangedBob?.admissionId, 'ADM-002');
  });

  test('updateStudent allows admissionId update when no conflict exists (#40)', () async {
    final dave = _student(roll: 3, name: 'Dave', className: 'Class 6')
        .copyWith(admissionId: 'ADM-003');
    await service.addStudent(student: dave);

    final daveDoc = await repo.fetchByRoll('Class 6', '', 3);
    expect(daveDoc, isNotNull);

    // Change to a fresh admissionId — should succeed
    final updatedDave = daveDoc!.copyWith(admissionId: 'ADM-999');
    final error = await service.updateStudent(updated: updatedDave);
    expect(error, isNull, reason: 'Non-colliding admissionId change must succeed');

    final newDave = await repo.fetchByRoll('Class 6', '', 3);
    expect(newDave?.admissionId, 'ADM-999');
  });

  test('updateStudent ignores admissionId check when unchanged (#40)', () async {
    // When the admissionId hasn't changed, the guard must not be triggered
    // (avoids an unnecessary DB round-trip).
    final eve = _student(roll: 4, name: 'Eve', className: 'Class 6')
        .copyWith(admissionId: 'ADM-004');
    await service.addStudent(student: eve);

    final eveDoc = await repo.fetchByRoll('Class 6', '', 4);
    expect(eveDoc, isNotNull);

    // Update only the name, not admissionId
    final updatedEve = eveDoc!.copyWith(name: 'Eve Updated');
    final error = await service.updateStudent(updated: updatedEve);
    expect(error, isNull, reason: 'Unchanged admissionId must not trigger duplicate guard');

    final newEve = await repo.fetchByRoll('Class 6', '', 4);
    expect(newEve?.name, 'Eve Updated');
    expect(newEve?.admissionId, 'ADM-004');
  });

  // ── 19. Student.buildDocId normalisation ───────────────────────────────────

  test('Student.buildDocId normalizes className and section case and spacing', () {
    final docId1 = Student.buildDocId(12, 'class 6', 'a');
    expect(docId1, 'Class_6_A_12');

    final docId2 = Student.buildDocId(5, '   cLaSs    9-b ', '  c  ');
    expect(docId2, 'Class_9-B_C_5');

    final docId3 = Student.buildDocId(20, 'Class 10', '');
    expect(docId3, 'Class_10_20');

    final docId4 = Student.buildDocId(1, '6-B', 'B');
    expect(docId4, '6-B_1');

    final docId5 = Student.buildDocId(1, '6_B', 'B');
    expect(docId5, '6_b_1');
  });

  // ── 20. Student.buildAttendanceKey normalisation ───────────────────────────

  test('Student.buildAttendanceKey correctly handles className and section formatting without duplication', () {
    expect(Student.buildAttendanceKey('6-A', 'A'), '6-A');
    expect(Student.buildAttendanceKey('6A', 'A'), '6A');
    expect(Student.buildAttendanceKey('6 A', 'A'), '6 A');
    expect(Student.buildAttendanceKey('6_A', 'A'), '6_A');
    expect(Student.buildAttendanceKey('6', 'A'), '6 A');
    expect(Student.buildAttendanceKey('LKG', 'G'), 'LKG G');
    expect(Student.buildAttendanceKey('Class A', 'A'), 'Class A');
    expect(Student.buildAttendanceKey('Class', 'A'), 'Class A');
    expect(Student.buildAttendanceKey('Class 6', ''), 'Class 6');
  });
}


