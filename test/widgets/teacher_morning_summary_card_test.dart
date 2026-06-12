import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/teachers/teacher_morning_summary_card.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/birthday_service.dart';
import 'package:school_app/services/copy_check_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockStudentService extends Mock implements StudentService {}
class MockTimetableService extends Mock implements TimetableService {}
class MockBirthdayService extends Mock implements BirthdayService {}
class MockCopyCheckService extends Mock implements CopyCheckService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStudentService mockStudentService;
  late MockTimetableService mockTimetableService;
  late MockBirthdayService mockBirthdayService;
  late MockCopyCheckService mockCopyCheckService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockStudentService = MockStudentService();
    mockTimetableService = MockTimetableService();
    mockBirthdayService = MockBirthdayService();
    mockCopyCheckService = MockCopyCheckService();

    StudentService.mockInstance = mockStudentService;
    TimetableService.mockInstance = mockTimetableService;
    BirthdayService.mockInstance = mockBirthdayService;
    CopyCheckService.mockInstance = mockCopyCheckService;
  });

  tearDown(() {
    StudentService.mockInstance = null;
    TimetableService.mockInstance = null;
    BirthdayService.mockInstance = null;
    CopyCheckService.mockInstance = null;
  });

  Widget createCard(Teacher teacher) {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherMorningSummaryCard(teacher: teacher),
          ),
        ),
      ),
    );
  }

  group('TeacherMorningSummaryCard Widget Tests', () {
    final teacher = Teacher(
      id: 'teacher_1',
      name: 'Ms. Nair',
      subject: 'Math',
      email: 'teacher@school.test',
      isClassTeacher: true,
      classTeacherOf: 'Class 9-A',
    );

    testWidgets('Shows loading state initially, then displays totals correctly', (WidgetTester tester) async {
      // Stub service methods
      when(() => mockStudentService.loadTodayFullSummary(classes: ['Class 9-A']))
          .thenAnswer((_) async => [
                const ClassSummary(
                  className: 'Class 9-A',
                  total: 40,
                  present: 35,
                  leave: 2,
                  absent: 3,
                  marked: true,
                  absentLeave: [],
                )
              ]);

      when(() => mockTimetableService.getStudentLeaveApplications(
            studentClass: 'Class 9-A',
            status: 'approved',
          )).thenAnswer((_) async => [
            {'startDate': '2026-06-12', 'numberOfDays': 1}
          ]);

      when(() => mockBirthdayService.getUpcomingStudentBirthdays(7, className: 'Class 9-A'))
          .thenAnswer((_) async => [
            {'name': 'Arjun', 'roll': 4}
          ]);

      when(() => mockTimetableService.getTodayDuties()).thenAnswer((_) async => {
            'teacher_1': 'Main Gate Attendance Supervision'
          });

      when(() => mockCopyCheckService.getChecks(teacherId: 'teacher_1'))
          .thenAnswer((_) async => []);

      // Pump Card
      await tester.pumpWidget(createCard(teacher));

      // 1. Loading state should be showing
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for loadData futures to complete
      await tester.pumpAndSettle();

      // 2. Verify all numbers rendered
      expect(find.text('3'), findsOneWidget); // todayAbsentees
      expect(find.text('1'), findsNWidgets(2)); // activeLeavesToday (1) & upcomingBirthdays (1)
      expect(find.text('Main Gate Attendance Supervision'), findsOneWidget); // dutyToday
    });
  });
}
