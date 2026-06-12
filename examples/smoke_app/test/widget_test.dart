import 'package:flutter/material.dart';
import 'package:flutter_pilot_smoke/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the sample app behavior used by the Flutter Pilot smoke Scenario.
void main() {
  testWidgets('shows validation message after submit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SmokeApp());

    await tester.enterText(find.byType(TextField), 'smoke@example.com');
    await tester.tap(find.text('Submit smoke'));
    await tester.pump();

    expect(find.text('Smoke validation failed'), findsOneWidget);
  });
}
