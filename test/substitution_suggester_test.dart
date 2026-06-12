import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:school_app/models/teacher.dart';
import 'package:school_app/models/timetable_entry.dart';
import 'package:school_app/services/substitution_suggester_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/services/substitution_history_service.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockTimetableService extends Mock implements TimetableService {}
class MockSubstitutionHistoryService extends Mock implements SubstitutionHistoryService {}

void main() {
  late MockTimetableService mockTimetableService;
  late MockSubstitutionHistoryService mockSubstitutionHistoryService;

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    mockTimetableService = MockTimetableService();
    mockSubstitutionHistoryService = MockSubstitutionHistoryService();

    TimetableService.mockInstance = mockTimetableService;
    SubstitutionHistoryService.mockInstance = mockSubstitutionHistoryService;
  });

  tearDown(() {
    TimetableService.mockInstance = null;
    SubstitutionHistoryService.mockInstance = null;
  });

  group('SubstitutionSuggesterService Tests', () {
    final suggester = SubstitutionSuggesterService();

    test('buildPlan suggests correct ranked substitutes', () async {
      // Define teachers
      final absentTeacher = Teacher(
        id: 't-absent',
        name: 'Absent Teacher',
        subject: 'Math',
        email: 'absent@school.test',
      );
      final candidate1 = Teacher(
        id: 't-math',
        name: 'Math Teacher',
        subject: 'Math', // Subject Match: +100
        email: 'math@school.test',
      );
      final candidate2 = Teacher(
        id: 't-science',
        name: 'Science Teacher',
        subject: 'Science', // No Subject Match: 0
        email: 'science@school.test',
      );
      final candidate3 = Teacher(
        id: 't-busy',
        name: 'Busy Teacher',
        subject: 'Math',
        email: 'busy@school.test',
      );

      final teachers = [absentTeacher, candidate1, candidate2, candidate3];

      // Stub getTeachers
      when(() => mockTimetableService.getTeachers()).thenAnswer((_) async => teachers);

      // Stub getSettings
      when(() => mockTimetableService.getSettings()).thenAnswer((_) async => {'workingDays': 'Mon-Sat'});

      // Stub getSubstitutionsForDate
      when(() => mockTimetableService.getSubstitutionsForDate(any())).thenAnswer((_) async => <String, String>{});

      // Stub getDutiesForDate
      when(() => mockTimetableService.getDutiesForDate(any())).thenAnswer((_) async => <String, String>{});

      // Stub getSubstituteCounts
      when(() => mockSubstitutionHistoryService.getSubstituteCounts(days: 7))
          .thenAnswer((_) async => {'t-math': 0, 't-science': 0});

      // Stub timetable:
      // - Class 9-A: Monday Bell 1 has t-absent teaching Math.
      // - Class 9-B: Monday Bell 1 has t-busy teaching Math (so t-busy is busy and cannot sub!).
      final Map<String, Map<String, Map<int, TimetableEntry>>> timetable = {
        'Class 9-A': {
          'Monday': {
            1: TimetableEntry(teacherId: 't-absent', subject: 'Math'),
          }
        },
        'Class 9-B': {
          'Monday': {
            1: TimetableEntry(teacherId: 't-busy', subject: 'Math'),
          }
        }
      };

      when(() => mockTimetableService.getTimetable()).thenAnswer((_) async => timetable);

      // Run buildPlan
      final slots = await suggester.buildPlan(
        absentTeacherId: 't-absent',
        startDate: DateTime(2026, 6, 8), // Monday
        numberOfDays: 1,
      );

      // Verify slots
      expect(slots.length, 1);
      final slot = slots.first;
      expect(slot.className, 'Class 9-A');
      expect(slot.bell, 1);
      expect(slot.subject, 'Math');

      // Verify candidates:
      // candidate3 ('t-busy') is teaching on Monday Bell 1, so they are excluded!
      // candidate1 ('t-math') has a subject match (+100).
      // candidate2 ('t-science') has no match (0).
      // Therefore, candidate1 should be the top pick.
      expect(slot.candidates.length, 2);
      expect(slot.candidates[0].teacher.id, 't-math');
      expect(slot.candidates[0].score, 100);
      expect(slot.candidates[1].teacher.id, 't-science');
      expect(slot.candidates[1].score, 0);
    });

    test('Candidates receive penalties for duty and high sub count', () async {
      final absentTeacher = Teacher(
        id: 't-absent',
        name: 'Absent Teacher',
        subject: 'Math',
        email: 'absent@school.test',
      );
      final candidate1 = Teacher(
        id: 't-math-1',
        name: 'Math Teacher 1',
        subject: 'Math', // Subject Match: +100. Has 2 substitutions: -20
        email: 'math1@school.test',
      );
      final candidate2 = Teacher(
        id: 't-math-2',
        name: 'Math Teacher 2',
        subject: 'Math', // Subject Match: +100. On Duty: -50
        email: 'math2@school.test',
      );

      final teachers = [absentTeacher, candidate1, candidate2];

      when(() => mockTimetableService.getTeachers()).thenAnswer((_) async => teachers);
      when(() => mockTimetableService.getSettings()).thenAnswer((_) async => {'workingDays': 'Mon-Sat'});
      when(() => mockTimetableService.getSubstitutionsForDate(any())).thenAnswer((_) async => <String, String>{});

      // candidate2 is on duty
      when(() => mockTimetableService.getDutiesForDate(any()))
          .thenAnswer((_) async => {'t-math-2': 'Playground Duty'});

      // candidate1 has 2 substitutions this week
      when(() => mockSubstitutionHistoryService.getSubstituteCounts(days: 7))
          .thenAnswer((_) async => {'t-math-1': 2, 't-math-2': 0});

      final Map<String, Map<String, Map<int, TimetableEntry>>> timetable = {
        'Class 9-A': {
          'Monday': {
            1: TimetableEntry(teacherId: 't-absent', subject: 'Math'),
          }
        }
      };

      when(() => mockTimetableService.getTimetable()).thenAnswer((_) async => timetable);

      final slots = await suggester.buildPlan(
        absentTeacherId: 't-absent',
        startDate: DateTime(2026, 6, 8), // Monday
        numberOfDays: 1,
      );

      expect(slots.length, 1);
      final slot = slots.first;

      // candidate1: 100 - 20 = 80
      // candidate2: 100 - 50 = 50
      expect(slot.candidates.length, 2);
      expect(slot.candidates[0].teacher.id, 't-math-1');
      expect(slot.candidates[0].score, 80);
      expect(slot.candidates[1].teacher.id, 't-math-2');
      expect(slot.candidates[1].score, 50);
    });
  });
}
