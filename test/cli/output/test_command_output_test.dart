import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies pure `test` command output rendering helpers.
void main() {
  test('Project Run output renders deterministic all-passed summary', () {
    const ProjectRunResult report = ProjectRunResult(
      passed: true,
      status: ProjectRunStatus.passed,
      projectRunReportPath:
          '.runs/2026-07-01_09-30_project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[
        ProjectRunScenarioOutputReport(
          scenarioPath: 'checkout.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_checkout/run_report.json',
          htmlReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_checkout/timeline.html',
        ),
        ProjectRunScenarioOutputReport(
          scenarioPath: 'login.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_login/run_report.json',
          htmlReportPath:
              '.runs/2026-07-01_09-30_project-run/'
              '2026-07-01_09-30_login/timeline.html',
        ),
      ],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, '''
Project Run: passed
Project Run report: .runs/2026-07-01_09-30_project-run/project_run_report.json
Scenario: checkout.yaml (passed)
Run report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_checkout/run_report.json
HTML report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_checkout/timeline.html
Scenario: login.yaml (passed)
Run report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_login/run_report.json
HTML report: .runs/2026-07-01_09-30_project-run/2026-07-01_09-30_login/timeline.html
''');
  });

  test('Project Run output renders partially failed summary', () {
    const ProjectRunResult report = ProjectRunResult(
      passed: false,
      status: ProjectRunStatus.failed,
      projectRunReportPath: '.runs/project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[
        ProjectRunScenarioOutputReport(
          scenarioPath: 'login.yaml',
          status: ProjectScenarioRunStatus.failed,
          runReportPath: '.runs/project-run/login/run_report.json',
          htmlReportPath: '.runs/project-run/login/timeline.html',
        ),
        ProjectRunScenarioOutputReport(
          scenarioPath: 'checkout.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath: '.runs/project-run/checkout/run_report.json',
          htmlReportPath: '.runs/project-run/checkout/timeline.html',
        ),
      ],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, contains('Project Run: failed'));
    expect(rendered, contains('Scenario: login.yaml (failed)'));
    expect(rendered, contains('Scenario: checkout.yaml (passed)'));
  });

  test('Project Run output renders environment-level failure summary', () {
    const ProjectRunResult report = ProjectRunResult(
      passed: false,
      status: ProjectRunStatus.environmentFailed,
      projectRunReportPath: '.runs/project-run/project_run_report.json',
      scenarioReports: <ProjectRunScenarioOutputReport>[],
    );

    final String rendered = TestCommandOutput.renderProjectRunSummary(report);

    expect(rendered, '''
Project Run: environmentFailed
Project Run report: .runs/project-run/project_run_report.json
''');
  });

  test(
    'test command chooses interactive progress only for terminals',
    () async {
      await FileTestkit.runZoned(() async {
        final IOSink sink = File('progress.log').openWrite();
        try {
          final StepProgressRenderer? jsonRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: true,
                stderrHasTerminal: true,
              );
          final StepProgressRenderer? terminalRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: true,
              );
          final StepProgressRenderer? redirectedRenderer =
              TestCommandOutput.stepProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: false,
              );
          final TargetAppLaunchProgressRenderer? terminalLaunchRenderer =
              TestCommandOutput.targetAppLaunchProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: true,
              );
          final TargetAppLaunchProgressRenderer? redirectedLaunchRenderer =
              TestCommandOutput.targetAppLaunchProgressRenderer(
                sink: sink,
                jsonOutput: false,
                stderrHasTerminal: false,
              );

          expect(jsonRenderer, isNull);
          expect(terminalRenderer?.interactive, isTrue);
          expect(redirectedRenderer?.interactive, isFalse);
          expect(terminalLaunchRenderer?.interactive, isTrue);
          expect(redirectedLaunchRenderer?.interactive, isFalse);
        } finally {
          await sink.close();
        }
      });
    },
  );
}
