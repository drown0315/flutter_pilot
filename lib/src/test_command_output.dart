import 'dart:io';

import 'step_progress_renderer.dart';
import 'target_app_launch_progress_renderer.dart';
import 'test_command_models.dart';

/// Terminal output helpers for the `test` command.
class TestCommandOutput {
  TestCommandOutput._();

  /// Return the Step progress renderer for human-readable `test` output.
  ///
  /// JSON output is machine-oriented and suppresses Step progress. Interactive
  /// rendering is used only when stderr is a terminal; redirected stderr gets
  /// deterministic plain-text progress lines for CI logs.
  static StepProgressRenderer? stepProgressRenderer({
    required IOSink sink,
    required bool jsonOutput,
    required bool stderrHasTerminal,
  }) {
    if (jsonOutput) {
      return null;
    }
    return StepProgressRenderer(sink: sink, interactive: stderrHasTerminal);
  }

  /// Return the Target App Launch Progress renderer for human-readable output.
  ///
  /// Launch progress is stderr-only status. JSON output suppresses it so stdout
  /// remains machine-oriented.
  static TargetAppLaunchProgressRenderer? targetAppLaunchProgressRenderer({
    required IOSink sink,
    required bool jsonOutput,
    required bool stderrHasTerminal,
  }) {
    if (jsonOutput) {
      return null;
    }
    return TargetAppLaunchProgressRenderer(
      sink: sink,
      interactive: stderrHasTerminal,
    );
  }

  /// Return deterministic stdout summary lines for a completed Project Run.
  ///
  /// The summary keeps the batch-level report path first, then prints each
  /// Scenario's existing report paths in execution order.
  static String renderProjectRunSummary(ProjectRunCommandReport report) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Project Run: ${report.status.name}')
      ..writeln('Project Run report: ${report.projectRunReportPath}');
    for (final ProjectRunScenarioOutputReport scenarioReport
        in report.scenarioReports) {
      buffer
        ..writeln(
          'Scenario: ${scenarioReport.scenarioPath} '
          '(${scenarioReport.status.name})',
        )
        ..writeln('Run report: ${scenarioReport.runReportPath}')
        ..writeln('HTML report: ${scenarioReport.htmlReportPath}');
    }
    return buffer.toString();
  }
}
