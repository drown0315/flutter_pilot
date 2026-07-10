import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies that the checked-in real-runtime smoke Scenario keeps exercising
/// the supported Finder contract.
void main() {
  test(
    'example smoke Scenario includes byText, byType, and combined Finder',
    () {
      final Scenario scenario = ScenarioParser.parseFile(
        'examples/smoke_app/smoke_scenario.yaml',
      );

      expect(scenario.name, 'smoke_runtime');

      final WaitForAction waitForReady = _actionWithLabel<WaitForAction>(
        scenario,
        'wait_for_smoke_form',
      );
      expect(waitForReady.finder.byText, 'Smoke form');

      final TypeAction type = _actionWithLabel<TypeAction>(
        scenario,
        'enter_email',
      );
      expect(type.finder.byText, isNull);
      expect(type.finder.byType, 'textField');

      final TapAction tap = _actionWithLabel<TapAction>(
        scenario,
        'submit_form',
      );
      expect(tap.finder.byText, 'Submit smoke');
      expect(tap.finder.byType, 'button');

      final WaitForAction waitFor = _actionWithLabel<WaitForAction>(
        scenario,
        'wait_for_error',
      );
      expect(waitFor.finder.byText, 'Smoke validation failed');
      expect(waitFor.finder.byType, isNull);

      expect(scenario.steps, hasLength(4));
    },
  );
}

/// Return the typed action for a labeled Step in the smoke Scenario.
T _actionWithLabel<T extends StepAction>(Scenario scenario, String label) {
  final ScenarioStep step = scenario.steps.singleWhere(
    (ScenarioStep step) => step.label == label,
  );
  expect(step.action, isA<T>());
  return step.action as T;
}
