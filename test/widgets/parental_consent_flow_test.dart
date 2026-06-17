import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:school_app/features/students/consent/parental_consent_flow.dart';
import 'package:school_app/shared/providers/locale_provider.dart';
import 'package:school_app/shared/widgets/email_text_form_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createConsentFlow({
    String? prefillEmail,
  }) {
    return ChangeNotifierProvider(
      create: (_) => LocaleProvider('en'),
      child: MaterialApp(
        home: ParentalConsentFlow(
          studentDocId: 'Class_9-A__1',
          studentName: 'Amit Sharma',
          prefillGuardianName: 'Raj Sharma',
          prefillGuardianPhone: '+919876543210',
          prefillGuardianEmail: prefillEmail,
        ),
      ),
    );
  }

  group('ParentalConsentFlow Email Prefill Tests', () {
    testWidgets('Prefills the email field when prefillGuardianEmail is provided',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: 'guardian@example.com'));
      await tester.pump();

      // Find the EmailTextFormField
      final emailFieldFinder = find.byType(EmailTextFormField);
      expect(emailFieldFinder, findsOneWidget);

      // Verify the initial value in the text controller
      final EmailTextFormField field = tester.widget<EmailTextFormField>(emailFieldFinder);
      expect(field.controller.text, 'guardian@example.com');
    });

    testWidgets('Leaves the email field empty when prefillGuardianEmail is null',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: null));
      await tester.pump();

      final emailFieldFinder = find.byType(EmailTextFormField);
      expect(emailFieldFinder, findsOneWidget);

      final EmailTextFormField field = tester.widget<EmailTextFormField>(emailFieldFinder);
      expect(field.controller.text, '');
    });

    testWidgets('Allows the user to modify the prefilled email field',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: 'guardian@example.com'));
      await tester.pump();

      final emailFieldFinder = find.byType(EmailTextFormField);
      final EmailTextFormField field = tester.widget<EmailTextFormField>(emailFieldFinder);
      expect(field.controller.text, 'guardian@example.com');

      // Enter a new email address
      await tester.enterText(emailFieldFinder, 'new-guardian@example.com');
      await tester.pump();

      expect(field.controller.text, 'new-guardian@example.com');
    });

    testWidgets('Requires a valid email address before continuing',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: null));
      await tester.pump();

      // Tap the Continue button
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Verify validation fails and required error is shown
      expect(find.text('Enter an Email'), findsOneWidget);
    });
  });
}
