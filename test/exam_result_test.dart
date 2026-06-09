import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/models/exam.dart';

void main() {
  group('ExamResult Math & Sentinel Handling', () {
    test('computes total and percentage correctly for normal marks', () {
      const result = ExamResult(
        roll: 1,
        studentName: 'Alice',
        className: 'Class 5',
        examId: 'exam-1',
        examName: 'Unit Test 1',
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
        marks: {
          'Math': 90.0,
          'Science': 80.0,
          'English': 70.0,
        },
      );

      expect(result.total, 240.0);
      expect(result.subjectCount, 3);
      expect(result.percentage, 80.0);
      expect(result.grade, 'A');
      expect(result.isPassed, true);
    });

    test('ignores -1.0 (absent sentinel) in total, but keeps it in subjectCount (penalizes GPA)', () {
      const result = ExamResult(
        roll: 2,
        studentName: 'Bob',
        className: 'Class 5',
        examId: 'exam-1',
        examName: 'Unit Test 1',
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
        marks: {
          'Math': 90.0,
          'Science': -1.0, // Absent
          'English': 70.0,
        },
      );

      // Total marks should sum only Math and English: 90 + 70 = 160.
      expect(result.total, 160.0);
      expect(result.subjectCount, 3);
      // Percentage should be 160 / 300 * 100 = 53.33%
      expect(result.percentage, closeTo(53.33, 0.01));
      expect(result.grade, 'C');
      expect(result.isPassed, true);
    });

    test('handles all subjects absent correctly', () {
      const result = ExamResult(
        roll: 3,
        studentName: 'Charlie',
        className: 'Class 5',
        examId: 'exam-1',
        examName: 'Unit Test 1',
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
        marks: {
          'Math': -1.0,
          'Science': -1.0,
        },
      );

      expect(result.total, 0.0);
      expect(result.subjectCount, 2);
      expect(result.percentage, 0.0);
      expect(result.grade, 'F');
      expect(result.isPassed, false);
    });

    test('handles division-by-zero gracefully when maxMarks is 0', () {
      const result = ExamResult(
        roll: 4,
        studentName: 'David',
        className: 'Class 5',
        examId: 'exam-1',
        examName: 'Unit Test 1',
        maxMarks: 0,
        enteredBy: 'teacher@school.com',
        marks: {
          'Math': 10.0,
        },
      );

      expect(result.total, 10.0);
      expect(result.percentage, 0.0);
      expect(result.grade, 'F');
      expect(result.isPassed, false);
    });

    test('handles division-by-zero gracefully when subjectCount is 0', () {
      const result = ExamResult(
        roll: 5,
        studentName: 'Eve',
        className: 'Class 5',
        examId: 'exam-1',
        examName: 'Unit Test 1',
        maxMarks: 100,
        enteredBy: 'teacher@school.com',
        marks: {},
      );

      expect(result.total, 0.0);
      expect(result.percentage, 0.0);
      expect(result.grade, 'F');
      expect(result.isPassed, false);
    });
  });
}
