import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/student.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/repositories/student_repository_fake.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/promotion_service.dart';
import 'package:school_app/services/timetable_service.dart';

class FakeTimetableService implements TimetableService {
  final List<Teacher> teachers;
  FakeTimetableService(this.teachers);

  @override
  Future<List<Teacher>> getTeachers({String? schoolId, bool refresh = false}) async {
    return teachers;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStudentRepository studentRepo;
  late StudentService studentService;

  setUp(() {
    BaseFirestoreService.currentSchoolId = 'test_school';
    studentRepo = FakeStudentRepository();
    studentService = StudentService(studentRepo);
  });

  tearDown(() {
    studentRepo.clear();
    BaseFirestoreService.currentSchoolId = null;
  });

  test('successfully promotes a batch of students and updates repository state', () async {
    // 1. Setup Class 6 students
    const s1 = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 6',
      section: 'A',
      admissionId: 'AD-001',
      guardianEmail: 'alice@parent.com',
    );
    const s2 = Student(
      roll: 2,
      name: 'Bob',
      className: 'Class 6',
      section: 'A',
      admissionId: 'AD-002',
    );
    studentRepo.seed([s1, s2]);

    final timetableService = FakeTimetableService([
      const Teacher(
        id: 'teacher1',
        name: 'Mr. Smith',
        subject: 'Math',
        email: 'smith@school.com',
        isClassTeacher: true,
        classTeacherOf: 'Class 7',
        section: 'A',
      ),
    ]);

    final promotionService = PromotionService(
      studentService: studentService,
      timetableService: timetableService,
    );

    // 2. Promote from Class 6 Section A to Class 7 Section A
    final result = await promotionService.promoteStudents(
      students: [s1, s2],
      targetClass: 'Class 7',
      targetSection: 'A',
    );

    // 3. Verify promotion result
    expect(result.promoted, 2);
    expect(result.skipped, isEmpty);

    // 4. Verify repository state for old students (marked promoted)
    final oldS1 = await studentRepo.fetchByRoll('Class 6', 'A', 1);
    final oldS2 = await studentRepo.fetchByRoll('Class 6', 'A', 2);
    expect(oldS1, isNotNull);
    expect(oldS1!.promoted, isTrue);
    expect(oldS2, isNotNull);
    expect(oldS2!.promoted, isTrue);

    // 5. Verify repository state for promoted (new) students
    final newS1 = await studentRepo.fetchByRoll('Class 7', 'A', 1);
    final newS2 = await studentRepo.fetchByRoll('Class 7', 'A', 2);

    expect(newS1, isNotNull);
    expect(newS1!.promoted, isFalse);
    expect(newS1.admissionId, 'AD-001');
    expect(newS1.name, 'Alice');
    expect(newS1.teacherId, 'teacher1'); // assigned to Mr. Smith

    expect(newS2, isNotNull);
    expect(newS2!.promoted, isFalse);
    expect(newS2.admissionId, 'AD-002');
    expect(newS2.name, 'Bob');
    expect(newS2.teacherId, 'teacher1');
  });

  test('skips students that are already promoted (matching admission ID)', () async {
    const s1 = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 6',
      section: 'A',
      admissionId: 'AD-001',
    );
    // Alice is already in Class 7
    const targetAlice = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 7',
      section: 'A',
      admissionId: 'AD-001',
    );
    studentRepo.seed([s1, targetAlice]);

    final timetableService = FakeTimetableService([]);
    final promotionService = PromotionService(
      studentService: studentService,
      timetableService: timetableService,
    );

    final result = await promotionService.promoteStudents(
      students: [s1],
      targetClass: 'Class 7',
      targetSection: 'A',
    );

    expect(result.promoted, 0);
    expect(result.skipped, hasLength(1));
    expect(result.skipped.first, contains('already in Class 7 (by admission ID)'));

    // Old Alice shouldn't be touched/marked promoted in this path since she was skipped
    final oldAlice = await studentRepo.fetchByRoll('Class 6', 'A', 1);
    expect(oldAlice!.promoted, isFalse);
  });

  test('skips promotion on roll number collision with different student', () async {
    const s1 = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 6',
      section: 'A',
      admissionId: 'AD-001',
    );
    // Someone else has Roll 1 in Class 7
    const otherStudent = Student(
      roll: 1,
      name: 'Charlie',
      className: 'Class 7',
      section: 'A',
      admissionId: 'AD-999',
    );
    studentRepo.seed([s1, otherStudent]);

    final timetableService = FakeTimetableService([]);
    final promotionService = PromotionService(
      studentService: studentService,
      timetableService: timetableService,
    );

    final result = await promotionService.promoteStudents(
      students: [s1],
      targetClass: 'Class 7',
      targetSection: 'A',
    );

    expect(result.promoted, 0);
    expect(result.skipped, hasLength(1));
    expect(result.skipped.first, contains('roll number 1 already exists in Class 7'));

    // Verify Class 7 Roll 1 is still Charlie
    final targetRoll1 = await studentRepo.fetchByRoll('Class 7', 'A', 1);
    expect(targetRoll1!.name, 'Charlie');
    expect(targetRoll1.admissionId, 'AD-999');

    // Verify old Alice is not promoted
    final oldAlice = await studentRepo.fetchByRoll('Class 6', 'A', 1);
    expect(oldAlice!.promoted, isFalse);
  });
}
