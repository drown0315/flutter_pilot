import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies terminal rendering for diagnostics printed by `run --print`.
void main() {
  test(
    'renders Widget Tree as a filtered summary tree without truncating children',
    () {
      final ScenarioRunReport report = ScenarioRunReport(
        scenarioName: 'smoke_runtime',
        scenarioDescription: null,
        totalSteps: 0,
        status: ScenarioRunStatus.passed,
        startedAt: DateTime.utc(2026, 6, 13),
        durationMs: 1,
        steps: const <StepRunReport>[],
        runDirectoryPath: '.runs/smoke_runtime',
        artifacts: const <ArtifactReport>[],
        printedDiagnostics: const <PrintedDiagnostic>[
          PrintedDiagnostic(
            type: PrintDiagnostic.widgetTree,
            data: <String, Object?>{
              'widgetType': 'RootWidget',
              'renderObjectType': '_ReusableRenderView',
              'children': <Object?>[
                <String, Object?>{
                  'widgetType': '_FocusInheritedScope',
                  'children': <Object?>[
                    <String, Object?>{
                      'widgetType': 'SmokeApp',
                      'sourceLocationHint': 'SmokeApp <- _FocusInheritedScope',
                      'children': <Object?>[
                        <String, Object?>{'widgetType': 'MaterialApp'},
                        <String, Object?>{
                          'widgetType': 'EmailTextField',
                          'label': 'Email',
                          'value': 'smoke@example.com',
                          'enabled': true,
                        },
                        <String, Object?>{
                          'widgetType': 'PrimaryButton',
                          'label': 'Submit smoke',
                          'enabled': true,
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ),
        ],
      );

      final String output = DiagnosticTextRenderer.render(report);

      expect(output, contains('Widget Tree'));
      expect(output, contains('- SmokeApp'));
      expect(
        output,
        contains(
          '  - EmailTextField "Email" value="smoke@example.com" enabled',
        ),
      );
      expect(output, contains('  - PrimaryButton "Submit smoke" enabled'));
      expect(output, contains('framework/noisy nodes omitted'));
      expect(output, isNot(contains('RootWidget')));
      expect(output, isNot(contains('_FocusInheritedScope')));
      expect(output, isNot(contains('MaterialApp')));
      expect(output, isNot(contains('renderObjectType')));
      expect(output, isNot(contains('sourceLocationHint')));
    },
  );
}
