import 'dart:io';

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

  test(
    'pilot_runtime calibration Project Scenarios cover replacement checks',
    () {
      final List<ProjectScenarioFile> scenarios =
          ProjectScenarioDiscovery.discoverInDirectory(
                'examples/smoke_app/pilot',
              )
              .where(
                (ProjectScenarioFile scenario) =>
                    scenario.relativePath.startsWith('calibration/'),
              )
              .toList();

      expect(
        scenarios.map((ProjectScenarioFile scenario) => scenario.relativePath),
        <String>[
          'calibration/01_interact.yaml',
          'calibration/02_after_restart.yaml',
        ],
      );

      final Scenario interact = scenarios.first.scenario;
      expect(interact.name, 'pilot_runtime_calibration_01_interact');

      final TapAction tapByText = _actionWithLabel<TapAction>(
        interact,
        'tap_calibration_button_by_text_and_type',
      );
      expect(tapByText.finder.byText, 'Calibration tap');
      expect(tapByText.finder.byType, 'button');

      final TypeAction typeBySemanticType = _actionWithLabel<TypeAction>(
        interact,
        'type_calibration_field_by_semantic_type',
      );
      expect(typeBySemanticType.finder.byType, 'textField');
      expect(typeBySemanticType.text, 'calibrated@example.com');

      final TapAction tapByKeyAndWidget = _actionWithLabel<TapAction>(
        interact,
        'tap_calibration_chip_by_key_and_widget',
      );
      expect(tapByKeyAndWidget.finder.byKey, 'calibration_chip');
      expect(tapByKeyAndWidget.finder.byWidget, 'CalibrationChip');

      final ScrollAction targetedScroll = _actionWithLabel<ScrollAction>(
        interact,
        'targeted_scroll_calibration_list',
      );
      expect(targetedScroll.finder?.byKey, 'calibration_target_scrollable');

      final ScrollAction primaryScroll = _actionWithLabel<ScrollAction>(
        interact,
        'primary_scroll_calibration_page',
      );
      expect(primaryScroll.finder, isNull);

      final CaptureAction capture = _actionWithLabel<CaptureAction>(
        interact,
        'capture_calibration_artifacts',
      );
      expect(capture.screenshot, isTrue);
      expect(capture.widgetTree, isTrue);
      expect(capture.logs, isTrue);

      final Scenario afterRestart = scenarios.last.scenario;
      expect(afterRestart.name, 'pilot_runtime_calibration_02_after_restart');

      final WaitForAction resetCheck = _actionWithLabel<WaitForAction>(
        afterRestart,
        'verify_hot_restart_reset_state',
      );
      expect(resetCheck.finder.byText, 'Calibration taps: 0');
      expect(resetCheck.finder.byKey, 'calibration_tap_count');

      final CaptureAction restartCapture = _actionWithLabel<CaptureAction>(
        afterRestart,
        'capture_after_restart_artifacts',
      );
      expect(restartCapture.screenshot, isTrue);
      expect(restartCapture.widgetTree, isTrue);
      expect(restartCapture.logs, isTrue);
    },
  );

  test(
    'pilot_runtime calibration target initializes runtime and routes logs',
    () {
      final String source = File(
        'examples/smoke_app/lib/pilot_runtime_calibration_app.dart',
      ).readAsStringSync();

      expect(source, contains('PilotRuntimeBinding.ensureInitialized()'));
      expect(source, contains("Logger('pilot_runtime_calibration')"));
      expect(source, contains('Logger.root.onRecord.listen'));
      expect(source, contains('debugPrint('));
      expect(source, contains('CalibrationChip'));
    },
  );

  test(
    'pilot_runtime calibration README states claimed and unclaimed targets',
    () {
      final String readme = File(
        'examples/smoke_app/README.md',
      ).readAsStringSync();

      expect(readme, contains('PilotRuntime Replacement Calibration'));
      expect(readme, contains('macOS desktop debug'));
      expect(readme, contains('Android debug'));
      expect(
        readme,
        contains('Web, profile, release, and iOS are not claimed'),
      );
      expect(readme, contains('These examples do not'));
      expect(
        readme,
        contains('change Flutter Pilot runtime selection behavior'),
      );
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
