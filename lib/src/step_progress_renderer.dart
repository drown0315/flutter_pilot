import 'dart:io';

import 'scenario.dart';
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
  String? _lastScenarioName;
  int _lastInteractiveLineCount = 0;
  String? _scenarioName;
  int? _totalSteps;
  final Map<int, _ProgressStepLine> _interactiveSteps =
      <int, _ProgressStepLine>{};
  final Map<int, String> _stepSourceDisplayPaths = <int, String>{};

  /// Render one runner progress event.
  ///
  /// Args:
  /// `event` is emitted by `ScenarioRunner` when a Step starts or finishes.
  /// Started events print `running`; finished events print the Step's final
  /// status and elapsed duration. Steps expanded from Step Libraries include
  /// the source file display path, e.g. `[flows/login.yaml]`.
  void render(StepProgressEvent event) {
    if (interactive) {
      _renderInteractive(event);
      return;
    }
    _resetHeaderForNewScenario(event.scenarioName);
    _writeScenarioHeader(event);
    switch (event) {
      case StepStartedEvent():
        _recordStepSource(event.step);
        sink.writeln(_startedLine(event));
      case StepFinishedEvent():
        sink.writeln(_finishedLine(event));
    }
  }

  /// Update the in-memory Step table and redraw the interactive progress block.
  void _renderInteractive(StepProgressEvent event) {
    _scenarioName = event.scenarioName;
    _totalSteps = event.totalSteps;
    switch (event) {
      case StepStartedEvent():
        _recordStepSource(event.step);
        _interactiveSteps[event.step.index] = _ProgressStepLine(
          index: event.step.index,
          totalSteps: event.totalSteps,
          action: event.action,
          label: event.step.label,
          sourceDisplayPath: _stepSourceDisplayPaths[event.step.index],
          status: _ProgressVisualStatus.running,
        );
      case StepFinishedEvent():
        final StepRunReport report = event.report;
        _interactiveSteps[report.index] = _ProgressStepLine(
          index: report.index,
          totalSteps: event.totalSteps,
          action: report.action,
          label: report.label,
          sourceDisplayPath: _stepSourceDisplayPaths[report.index],
          status: _visualStatusFor(report.status),
          report: report,
        );
    }
    _redrawInteractiveBlock();
  }

  /// Redraw the whole interactive Step block in place.
  void _redrawInteractiveBlock() {
    if (_lastInteractiveLineCount > 0) {
      sink.write('\u001b[${_lastInteractiveLineCount}A');
      sink.write('\u001b[J');
    }
    final List<String> lines = _interactiveBlockLines();
    for (final String line in lines) {
      sink.writeln(line);
    }
    _lastInteractiveLineCount = lines.length;
  }

  /// Return the current interactive block as terminal lines.
  List<String> _interactiveBlockLines() {
    final String scenarioName = _scenarioName ?? 'scenario';
    final int totalSteps = _totalSteps ?? 0;
    return <String>[
      'Scenario: $scenarioName ($totalSteps steps)',
      TerminalStyle.bold('> Step Progress', enabled: true),
      for (int index = 1; index <= totalSteps; index++)
        _interactiveLine(
          _interactiveSteps[index] ??
              _ProgressStepLine(
                index: index,
                totalSteps: totalSteps,
                action: '-',
                label: null,
                sourceDisplayPath: null,
                status: _ProgressVisualStatus.pending,
              ),
        ),
    ];
  }

  /// Render one Step row for the interactive block.
  String _interactiveLine(_ProgressStepLine line) {
    return '${_statusIcon(line.status)} '
        '${_prefix(line.index, line.totalSteps)} '
        '${_actionColumn(line.action)} '
        '${_labelColumn(line.label)} '
        '${_interactiveStatusText(line)}'
        '${_sourceSuffix(line.sourceDisplayPath)}';
  }

  /// Return a styled status label for an interactive Step row.
  String _interactiveStatusText(_ProgressStepLine line) {
    final StepRunReport? report = line.report;
    if (report == null) {
      return switch (line.status) {
        _ProgressVisualStatus.pending => TerminalStyle.dim(
          'pending',
          enabled: true,
        ),
        _ProgressVisualStatus.running => 'running',
        _ProgressVisualStatus.passed ||
        _ProgressVisualStatus.failed => 'running',
      };
    }
    return _statusText(report);
  }

  /// Return the visual status for a finished Step report status.
  _ProgressVisualStatus _visualStatusFor(StepStatus status) {
    return switch (status) {
      StepStatus.passed => _ProgressVisualStatus.passed,
      StepStatus.failed => _ProgressVisualStatus.failed,
      StepStatus.skipped => _ProgressVisualStatus.pending,
    };
  }

  /// Return the icon displayed beside an interactive Step row.
  String _statusIcon(_ProgressVisualStatus status) {
    return switch (status) {
      _ProgressVisualStatus.pending => '⬜',
      _ProgressVisualStatus.running => '⏳',
      _ProgressVisualStatus.passed => '✅',
      _ProgressVisualStatus.failed => '❌',
    };
  }

  /// Print the run header once before the first Step progress line.
  void _writeScenarioHeader(StepProgressEvent event) {
    if (_wroteScenarioHeader) {
      return;
    }
    sink.writeln('Scenario: ${event.scenarioName} (${event.totalSteps} steps)');
    _wroteScenarioHeader = true;
    _lastScenarioName = event.scenarioName;
  }

  /// Reset header state when the renderer receives a new Scenario name.
  void _resetHeaderForNewScenario(String scenarioName) {
    if (_lastScenarioName == null || _lastScenarioName == scenarioName) {
      return;
    }
    _wroteScenarioHeader = false;
    _stepSourceDisplayPaths.clear();
  }

  /// Render a deterministic `running` line for a Step.
  String _startedLine(StepStartedEvent event) {
    return '${_prefix(event.step.index, event.totalSteps)} '
        '${_actionColumn(event.action)} '
        '${_labelColumn(event.step.label)} '
        'running'
        '${_sourceSuffix(_stepSourceDisplayPaths[event.step.index])}';
  }

  /// Render the final status and duration for a Step.
  String _finishedLine(StepFinishedEvent event) {
    final StepRunReport report = event.report;
    return '${_prefix(report.index, event.totalSteps)} '
        '${_actionColumn(report.action)} '
        '${_labelColumn(report.label)} '
        '${_statusText(report)}'
        '${_sourceSuffix(_stepSourceDisplayPaths[report.index])}';
  }

  /// Remember source display paths from started events for finished rows.
  void _recordStepSource(ScenarioStep step) {
    final StepSource? source = step.source;
    if (source == null || source.includeChain.isEmpty) {
      return;
    }
    _stepSourceDisplayPaths[step.index] = source.displayPath;
  }

  /// Return a concise source suffix for Steps expanded from Step Libraries.
  String _sourceSuffix(String? displayPath) {
    if (displayPath == null || displayPath.isEmpty) {
      return '';
    }
    return ' [$displayPath]';
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

/// Stored state for one row in the interactive progress block.
class _ProgressStepLine {
  const _ProgressStepLine({
    required this.index,
    required this.totalSteps,
    required this.action,
    required this.label,
    required this.sourceDisplayPath,
    required this.status,
    this.report,
  });

  final int index;
  final int totalSteps;
  final String action;
  final String? label;
  final String? sourceDisplayPath;
  final _ProgressVisualStatus status;
  final StepRunReport? report;
}

enum _ProgressVisualStatus { pending, running, passed, failed }
