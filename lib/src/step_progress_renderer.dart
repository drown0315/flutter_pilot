import 'dart:io';

import 'scenario_runner.dart';

/// Renders deterministic plain-text Step progress for CLI output.
///
/// The renderer owns human-facing wording and layout. It writes to the sink
/// supplied by the CLI so progress can go to stderr while report paths stay on
/// stdout.
class StepProgressRenderer {
  StepProgressRenderer({required this.sink});

  final IOSink sink;
  bool _wroteScenarioHeader = false;

  /// Render one runner progress event.
  ///
  /// Args:
  /// `event` is emitted by `ScenarioRunner` when a Step starts or finishes.
  /// Started events print `running`; finished events print the Step's final
  /// status and elapsed duration.
  void render(StepProgressEvent event) {
    _writeScenarioHeader(event);
    switch (event) {
      case StepStartedEvent():
        sink.writeln(_startedLine(event));
      case StepFinishedEvent():
        sink.writeln(_finishedLine(event));
    }
  }

  /// Print the run header once before the first Step progress line.
  void _writeScenarioHeader(StepProgressEvent event) {
    if (_wroteScenarioHeader) {
      return;
    }
    sink.writeln('Scenario: ${event.scenarioName} (${event.totalSteps} steps)');
    _wroteScenarioHeader = true;
  }

  /// Render a deterministic `running` line for a Step.
  String _startedLine(StepStartedEvent event) {
    return '${_prefix(event.step.index, event.totalSteps)} '
        '${_actionColumn(event.action)} '
        '${_labelColumn(event.step.label)} '
        'running';
  }

  /// Render the final status and duration for a Step.
  String _finishedLine(StepFinishedEvent event) {
    final StepRunReport report = event.report;
    return '${_prefix(report.index, event.totalSteps)} '
        '${_actionColumn(report.action)} '
        '${_labelColumn(report.label)} '
        '${_statusText(report)}';
  }

  /// Return the `current/total` prefix for one Step line.
  String _prefix(int index, int totalSteps) => '$index/$totalSteps';

  /// Return a fixed-width action column for non-interactive logs.
  String _actionColumn(String action) => action.padRight(7);

  /// Return a fixed-width Step Label column, using `-` for unlabeled Steps.
  String _labelColumn(String? label) => (label ?? '-').padRight(14);

  /// Return the final status text shown after Step completion.
  String _statusText(StepRunReport report) {
    return switch (report.status) {
      StepStatus.passed => 'ok ${report.durationMs}ms',
      StepStatus.failed => 'failed after ${report.durationMs}ms',
      StepStatus.skipped => 'skipped',
    };
  }
}
