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

  group('ParentalConsentFlow Swipe Navigation Tests', () {
    testWidgets('Swiping updates selected language ChoiceChip and text content',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: 'guardian@example.com'));
      await tester.pump();

      // Tap Continue to get to the Privacy Notice step
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Verify we are on the Privacy Notice page (looking for "Privacy Notice" text or title)
      expect(find.text('Privacy Notice'), findsWidgets);

      // Verify default language is English (ChoiceChip for English selected, Hindi not)
      final englishChipFinder = find.widgetWithText(ChoiceChip, 'English');
      final hindiChipFinder = find.widgetWithText(ChoiceChip, 'हिंदी');

      expect(tester.widget<ChoiceChip>(englishChipFinder).selected, isTrue);
      expect(tester.widget<ChoiceChip>(hindiChipFinder).selected, isFalse);

      // Swipe left on the PageView to change language to Hindi
      final pageViewFinder = find.byKey(const Key('privacy_notice_page_view'));
      expect(pageViewFinder, findsOneWidget);

      await tester.fling(pageViewFinder, const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // Verify language is now Hindi
      expect(tester.widget<ChoiceChip>(englishChipFinder).selected, isFalse);
      expect(tester.widget<ChoiceChip>(hindiChipFinder).selected, isTrue);

      // Swipe right on the PageView to change language back to English
      await tester.fling(pageViewFinder, const Offset(400, 0), 1000);
      await tester.pumpAndSettle();

      // Verify language is back to English
      expect(tester.widget<ChoiceChip>(englishChipFinder).selected, isTrue);
      expect(tester.widget<ChoiceChip>(hindiChipFinder).selected, isFalse);
    });

    testWidgets('Tapping ChoiceChips animates PageView page',
        (WidgetTester tester) async {
      await tester.pumpWidget(createConsentFlow(prefillEmail: 'guardian@example.com'));
      await tester.pump();

      // Tap Continue to get to the Privacy Notice step
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final englishChipFinder = find.widgetWithText(ChoiceChip, 'English');
      final hindiChipFinder = find.widgetWithText(ChoiceChip, 'हिंदी');
      final pageViewFinder = find.byKey(const Key('privacy_notice_page_view'));

      // Initially PageView is on English (index 0)
      final PageView pageViewInitial = tester.widget<PageView>(pageViewFinder);
      expect(pageViewInitial.controller?.page?.round() ?? 0, 0);

      // Tap Hindi ChoiceChip
      await tester.tap(hindiChipFinder);
      await tester.pumpAndSettle();

      // Verify ChoiceChip is selected and PageView has moved to page 1
      expect(tester.widget<ChoiceChip>(hindiChipFinder).selected, isTrue);
      final PageView pageViewAfterTap = tester.widget<PageView>(pageViewFinder);
      expect(pageViewAfterTap.controller?.page?.round(), 1);

      // Tap English ChoiceChip
      await tester.tap(englishChipFinder);
      await tester.pumpAndSettle();

      // Verify ChoiceChip is selected and PageView is back to page 0
      expect(tester.widget<ChoiceChip>(englishChipFinder).selected, isTrue);
      final PageView pageViewAfterTapBack = tester.widget<PageView>(pageViewFinder);
      expect(pageViewAfterTapBack.controller?.page?.round(), 0);
    });
  });
}
