import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies deterministic terminal Step progress rendering.
///
/// These tests cover presentation behavior separately from Scenario execution
/// so runner tests can focus on progress events and report data.
void main() {
  test('renders interactive refresh markers when enabled', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('refresh.log');
      final IOSink sink = output.openWrite();
      final StepProgressRenderer renderer = StepProgressRenderer(
        sink: sink,
        interactive: true,
      );

      renderer.render(
        const StepStartedEvent(
          scenarioName: 'login_error',
          totalSteps: 1,
          step: ScenarioStep(
            index: 1,
            label: 'submit',
            action: CaptureAction(
              screenshot: false,
              snapshot: false,
              widgetTree: false,
              logs: false,
            ),
          ),
          action: 'capture',
        ),
      );
      renderer.render(
        const StepFinishedEvent(
          scenarioName: 'login_error',
          totalSteps: 1,
          report: StepRunReport(
            index: 1,
            label: 'submit',
            action: 'capture',
            status: StepStatus.passed,
            durationMs: 8,
          ),
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('\r'));
      expect(rendered, contains('\u001b['));
      expect(TerminalStyle.stripAnsi(rendered), contains('ok 8ms'));
    });
  });

  test(
    'renders unlabeled failed Steps with a concise single-line summary',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final StepProgressRenderer renderer = StepProgressRenderer(sink: sink);

        renderer.render(
          const StepFinishedEvent(
            scenarioName: 'login_error',
            totalSteps: 2,
            report: StepRunReport(
              index: 2,
              label: null,
              action: 'waitFor',
              status: StepStatus.failed,
              durationMs: 3004,
              failureReason:
                  'Finder matched no widgets.\nFull diagnostic details follow.',
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('Scenario: login_error (2 steps)'));
        expect(
          rendered,
          contains(
            '2/2 waitFor -              failed after 3004ms: '
            'Finder matched no widgets. Full diagnostic details follow.',
          ),
        );
        expect(
          rendered.split('\n').where((String line) => line.contains('2/2')),
          hasLength(1),
        );
      });
    },
  );

  test(
    'truncates long failure summaries without changing the report',
    () async {
      await FileTestkit.runZoned(() async {
        final String longFailure = 'A' * 180;
        final StepRunReport report = StepRunReport(
          index: 1,
          label: 'very_long_label_that_should_be_truncated',
          action: 'tap',
          status: StepStatus.failed,
          durationMs: 12,
          failureReason: longFailure,
        );
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final StepProgressRenderer renderer = StepProgressRenderer(sink: sink);

        renderer.render(
          StepFinishedEvent(
            scenarioName: 'login_error',
            totalSteps: 1,
            report: report,
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('very_long_lab…'));
        expect(rendered, contains('failed after 12ms: '));
        expect(rendered, isNot(contains(longFailure)));
        expect(report.failureReason, longFailure);
      });
    },
  );
}
