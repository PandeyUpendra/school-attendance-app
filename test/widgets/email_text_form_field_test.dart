import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/shared/widgets/email_text_form_field.dart';

void main() {
  testWidgets('EmailTextFormField shows error on blur when invalid', (WidgetTester tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              EmailTextFormField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const TextField(key: Key('other_field')),
            ],
          ),
        ),
      ),
    );

    // Initial state: no error
    expect(find.text('Enter a valid email address'), findsNothing);

    // Enter invalid email
    await tester.enterText(find.byType(EmailTextFormField), 'invalid-email');
    await tester.pump();

    // Still no error (no blur yet)
    expect(find.text('Enter a valid email address'), findsNothing);

    // Tap outside (on the other field) to trigger blur
    await tester.tap(find.byKey(const Key('other_field')));
    await tester.pump();

    // Now error should show
    expect(find.text('Enter a valid email address'), findsOneWidget);
  });
}
