import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/birthdays/birthdays_screen.dart';
import 'package:school_app/services/birthday_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';

class MockBirthdayService extends Mock implements BirthdayService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockBirthdayService mockBirthdayService;

  setUpAll(() {
    registerFallbackValue(Timestamp.now());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockBirthdayService = MockBirthdayService();
    BirthdayService.mockInstance = mockBirthdayService;

    // Default stubs
    when(() => mockBirthdayService.formatDOB(any())).thenReturn('15 Aug');

    when(() => mockBirthdayService.getTodayStaffBirthdays())
        .thenAnswer((_) async => []);
    when(() => mockBirthdayService.getTodayStudentBirthdays(
          className: any(named: 'className'),
          section: any(named: 'section'),
          classNames: any(named: 'classNames'),
        )).thenAnswer((_) async => []);

    when(() => mockBirthdayService.getUpcomingStaffBirthdays(any()))
        .thenAnswer((_) async => []);
    when(() => mockBirthdayService.getUpcomingStudentBirthdays(
          any(),
          className: any(named: 'className'),
          section: any(named: 'section'),
          classNames: any(named: 'classNames'),
        )).thenAnswer((_) async => []);

    when(() => mockBirthdayService.getMonthlyStaffBirthdays(any()))
        .thenAnswer((_) async => []);
    when(() => mockBirthdayService.getMonthlyStudentBirthdays(
          any(),
          className: any(named: 'className'),
          section: any(named: 'section'),
          classNames: any(named: 'classNames'),
        )).thenAnswer((_) async => []);

    when(() => mockBirthdayService.getAllStaffBirthdays())
        .thenAnswer((_) async => []);
    when(() => mockBirthdayService.getAllStudentBirthdays(
          className: any(named: 'className'),
          section: any(named: 'section'),
          classNames: any(named: 'classNames'),
        )).thenAnswer((_) async => []);
  });

  tearDown(() {
    BirthdayService.mockInstance = null;
  });

  Widget buildScreen(String role) {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: MaterialApp(
        home: BirthdaysScreen(
          role: role,
          schoolName: 'Test School',
        ),
      ),
    );
  }

  group('BirthdaysScreen Swipe Tests', () {
    testWidgets('Allows swiping left and right to switch tabs', (WidgetTester tester) async {
      await tester.pumpWidget(buildScreen('principal'));
      await tester.pumpAndSettle();

      // Verify the Today tab (filter index 0) is active by checking the empty block text.
      // In the empty block: Today -> "No staff birthdays" (translates to context.tr('noStaffBirthdays'))
      expect(find.text('No staff birthdays'), findsOneWidget);

      final detector = find.byKey(const Key('birthday-swipe-detector'));

      // Verify "Today" filter label is displayed.
      // Swipe left to shift from Today -> This Week
      // We perform a fling on the GestureDetector wrapper of the body.
      await tester.fling(detector, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Verify getUpcomingStaffBirthdays was called (meaning filter 1 - This Week is loaded)
      verify(() => mockBirthdayService.getUpcomingStaffBirthdays(7)).called(1);

      // Swipe left again: This Week -> This Month
      await tester.fling(detector, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      verify(() => mockBirthdayService.getMonthlyStaffBirthdays(any())).called(1);

      // Swipe right to go back: This Month -> This Week
      await tester.fling(detector, const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      // Swipe right again: This Week -> Today
      await tester.fling(detector, const Offset(400, 0), 1000);
      await tester.pumpAndSettle();
    });

    testWidgets('Displays "Your Birthday" and disables actions when the card belongs to the logged-in user', (WidgetTester tester) async {
      // Mock session to return a matching email
      SharedPreferences.setMockInitialValues({
        'auth_email': 'upendra@school.com',
        'auth_role': 'teacher',
        'auth_name': 'Upendra Pandey',
      });

      final staffMember = {
        'id': 'teacher_upendra',
        'name': 'Upendra Pandey',
        'email': 'upendra@school.com',
        'daysLeft': 0,
        'type': 'staff',
        'subject': 'Computer Science',
        'dateOfBirth': Timestamp.fromDate(DateTime(1985, 6, 19)),
        'phone': '1234567890',
      };

      when(() => mockBirthdayService.getTodayStaffBirthdays())
          .thenAnswer((_) async => [staffMember]);

      await tester.pumpWidget(buildScreen('teacher'));
      await tester.pumpAndSettle();

      // Verify the name is displayed as "Your Birthday" instead of "Upendra Pandey"
      expect(find.text('Your Birthday'), findsOneWidget);
      expect(find.text('Upendra Pandey'), findsNothing);

      // Verify the action button WhatsApp/Call/Custom is disabled
      final actionButtons = tester.widgetList(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ActionBtn'),
      );
      expect(actionButtons.length, 3);
      for (final btn in actionButtons) {
        expect((btn as dynamic).enabled, isFalse);
      }
    });
  });
}
