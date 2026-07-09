import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Scenario domain behavior that is independent from YAML parsing.
void main() {
  group('Scenario', () {
    test('creates a run slice through a 1-based step number', () {
      final Scenario scenario = _scenario();

      final Scenario sliced = scenario.sliceThroughStepNumber(2);

      expect(sliced.name, 'login_error');
      expect(sliced.description, 'description');
      expect(sliced.steps.map((ScenarioStep step) => step.label), <String?>[
        'enter_email',
        'submit_login',
      ]);
    });

    test('creates a run slice through a step label', () {
      final Scenario scenario = _scenario();

      final Scenario sliced = scenario.sliceThroughStepLabel('submit_login');

      expect(sliced.steps.map((ScenarioStep step) => step.label), <String?>[
        'enter_email',
        'submit_login',
      ]);
    });

    test('rejects invalid step number slices', () {
      final Scenario scenario = _scenario();

      expect(() => scenario.sliceThroughStepNumber(0), throwsRangeError);
      expect(() => scenario.sliceThroughStepNumber(4), throwsRangeError);
    });

    test('rejects missing step label slices', () {
      final Scenario scenario = _scenario();

      expect(
        () => scenario.sliceThroughStepLabel('missing_label'),
        throwsArgumentError,
      );
    });
  });
}

/// Build a small Scenario with enough steps to exercise stop-point slicing.
Scenario _scenario() {
  return const Scenario(
    name: 'login_error',
    description: 'description',
    steps: <ScenarioStep>[
      ScenarioStep(
        index: 1,
        label: 'enter_email',
        action: TypeAction(
          finder: Finder(byText: 'email_input'),
          text: 'bad@example.com',
        ),
      ),
      ScenarioStep(
        index: 2,
        label: 'submit_login',
        action: TapAction(finder: Finder(byText: 'login_button')),
      ),
      ScenarioStep(
        index: 3,
        label: 'capture_error',
        action: CaptureAction(
          screenshot: true,
          snapshot: false,
          widgetTree: true,
          logs: true,
        ),
      ),
    ],
  );
}
