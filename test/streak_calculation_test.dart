import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/services/student_service.dart';

void main() {
  group('StudentService.calculateStreaksFromData', () {
    // Helper to build dates going backwards from a Wednesday.
    // e.g. base = Wednesday, base - 1 = Tuesday, etc.
    final baseDate = DateTime(2026, 6, 10); // Wednesday

    List<DateTime> buildDates(int count) {
      return List.generate(count, (i) => baseDate.subtract(Duration(days: i)));
    }

    test('simple consecutive absences are counted correctly', () {
      final dates = buildDates(3); // Wed, Tue, Mon (all working days)
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 3);
    });

    test('Sunday is skipped and does not break or extend streak', () {
      // Wed, Tue, Mon, Sun (non-working), Sat (working)
      final dates = buildDates(5);
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
        null,                       // Sun (skipped anyway)
        {'rolls': {'1': 'Absent'}}, // Sat
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 4); // Mon, Tue, Wed, Sat are working. Sun skipped.
    });

    test('Saturday is skipped when workingDays is Mon-Fri', () {
      // Wed, Tue, Mon, Sun (weekend), Sat (weekend under Mon-Fri), Fri (working)
      final dates = buildDates(6);
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
        null,                       // Sun (weekend)
        null,                       // Sat (weekend)
        {'rolls': {'1': 'Absent'}}, // Fri
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Fri',
      );

      expect(streaks[1], 4); // Fri, Mon, Tue, Wed. Sat and Sun are skipped.
    });

    test('Saturday is NOT skipped and extends streak when workingDays is Mon-Sat', () {
      // Wed, Tue, Mon, Sun (weekend), Sat (working), Fri (working)
      final dates = buildDates(6);
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
        null,                       // Sun (weekend)
        {'rolls': {'1': 'Absent'}}, // Sat
        {'rolls': {'1': 'Absent'}}, // Fri
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 5); // Fri, Sat, Mon, Tue, Wed. Sun skipped.
    });

    test('unmarked working day (null data) breaks active streaks', () {
      // Wed (Absent), Tue (unmarked working day), Mon (Absent)
      final dates = buildDates(3);
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        null,                       // Tue (unmarked)
        {'rolls': {'1': 'Absent'}}, // Mon
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      // Student 1 was absent on Wed, but the streak broke on Tue.
      // So their consecutive absence streak is 1 (just Wed).
      expect(streaks[1], 1);
    });

    test('empty rolls on working day breaks active streaks', () {
      // Wed (Absent), Tue (empty rolls), Mon (Absent)
      final dates = buildDates(3);
      final datas = [
        {'rolls': {'1': 'Absent'}}, // Wed
        {'rolls': {}},              // Tue (empty rolls)
        {'rolls': {'1': 'Absent'}}, // Mon
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 1);
    });

    test('missing roll for student on working day breaks their streak', () {
      // Wed (Absent), Tue (Present/not in rolls), Mon (Absent)
      final dates = buildDates(3);
      final datas = [
        {'rolls': {'1': 'Absent', '2': 'Absent'}},
        {'rolls': {'2': 'Absent'}}, // 1 is missing on Tue
        {'rolls': {'1': 'Absent', '2': 'Absent'}},
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 1); // 1's streak broke on Tue
      expect(streaks[2], 3); // 2 was absent all 3 days
    });

    test('present status on working day breaks streak', () {
      // Wed (Absent), Tue (Present), Mon (Absent)
      final dates = buildDates(3);
      final datas = [
        {'rolls': {'1': 'Absent'}},
        {'rolls': {'1': 'Present'}}, // Present
        {'rolls': {'1': 'Absent'}},
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 1);
    });

    test('leave and false status count as absent/leave and extend streak', () {
      final dates = buildDates(3);
      final datas = [
        {'rolls': {'1': 'Absent'}},
        {'rolls': {'1': 'Leave'}},
        {'rolls': {'1': false}}, // false is legacy absent status
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks[1], 3);
    });

    test('no streaks start if the most recent working day is unmarked', () {
      final dates = buildDates(3);
      final datas = [
        null,                       // Wed (unmarked most recent working day)
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks.isEmpty, isTrue);
    });

    test('no streaks start if the most recent working day has empty rolls', () {
      final dates = buildDates(3);
      final datas = [
        {'rolls': {}},              // Wed (empty rolls)
        {'rolls': {'1': 'Absent'}}, // Tue
        {'rolls': {'1': 'Absent'}}, // Mon
      ];

      final streaks = StudentService.calculateStreaksFromData(
        dates: dates,
        datas: datas,
        workingDaysSetting: 'Mon-Sat',
      );

      expect(streaks.isEmpty, isTrue);
    });
  });
}
