import 'dart:io';

import 'scenario_runner.dart';
import 'terminal_style.dart';

/// Renders deterministic plain-text Step progress for CLI output.
///
/// The renderer owns human-facing wording and layout. It writes to the sink
/// supplied by the CLI so progress can go to stderr while report paths stay on
/// stdout.
class StepProgressRenderer {
  StepProgressRenderer({required this.sink, this.interactive = false});

  final IOSink sink;
  final bool interactive;
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
        _writeLine(_startedLine(event), replacePrevious: interactive);
      case StepFinishedEvent():
        _writeLine(_finishedLine(event), replacePrevious: interactive);
    }
  }

  /// Write one rendered line, optionally replacing the previous terminal line.
  void _writeLine(String line, {required bool replacePrevious}) {
    if (replacePrevious) {
      sink.write('\r');
    }
    sink.writeln(line);
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
        '${_statusText(report)}${_emojiSuffix(report)}';
  }

  /// Return the `current/total` prefix for one Step line.
  String _prefix(int index, int totalSteps) => '$index/$totalSteps';

  /// Return a fixed-width action column for non-interactive logs.
  String _actionColumn(String action) => action.padRight(7);

  /// Return a fixed-width Step Label column, using `-` for unlabeled Steps.
  String _labelColumn(String? label) {
    final String value = label ?? '-';
    if (value.length <= 14) {
      return value.padRight(14);
    }
    return '${value.substring(0, 13)}…';
  }

  /// Return the final status text shown after Step completion.
  String _statusText(StepRunReport report) {
    final String plainStatus = switch (report.status) {
      StepStatus.passed => 'ok ${report.durationMs}ms',
      StepStatus.failed =>
        'failed after ${report.durationMs}ms${_failureSuffix(report)}',
      StepStatus.skipped => 'skipped',
    };
    if (!interactive) {
      return plainStatus;
    }
    return switch (report.status) {
      StepStatus.passed => TerminalStyle.bold(
        TerminalStyle.color(plainStatus, TerminalColor.green, enabled: true),
        enabled: true,
      ),
      StepStatus.failed => TerminalStyle.color(
        plainStatus,
        TerminalColor.red,
        enabled: true,
      ),
      StepStatus.skipped => TerminalStyle.dim(plainStatus, enabled: true),
    };
  }

  /// Return a short success/failure emoji marker for interactive terminals.
  String _emojiSuffix(StepRunReport report) {
    if (!interactive) {
      return '';
    }
    return switch (report.status) {
      StepStatus.passed => ' ✅',
      StepStatus.failed => ' ❌',
      StepStatus.skipped => '',
    };
  }

  /// Return a concise single-line failure summary for terminal output.
  String _failureSuffix(StepRunReport report) {
    final String? failureReason = report.failureReason;
    if (failureReason == null || failureReason.isEmpty) {
      return '';
    }
    final String normalized = failureReason.replaceAll(RegExp(r'\s+'), ' ');
    final int maxSummaryLength = 80;
    if (normalized.length <= maxSummaryLength) {
      return ': $normalized';
    }
    return ': ${normalized.substring(0, maxSummaryLength - 1)}…';
  }
}
