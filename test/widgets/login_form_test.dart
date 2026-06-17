import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/auth/login_screen.dart';
import 'package:school_app/services/auth_service.dart';
import 'package:school_app/services/timetable_service.dart';
import 'package:school_app/shared/providers/locale_provider.dart';
import 'package:school_app/shared/widgets/email_text_form_field.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class MockAuthService extends Mock implements AuthService {}
class MockTimetableService extends Mock implements TimetableService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthService mockAuthService;
  late MockTimetableService mockTimetableService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockAuthService = MockAuthService();
    mockTimetableService = MockTimetableService();
    when(() => mockAuthService.isBiometricEnabled()).thenAnswer((_) async => false);

    AuthService.mockInstance = mockAuthService;
    TimetableService.mockInstance = mockTimetableService;
  });

  tearDown(() {
    AuthService.mockInstance = null;
    TimetableService.mockInstance = null;
  });

  Widget createLoginScreen() {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: const MaterialApp(
        home: LoginScreen(),
      ),
    );
  }

  group('LoginScreen Form Widget Tests', () {
    final Finder passwordFieldFinder = find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.prefixIcon as Icon?)?.icon == Icons.lock_outline,
    );

    testWidgets('Renders all input fields and titles', (WidgetTester tester) async {
      await tester.pumpWidget(createLoginScreen());

      expect(find.text('Klassivo'), findsOneWidget);
      expect(find.byType(EmailTextFormField), findsOneWidget);
      expect(passwordFieldFinder, findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('Toggles password visibility when eye icon is tapped', (WidgetTester tester) async {
      await tester.pumpWidget(createLoginScreen());

      final TextField passwordField = tester.widget<TextField>(passwordFieldFinder);
      expect(passwordField.obscureText, isTrue);

      // Tap the visibility icon button
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();

      final TextField visiblePasswordField = tester.widget<TextField>(passwordFieldFinder);
      expect(visiblePasswordField.obscureText, isFalse);
    });

    testWidgets('Shows error message when email is invalid', (WidgetTester tester) async {
      await tester.pumpWidget(createLoginScreen());

      // Enter invalid email
      await tester.enterText(find.byType(EmailTextFormField), 'invalid-email');
      await tester.enterText(passwordFieldFinder, 'password123');
      await tester.pump();

      // Tap Sign In
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('Shows error message when password is empty', (WidgetTester tester) async {
      await tester.pumpWidget(createLoginScreen());

      // Enter valid email but empty password
      await tester.enterText(find.byType(EmailTextFormField), 'test@school.test');
      await tester.enterText(passwordFieldFinder, '');
      await tester.pump();

      // Tap Sign In
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('Calls AuthService.signInWithEmail on submit', (WidgetTester tester) async {
      when(() => mockAuthService.signInWithEmail(any(), any()))
          .thenAnswer((_) async => throw Exception('Stub login result'));

      await tester.pumpWidget(createLoginScreen());

      await tester.enterText(find.byType(EmailTextFormField), 'test@school.test');
      await tester.enterText(passwordFieldFinder, 'password123');
      await tester.pump();

      await tester.tap(find.text('Sign In'));
      await tester.pump();

      verify(() => mockAuthService.signInWithEmail('test@school.test', 'password123')).called(1);
    });
  });
}
