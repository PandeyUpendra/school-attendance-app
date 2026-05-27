import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_app/main.dart';

void main() {
  testWidgets('App smoke test — splash gate renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SchoolApp());
    // Splash gate shows a school icon + spinner while it resolves the session.
    expect(find.byIcon(Icons.school), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
