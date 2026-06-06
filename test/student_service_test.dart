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
    repo    = FakeStudentRepository();
    service = StudentService(repo);
  });

  tearDown(() => repo.clear());

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
}
