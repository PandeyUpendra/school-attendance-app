import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/attendance/attendance_screen.dart';
import 'package:school_app/models/student.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/offline_queue_service.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/auth_service.dart';
import 'package:school_app/services/consent_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';

class MockStudentService extends Mock implements StudentService {}
class MockTimetableService extends Mock implements TimetableService {}
class MockAuthService extends Mock implements AuthService {}
class MockUser extends Mock implements fb.User {}
class MockConsentService extends Mock implements ConsentService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStudentService mockStudentService;
  late MockTimetableService mockTimetableService;
  late MockAuthService mockAuthService;
  late MockUser mockUser;
  late MockConsentService mockConsentService;
  late List<String> mockConnectivityResult;

  const MethodChannel connectivityChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BaseFirestoreService.currentSchoolId = 'test_school';
    mockStudentService = MockStudentService();
    mockTimetableService = MockTimetableService();
    mockAuthService = MockAuthService();
    mockUser = MockUser();
    mockConsentService = MockConsentService();
    mockConnectivityResult = ['wifi']; // default online

    StudentService.mockInstance = mockStudentService;
    TimetableService.mockInstance = mockTimetableService;
    AuthService.mockInstance = mockAuthService;
    ConsentService.mockInstance = mockConsentService;

    when(() => mockAuthService.currentFirebaseUser).thenReturn(mockUser);
    when(() => mockAuthService.getSession()).thenAnswer((_) async => {
          'email': 'teacher@school.test',
          'role': 'teacher',
          'schoolId': 'test_school',
          'teacherId': 'teacher_123',
        });

    when(() => mockTimetableService.getTeacherById(id: any(named: 'id')))
        .thenAnswer((_) async => const Teacher(
              id: 'teacher_123',
              name: 'Ms. Nair',
              subject: 'Math',
              email: 'teacher@school.test',
              isClassTeacher: true,
              classTeacherOf: 'Class 9-A',
              section: 'A',
            ));

    when(() => mockConsentService.filterHasActiveConsent(any()))
        .thenAnswer((_) async => <String>{});

    when(() => mockStudentService.watchStudentsByClass(
          className: any(named: 'className'),
          section: any(named: 'section'),
        )).thenAnswer((_) => Stream.value(<Student>[]));

    // Stub connectivity method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (MethodCall call) async {
      if (call.method == 'check') {
        return mockConnectivityResult;
      }
      return null;
    });
  });

  tearDown(() {
    BaseFirestoreService.currentSchoolId = null;
    StudentService.mockInstance = null;
    TimetableService.mockInstance = null;
    AuthService.mockInstance = null;
    ConsentService.mockInstance = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  Widget createScreen() {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: const MaterialApp(
        home: AttendanceScreen(className: 'Class 9-A', section: 'A'),
      ),
    );
  }

  group('E2E Attendance & Offline Sync Integration Tests', () {
    final student1 = Student(
      roll: 1,
      name: 'Alice',
      className: 'Class 9-A',
      section: 'A',
      guardianEmail: 'alice@guardian.com',
    );

    final student2 = Student(
      roll: 2,
      name: 'Bob',
      className: 'Class 9-A',
      section: 'A',
      guardianEmail: 'bob@guardian.com',
    );

    testWidgets('Mark attendance online writes directly to database', (WidgetTester tester) async {
      // 1. Stub list students and leaves
      when(() => mockStudentService.getStudentsByClass(
            className: 'Class 9-A',
            section: 'A',
          )).thenAnswer((_) async => [student1, student2]);

      when(() => mockStudentService.watchStudentsByClass(
            className: 'Class 9-A',
            section: 'A',
          )).thenAnswer((_) => Stream.value([student1, student2]));

      when(() => mockTimetableService.getStudentLeaveApplications(
            studentClass: 'Class 9-A',
            status: 'approved',
          )).thenAnswer((_) async => []);

      when(() => mockStudentService.loadTodayFullSummary(classes: ['Class 9-A']))
          .thenAnswer((_) async => []);

      when(() => mockStudentService.saveAttendance(
            className: any(named: 'className'),
            attendance: any(named: 'attendance'),
          )).thenAnswer((_) async {});

      when(() => mockStudentService.loadTodayAttendance(
            className: any(named: 'className'),
          )).thenAnswer((_) async => <int, String>{});

      // Pump screen
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Tap Take Attendance for Today
      await tester.tap(find.text('Take Attendance for Today'));
      await tester.pumpAndSettle();

      // Verify students rendered
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      // Verify the check/cross status is toggleable
      // By default students are Present ( ✓ ). Tap to toggle status.
      // Wait, let's look at the AttendanceScreen toggles: Present / Absent / Leave.
      // Let's verify we can find the save button and save.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify database write was triggered
      verify(() => mockStudentService.saveAttendance(
            className: 'Class 9-A',
            attendance: any(named: 'attendance'),
          )).called(1);
    });

    testWidgets('Mark attendance offline enqueues locally, then syncs when online', (WidgetTester tester) async {
      // 1. Stub list students and leaves
      when(() => mockStudentService.getStudentsByClass(
            className: 'Class 9-A',
            section: 'A',
          )).thenAnswer((_) async => [student1, student2]);

      when(() => mockStudentService.watchStudentsByClass(
            className: 'Class 9-A',
            section: 'A',
          )).thenAnswer((_) => Stream.value([student1, student2]));

      when(() => mockTimetableService.getStudentLeaveApplications(
            studentClass: 'Class 9-A',
            status: 'approved',
          )).thenAnswer((_) async => []);

      when(() => mockStudentService.loadTodayFullSummary(classes: ['Class 9-A']))
          .thenAnswer((_) async => []);

      when(() => mockStudentService.loadTodayAttendance(
            className: any(named: 'className'),
          )).thenAnswer((_) async => <int, String>{});

      // Go offline!
      mockConnectivityResult = ['none'];

      // Pump screen
      await tester.pumpWidget(createScreen());
      await tester.pumpAndSettle();

      // Tap Take Attendance for Today
      await tester.tap(find.text('Take Attendance for Today'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify NO database write was triggered because we are offline
      verifyNever(() => mockStudentService.saveAttendance(
            className: any(named: 'className'),
            attendance: any(named: 'attendance'),
          ));

      // Verify enqueued in OfflineQueueService
      final count = await OfflineQueueService().pendingCount();
      expect(count, greaterThan(0));

      // Go back online!
      mockConnectivityResult = ['wifi'];

      // Stub saveAttendanceForDate (called during syncAll)
      when(() => mockStudentService.saveAttendanceForDate(
            className: any(named: 'className'),
            attendance: any(named: 'attendance'),
            date: any(named: 'date'),
          )).thenAnswer((_) async {});

      // Trigger sync
      await OfflineQueueService().syncAll();

      // Verify it synced to database and queue is empty
      verify(() => mockStudentService.saveAttendanceForDate(
            className: 'Class 9-A',
            attendance: any(named: 'attendance'),
            date: any(named: 'date'),
          )).called(1);

      final newCount = await OfflineQueueService().pendingCount();
      expect(newCount, 0);
    });
  });
}
