import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/auth/login_screen.dart';
import 'package:school_app/features/dashboards/home_screen.dart';
import 'package:school_app/features/dashboards/coordinator_dashboard.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/services/auth_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/base_firestore_service.dart';
import 'package:school_app/services/notification_service.dart';
import 'package:school_app/services/staff_task_service.dart';
import 'package:school_app/services/meeting_service.dart';
import 'package:school_app/services/substitution_history_service.dart';
import 'package:school_app/services/todo_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';
import 'package:school_app/shared/widgets/email_text_form_field.dart';

class MockAuthService extends Mock implements AuthService {}
class MockTimetableService extends Mock implements TimetableService {}
class MockUserCredential extends Mock implements UserCredential {}
class MockUser extends Mock implements User {}
class MockNotificationService extends Mock implements NotificationService {}
class MockStaffTaskService extends Mock implements StaffTaskService {}
class MockMeetingService extends Mock implements MeetingService {}
class MockSubstitutionHistoryService extends Mock implements SubstitutionHistoryService {}
class MockTodoService extends Mock implements TodoService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Teacher(
      id: '',
      name: '',
      subject: '',
      email: '',
      isClassTeacher: false,
    ));
  });

  late MockAuthService mockAuthService;
  late MockTimetableService mockTimetableService;
  late MockUserCredential mockUserCredential;
  late MockUser mockUser;
  late MockNotificationService mockNotificationService;
  late MockStaffTaskService mockStaffTaskService;
  late MockMeetingService mockMeetingService;
  late MockSubstitutionHistoryService mockSubstitutionHistoryService;
  late MockTodoService mockTodoService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BaseFirestoreService.currentSchoolId = 'test_school';
    mockAuthService = MockAuthService();
    mockTimetableService = MockTimetableService();
    mockUserCredential = MockUserCredential();
    mockUser = MockUser();
    mockNotificationService = MockNotificationService();
    mockStaffTaskService = MockStaffTaskService();
    mockMeetingService = MockMeetingService();
    mockSubstitutionHistoryService = MockSubstitutionHistoryService();
    mockTodoService = MockTodoService();

    when(() => mockUserCredential.user).thenReturn(mockUser);
    when(() => mockUser.email).thenReturn('teacher@school.test');
    when(() => mockAuthService.currentFirebaseUser).thenReturn(mockUser);
    when(() => mockAuthService.saveSession(
          email: any(named: 'email'),
          role: any(named: 'role'),
          teacherId: any(named: 'teacherId'),
          studentClass: any(named: 'studentClass'),
          studentRoll: any(named: 'studentRoll'),
          studentSection: any(named: 'studentSection'),
          studentAdmissionId: any(named: 'studentAdmissionId'),
          assignedClasses: any(named: 'assignedClasses'),
          name: any(named: 'name'),
          schoolId: any(named: 'schoolId'),
          studentLinks: any(named: 'studentLinks'),
        )).thenAnswer((_) async {});

    when(() => mockNotificationService.streamFor(
          role: any(named: 'role'),
          teacherId: any(named: 'teacherId'),
        )).thenAnswer((_) => Stream.value([]));

    when(() => mockStaffTaskService.streamPendingCountForTeacher(any()))
        .thenAnswer((_) => Stream.value(0));

    when(() => mockMeetingService.streamPendingTaskCountForTeacher(any()))
        .thenAnswer((_) => Stream.value(0));

    when(() => mockTimetableService.syncTeacherClassIds(any()))
        .thenAnswer((_) async {});

    when(() => mockTimetableService.streamPendingStudentLeaveCount(
          studentClass: any(named: 'studentClass'),
          studentSection: any(named: 'studentSection'),
        )).thenAnswer((_) => Stream.value(0));

    when(() => mockSubstitutionHistoryService.streamSubstitutions(any()))
        .thenAnswer((_) => Stream.empty());

    when(() => mockTodoService.streamTodayReminders(any()))
        .thenAnswer((_) => Stream.empty());

    AuthService.mockInstance = mockAuthService;
    TimetableService.mockInstance = mockTimetableService;
    NotificationService.mockInstance = mockNotificationService;
    StaffTaskService.mockInstance = mockStaffTaskService;
    MeetingService.mockInstance = mockMeetingService;
    SubstitutionHistoryService.mockInstance = mockSubstitutionHistoryService;
    TodoService.mockInstance = mockTodoService;
  });

  tearDown(() {
    BaseFirestoreService.currentSchoolId = null;
    AuthService.mockInstance = null;
    TimetableService.mockInstance = null;
    NotificationService.mockInstance = null;
    StaffTaskService.mockInstance = null;
    MeetingService.mockInstance = null;
    SubstitutionHistoryService.mockInstance = null;
    TodoService.mockInstance = null;
  });

  Widget createLoginScreen() {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  group('E2E Login Flow Integration Tests', () {
    final teacher = Teacher(
      id: 'teacher_123',
      name: 'Ms. Nair',
      subject: 'Math',
      email: 'teacher@school.test',
      isClassTeacher: true,
      classTeacherOf: 'Class 9-A',
    );

    testWidgets('Login with teacher credentials routes to teacher HomeScreen', (WidgetTester tester) async {
      // Mock login to succeed and return MockUserCredential
      when(() => mockAuthService.signInWithEmail('teacher@school.test', 'password123'))
          .thenAnswer((_) async => mockUserCredential);

      when(() => mockAuthService.getSession()).thenAnswer((_) async => {
            'email': 'teacher@school.test',
            'role': 'teacher',
            'schoolId': 'test_school',
            'teacherId': 'teacher_123',
          });

      // Mock allowed user verification
      when(() => mockTimetableService.getAllowedUserDoc('teacher@school.test'))
          .thenAnswer((_) async => {
                'role': 'teacher',
                'status': 'active',
                'schoolId': 'test_school',
                'teacherId': 'teacher_123',
              });

      // Mock teacher fetch
      when(() => mockTimetableService.getTeacherById(id: 'teacher_123'))
          .thenAnswer((_) async => teacher);

      // Mock settings fetch
      when(() => mockTimetableService.getSettings())
          .thenAnswer((_) async => {'classes': ['Class 9-A']});

      // Stub copy check service
      // As teacher morning summary card runs during home screen initialization, we stub other teacher services
      // (StudentService, BirthdayService, CopyCheckService, etc.) to keep them happy.
      // But they are already covered if we mock the singleton services. Since mock instances are overridden,
      // the widgets won't crash if they get empty answers.

      await tester.pumpWidget(createLoginScreen());
      await tester.pumpAndSettle();

      final Finder passwordFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.prefixIcon as Icon?)?.icon == Icons.lock_outline,
      );

      // Enter email and password
      await tester.enterText(find.byType(EmailTextFormField), 'teacher@school.test');
      await tester.enterText(passwordFieldFinder, 'password123');
      await tester.pump();

      // Tap Sign In
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Verify redirection to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Ms. Nair'), findsOneWidget);
    });

    testWidgets('Login with coordinator credentials routes to CoordinatorDashboard', (WidgetTester tester) async {
      when(() => mockAuthService.signInWithEmail('coord@school.test', 'password123'))
          .thenAnswer((_) async => mockUserCredential);

      when(() => mockAuthService.getSession()).thenAnswer((_) async => {
            'email': 'coord@school.test',
            'role': 'coordinator',
            'schoolId': 'test_school',
          });

      when(() => mockTimetableService.getAllowedUserDoc('coord@school.test'))
          .thenAnswer((_) async => {
                'role': 'coordinator',
                'status': 'active',
                'schoolId': 'test_school',
              });

      when(() => mockTimetableService.getSettings())
          .thenAnswer((_) async => {'classes': ['Class 9-A', 'Class 9-B']});

      await tester.pumpWidget(createLoginScreen());
      await tester.pumpAndSettle();

      final Finder passwordFieldFinder = find.byWidgetPredicate(
        (w) => w is TextField && (w.decoration?.prefixIcon as Icon?)?.icon == Icons.lock_outline,
      );

      await tester.enterText(find.byType(EmailTextFormField), 'coord@school.test');
      await tester.enterText(passwordFieldFinder, 'password123');
      await tester.pump();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.byType(CoordinatorDashboard), findsOneWidget);
    });
  });
}
