import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/models/exam.dart';
import 'package:school_app/models/homework.dart';
import 'package:school_app/services/offline_queue_service.dart';
import 'package:school_app/services/student_service.dart';
import 'package:school_app/services/exam_service.dart';
import 'package:school_app/services/homework_service.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockStudentService extends Mock implements StudentService {}
class MockExamService extends Mock implements ExamService {}
class MockHomeworkService extends Mock implements HomeworkService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockStudentService mockStudentService;
  late MockExamService mockExamService;
  late MockHomeworkService mockHomeworkService;

  setUpAll(() {
    registerFallbackValue(DateTime.now());
    registerFallbackValue(Homework(
      id: '',
      teacherId: '',
      teacherName: '',
      className: '',
      subject: '',
      title: '',
      description: '',
      dueDate: DateTime.now(),
      postedAt: DateTime.now(),
    ));
    registerFallbackValue(ExamResult(
      roll: 1,
      studentName: 'Alice',
      className: 'Class 9',
      examId: '',
      examName: '',
      marks: {},
      maxMarks: 100,
      enteredBy: '',
    ));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockStudentService = MockStudentService();
    mockExamService = MockExamService();
    mockHomeworkService = MockHomeworkService();

    StudentService.mockInstance = mockStudentService;
    ExamService.mockInstance = mockExamService;
    HomeworkService.mockInstance = mockHomeworkService;
  });

  tearDown(() {
    StudentService.mockInstance = null;
    ExamService.mockInstance = null;
    HomeworkService.mockInstance = null;
  });

  group('OfflineQueueService Tests', () {
    final offlineService = OfflineQueueService();

    test('Initial pending counts are zero', () async {
      expect(await offlineService.pendingCount(), 0);
      expect(await offlineService.pendingAttendanceCount(), 0);
      expect(await offlineService.pendingMarksCount(), 0);
      expect(await offlineService.pendingHomeworkCount(), 0);
    });

    test('Enqueue attendance caches locally and replaces duplicates', () async {
      final date = DateTime(2026, 6, 12);
      await offlineService.enqueue(
        className: 'Class 9-A',
        attendance: {1: 'P', 2: 'A'},
        date: date,
      );

      expect(await offlineService.pendingAttendanceCount(), 1);

      // Re-enqueue for same class and date: should replace
      await offlineService.enqueue(
        className: 'Class 9-A',
        attendance: {1: 'L', 2: 'P'},
        date: date,
      );

      expect(await offlineService.pendingAttendanceCount(), 1);

      final prefs = await SharedPreferences.getInstance();
      final list = jsonDecode(prefs.getString('attendance_offline_queue')!) as List;
      expect(list.length, 1);
      expect(list[0]['rolls']['1'], 'L');
    });

    test('Enqueue marks and homework correctly increments pending counts', () async {
      final examResult = ExamResult(
        roll: 10,
        studentName: 'Bob',
        className: 'Class 9-A',
        examId: 'exam_1',
        examName: 'Unit Test 1',
        marks: {'Math': 95.0},
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
      );

      await offlineService.enqueueExamResult(examId: 'exam_1', result: examResult);
      expect(await offlineService.pendingMarksCount(), 1);

      final homework = Homework(
        id: 'hw_1',
        teacherId: 't_1',
        teacherName: 'Ms. Nair',
        description: 'Solve equations',
        className: 'Class 9-A',
        subject: 'Math',
        title: 'Equations',
        dueDate: DateTime.now(),
        postedAt: DateTime.now(),
      );

      await offlineService.enqueueHomework(schoolId: 'school_1', homework: homework);
      expect(await offlineService.pendingHomeworkCount(), 1);

      expect(await offlineService.pendingCount(), 2);
    });

    test('syncAll attempts to sync all queues and clears on success', () async {
      // Seed data
      final date = DateTime(2026, 6, 12);
      await offlineService.enqueue(
        className: 'Class 9-A',
        attendance: {1: 'P'},
        date: date,
      );
      final examResult = ExamResult(
        roll: 10,
        studentName: 'Bob',
        className: 'Class 9-A',
        examId: 'exam_1',
        examName: 'Unit Test 1',
        marks: {'Math': 95.0},
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
      );
      await offlineService.enqueueExamResult(examId: 'exam_1', result: examResult);

      // Setup stub responses
      when(() => mockStudentService.saveAttendanceForDate(
            className: any(named: 'className'),
            attendance: any(named: 'attendance'),
            date: any(named: 'date'),
          )).thenAnswer((_) async => null);

      when(() => mockExamService.saveResult(
            examId: any(named: 'examId'),
            result: any(named: 'result'),
          )).thenAnswer((_) async => null);

      // Perform sync
      final synced = await offlineService.syncAll();
      expect(synced, 2);

      // Check counts are reset
      expect(await offlineService.pendingCount(), 0);

      verify(() => mockStudentService.saveAttendanceForDate(
            className: 'Class 9-A',
            attendance: {1: 'P'},
            date: date,
          )).called(1);

      verify(() => mockExamService.saveResult(
            examId: 'exam_1',
            result: any(named: 'result'),
          )).called(1);
    });

    test('Failed sync records persist and increment attempt counter', () async {
      final date = DateTime(2026, 6, 12);
      await offlineService.enqueue(
        className: 'Class 9-A',
        attendance: {1: 'P'},
        date: date,
      );

      // Throw exception on sync
      when(() => mockStudentService.saveAttendanceForDate(
            className: any(named: 'className'),
            attendance: any(named: 'attendance'),
            date: any(named: 'date'),
          )).thenThrow(Exception('Network Error'));

      final synced = await offlineService.syncAll();
      expect(synced, 0);

      // Record should still be in queue
      expect(await offlineService.pendingAttendanceCount(), 1);

      final prefs = await SharedPreferences.getInstance();
      final list = jsonDecode(prefs.getString('attendance_offline_queue')!) as List;
      expect(list[0]['attempts'], 1);
    });
  });
}
