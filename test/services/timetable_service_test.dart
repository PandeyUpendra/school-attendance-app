import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/timetable_service.dart';

void main() {
  late FakeFirebaseFirestore fakeDb;
  late TimetableService service;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    fakeDb = FakeFirebaseFirestore();
    BaseFirestoreService.mockDb = fakeDb;
    BaseFirestoreService.currentSchoolId = 'test_school';
    service = TimetableService();
  });

  tearDown(() {
    BaseFirestoreService.mockDb = null;
    BaseFirestoreService.currentSchoolId = null;
  });

  group('TimetableService addTeacher Tests', () {
    test('addTeacher works and does not throw exception even if HTTP Auth signup fails (Subject Teacher)', () async {
      final teacher = Teacher(
        id: 'teacher_test_id',
        name: 'Jane Doe',
        subject: 'Maths',
        email: 'jane.doe@school.test',
        isClassTeacher: false,
        schoolId: 'test_school',
      );

      // This should complete successfully and not throw any exception,
      // even though the HTTP signup call fails (since there is no internet in the test sandbox).
      await service.addTeacher('test_school', teacher);

      // Verify teacher was successfully written to Firestore
      final teacherDoc = await fakeDb
          .collection('schools')
          .doc('test_school')
          .collection('teachers')
          .doc('teacher_test_id')
          .get();
      expect(teacherDoc.exists, isTrue);
      expect(teacherDoc.data()?['name'], 'Jane Doe');

      // Verify allowed_users document was successfully written to Firestore
      final allowedUserDoc = await fakeDb
          .collection('allowed_users')
          .doc('jane.doe@school.test')
          .get();
      expect(allowedUserDoc.exists, isTrue);
      expect(allowedUserDoc.data()?['name'], 'Jane Doe');
      expect(allowedUserDoc.data()?['role'], 'subjectTeacher');
    });

    test('addTeacher writes role "teacher" for a Class Teacher', () async {
      final teacher = Teacher(
        id: 'class_teacher_id',
        name: 'John Smith',
        subject: 'Science',
        email: 'john.smith@school.test',
        isClassTeacher: true,
        schoolId: 'test_school',
      );

      await service.addTeacher('test_school', teacher);

      final allowedUserDoc = await fakeDb
          .collection('allowed_users')
          .doc('john.smith@school.test')
          .get();
      expect(allowedUserDoc.exists, isTrue);
      expect(allowedUserDoc.data()?['role'], 'teacher');
    });

    test('provisionTeacherLoginAccess handles transition between teacher and subjectTeacher without throwing', () async {
      final teacher = Teacher(
        id: 'class_teacher_id',
        name: 'John Smith',
        subject: 'Science',
        email: 'john.smith@school.test',
        isClassTeacher: true, // target role: teacher
        schoolId: 'test_school',
      );

      // Pre-fill as subjectTeacher
      await fakeDb.collection('allowed_users').doc('john.smith@school.test').set({
        'role': 'subjectTeacher',
        'email': 'john.smith@school.test',
        'name': 'John Smith',
        'teacherId': 'class_teacher_id',
        'schoolId': 'test_school',
        'status': 'active',
      });

      // This should succeed because switching roles between teacher and subjectTeacher is allowed
      await service.provisionTeacherLoginAccess(teacher);

      final allowedUserDoc = await fakeDb
          .collection('allowed_users')
          .doc('john.smith@school.test')
          .get();
      expect(allowedUserDoc.exists, isTrue);
      expect(allowedUserDoc.data()?['role'], 'teacher');
    });
  });
}
