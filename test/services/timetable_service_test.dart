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
    test('addTeacher works and does not throw exception even if HTTP Auth signup fails', () async {
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
      expect(allowedUserDoc.data()?['role'], 'teacher');
    });
  });
}
