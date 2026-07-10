import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies the machine-readable Project Run report shape.
void main() {
  test('serializes passed and failed Scenario results in execution order', () {
    final ProjectRunReport report = ProjectRunReport(
      discoveryRootPath: 'pilot',
      scenarioResults: <ProjectScenarioRunReport>[
        const ProjectScenarioRunReport(
          scenarioPath: 'checkout/login.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath: '2026-07-01_09-31_login/run_report.json',
          htmlReportPath: '2026-07-01_09-31_login/timeline.html',
        ),
        const ProjectScenarioRunReport(
          scenarioPath: 'checkout/payment.yaml',
          status: ProjectScenarioRunStatus.failed,
          runReportPath: '2026-07-01_09-32_payment/run_report.json',
          htmlReportPath: '2026-07-01_09-32_payment/timeline.html',
        ),
      ],
      status: ProjectRunStatus.failed,
      startedAt: DateTime.utc(2026, 7, 1, 9, 30),
      durationMs: 1200,
      commandInputs: const ProjectRunCommandInputs(
        device: 'pixel-8',
        flavor: 'staging',
        target: 'lib/main_staging.dart',
      ),
    );

    expect(report.toJson(), <String, Object?>{
      'discoveryRoot': 'pilot',
      'status': 'failed',
      'startedAt': '2026-07-01T09:30:00.000Z',
      'durationMs': 1200,
      'commandInputs': <String, Object?>{
        'device': 'pixel-8',
        'flavor': 'staging',
        'target': 'lib/main_staging.dart',
      },
      'scenarios': <Object?>[
        <String, Object?>{
          'path': 'checkout/login.yaml',
          'status': 'passed',
          'runReportPath': '2026-07-01_09-31_login/run_report.json',
          'htmlReportPath': '2026-07-01_09-31_login/timeline.html',
        },
        <String, Object?>{
          'path': 'checkout/payment.yaml',
          'status': 'failed',
          'runReportPath': '2026-07-01_09-32_payment/run_report.json',
          'htmlReportPath': '2026-07-01_09-32_payment/timeline.html',
        },
      ],
    });
  });

  test('serializes environment-level failure details', () {
    final ProjectRunReport report = ProjectRunReport.environmentFailure(
      discoveryRootPath: 'pilot',
      startedAt: DateTime.utc(2026, 7, 1, 9, 30),
      durationMs: 42,
      commandInputs: const ProjectRunCommandInputs(),
      failure: const ProjectRunEnvironmentFailure(
        phase: ProjectRunEnvironmentFailurePhase.hotRestart,
        message: 'Hot restart failed.',
      ),
      scenarioResults: const <ProjectScenarioRunReport>[
        ProjectScenarioRunReport(
          scenarioPath: 'checkout/login.yaml',
          status: ProjectScenarioRunStatus.passed,
          runReportPath: '2026-07-01_09-31_login/run_report.json',
          htmlReportPath: '2026-07-01_09-31_login/timeline.html',
        ),
      ],
    );

    expect(report.toJson(), containsPair('status', 'environmentFailed'));
    expect(
      report.toJson(),
      containsPair('environmentFailure', <String, Object?>{
        'phase': 'hotRestart',
        'message': 'Hot restart failed.',
      }),
    );
  });
}
