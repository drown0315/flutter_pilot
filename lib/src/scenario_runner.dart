import 'dart:convert';
import 'dart:io';

import 'runtime/runtime_contract.dart';
import 'scenario.dart';

/// Executes a Scenario against a Runtime Adapter and writes a basic report.
///
/// The runner owns Scenario control flow:
/// - initialize the Runtime Adapter
/// - execute ordered Steps
/// - dispose the Runtime Adapter
/// - write `run_report.json` into the configured output directory
///
/// It does not create the final run directory or persist artifacts yet; those
/// responsibilities belong to the later Artifact Store slice.
class ScenarioRunner {
  const ScenarioRunner({required this.adapter, required this.outputDirectory});

  static const Duration _waitForPollInterval = Duration(milliseconds: 50);

  final RuntimeAdapter adapter;
  final Directory outputDirectory;

  /// Execute every Step in `scenario` and write `run_report.json`.
  ///
  /// Args:
  /// `scenario` is the parsed Scenario to replay through the Runtime Adapter.
  ///
  /// Returns:
  /// A `ScenarioRunReport` containing Scenario metadata, total status, and
  /// ordered Step results.
  Future<ScenarioRunReport> run(Scenario scenario) async {
    final DateTime startedAt = DateTime.now().toUtc();
    final Stopwatch stopwatch = Stopwatch()..start();
    final List<StepRunReport> steps = <StepRunReport>[];

    bool failed = false;
    String? failureReason;
    try {
      await adapter.initialize();
    } on RuntimeOperationException catch (error) {
      stopwatch.stop();
      final ScenarioRunReport report = ScenarioRunReport(
        scenarioName: scenario.name,
        scenarioDescription: scenario.description,
        status: ScenarioRunStatus.failed,
        startedAt: startedAt,
        durationMs: stopwatch.elapsedMilliseconds,
        steps: steps,
        failureReason: error.message,
      );
      _writeReport(report);
      return report;
    }
    ScenarioStep? activeStep;
    Stopwatch? activeStepStopwatch;
    try {
      for (final ScenarioStep step in scenario.steps) {
        activeStep = step;
        activeStepStopwatch = Stopwatch()..start();
        final StepRunReport stepReport = await _executeStep(
          step,
          activeStepStopwatch,
        );
        steps.add(stepReport);
        if (stepReport.status == StepStatus.failed) {
          failed = true;
          failureReason = stepReport.failureReason;
          break;
        }
      }
    } on RuntimeOperationException catch (error) {
      activeStepStopwatch?.stop();
      final ScenarioStep? step = activeStep;
      failed = true;
      failureReason = error.message;
      if (step != null) {
        steps.add(
          StepRunReport(
            index: step.index,
            label: step.label,
            action: _actionName(step.action),
            status: StepStatus.failed,
            durationMs: activeStepStopwatch?.elapsedMilliseconds ?? 0,
            failureReason: error.message,
          ),
        );
      }
    } finally {
      try {
        await adapter.dispose();
      } on RuntimeOperationException catch (error) {
        if (!failed) {
          failed = true;
          failureReason = error.message;
        }
        // Cleanup is best-effort after a primary Step failure. If cleanup is
        // the only failure, report it as the run-level failure.
      }
    }

    stopwatch.stop();
    final ScenarioRunReport report = ScenarioRunReport(
      scenarioName: scenario.name,
      scenarioDescription: scenario.description,
      status: failed ? ScenarioRunStatus.failed : ScenarioRunStatus.passed,
      startedAt: startedAt,
      durationMs: stopwatch.elapsedMilliseconds,
      steps: steps,
      failureReason: failureReason,
    );
    _writeReport(report);
    return report;
  }

  /// Execute one Step and return its report entry.
  Future<StepRunReport> _executeStep(
    ScenarioStep step,
    Stopwatch stopwatch,
  ) async {
    final String actionName = _actionName(step.action);
    try {
      await _executeAction(step.action);
      stopwatch.stop();
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: actionName,
        status: StepStatus.passed,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on _StepFailureException catch (error) {
      stopwatch.stop();
      return StepRunReport(
        index: step.index,
        label: step.label,
        action: error.actionName,
        status: StepStatus.failed,
        durationMs: stopwatch.elapsedMilliseconds,
        failureReason: error.message,
      );
    }
  }

  /// Return the stable report action name for a Step action.
  String _actionName(StepAction action) {
    return switch (action) {
      TapAction() => 'tap',
      TypeAction() => 'type',
      ScrollAction() => 'scroll',
      WaitForAction() => 'waitFor',
      CaptureAction() => 'capture',
    };
  }

  /// Dispatch one action to the Runtime Adapter.
  Future<String> _executeAction(StepAction action) async {
    return switch (action) {
      TapAction(:final Finder finder) => _withUniqueMatch(
        finder,
        (FinderMatch match) => adapter.performTap(match),
        actionName: 'tap',
      ),
      TypeAction(:final Finder finder, :final String text) => _withUniqueMatch(
        finder,
        (FinderMatch match) => adapter.replaceText(match, text),
        actionName: 'type',
      ),
      ScrollAction(
        :final Finder? finder,
        :final double deltaX,
        :final double deltaY,
      ) =>
        _executeScroll(finder: finder, deltaX: deltaX, deltaY: deltaY),
      WaitForAction(:final Finder finder, :final int timeoutMs) => _waitFor(
        finder,
        timeout: Duration(milliseconds: timeoutMs),
      ),
      CaptureAction(
        :final bool screenshot,
        :final bool snapshot,
        :final bool widgetTree,
        :final bool logs,
      ) =>
        _executeCapture(
          screenshot: screenshot,
          snapshot: snapshot,
          widgetTree: widgetTree,
          logs: logs,
        ),
    };
  }

  /// Resolve `finder`, execute `operation`, and return the action name.
  Future<String> _withUniqueMatch(
    Finder finder,
    Future<void> Function(FinderMatch match) operation, {
    required String actionName,
  }) async {
    final FinderMatch match = await _resolveUniqueMatch(
      finder,
      actionName: actionName,
    );
    await operation(match);
    return actionName;
  }

  /// Resolve a Finder and enforce first-version cardinality rules.
  Future<FinderMatch> _resolveUniqueMatch(
    Finder finder, {
    required String actionName,
  }) async {
    final List<FinderMatch> matches = await adapter.resolveFinder(finder);
    if (matches.isEmpty) {
      throw _StepFailureException(
        actionName: actionName,
        message: 'Finder matched no widgets.',
      );
    }
    if (matches.length > 1) {
      throw _StepFailureException(
        actionName: actionName,
        message: 'Finder matched multiple widgets.',
      );
    }
    return matches.single;
  }

  /// Poll a Finder until it has one unique match or the timeout expires.
  Future<String> _waitFor(Finder finder, {required Duration timeout}) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (true) {
      final List<FinderMatch> matches = await adapter.resolveFinder(finder);
      if (matches.length == 1) {
        return 'waitFor';
      }
      if (matches.length > 1) {
        throw _StepFailureException(
          actionName: 'waitFor',
          message: 'Finder matched multiple widgets.',
        );
      }
      if (stopwatch.elapsed >= timeout) {
        throw _StepFailureException(
          actionName: 'waitFor',
          message: 'Finder matched no widgets before timeout.',
        );
      }
      await Future<void>.delayed(_waitForPollInterval);
    }
  }

  /// Execute a scroll action, resolving its optional Finder when provided.
  Future<String> _executeScroll({
    required Finder? finder,
    required double deltaX,
    required double deltaY,
  }) async {
    FinderMatch? match;
    if (finder != null) {
      match = await _resolveUniqueMatch(finder, actionName: 'scroll');
    }
    await adapter.performScroll(match: match, deltaX: deltaX, deltaY: deltaY);
    return 'scroll';
  }

  /// Execute a capture action without persisting artifacts yet.
  ///
  /// Issue #6 and Issue #7 will write captured payloads through the Artifact
  /// Store. In this runner slice, capture only proves that the configured
  /// Runtime Adapter operations are invoked successfully.
  Future<String> _executeCapture({
    required bool screenshot,
    required bool snapshot,
    required bool widgetTree,
    required bool logs,
  }) async {
    if (screenshot) {
      await adapter.captureScreenshot();
    }
    if (snapshot) {
      await adapter.captureSnapshot();
    }
    if (widgetTree) {
      await adapter.captureWidgetTree();
    }
    if (logs) {
      await adapter.collectLogs();
    }
    return 'capture';
  }

  /// Write the JSON report for this first runner slice.
  void _writeReport(ScenarioRunReport report) {
    outputDirectory.createSync(recursive: true);
    final File reportFile = File('${outputDirectory.path}/run_report.json');
    reportFile.writeAsStringSync(jsonEncode(report.toJson()));
  }
}

/// Overall status for one Scenario run.
enum ScenarioRunStatus { passed, failed }

/// Status for one executed Step.
enum StepStatus { passed, failed, skipped }

/// JSON-serializable report for one Scenario run.
///
/// It contains Scenario metadata, total status and duration, and one ordered
/// entry for every executed Step.
class ScenarioRunReport {
  const ScenarioRunReport({
    required this.scenarioName,
    required this.scenarioDescription,
    required this.status,
    required this.startedAt,
    required this.durationMs,
    required this.steps,
    this.failureReason,
  });

  final String scenarioName;
  final String? scenarioDescription;
  final ScenarioRunStatus status;
  final DateTime startedAt;
  final int durationMs;
  final List<StepRunReport> steps;

  /// Human-readable run-level failure reason.
  final String? failureReason;

  /// Convert this report to the first-version `run_report.json` shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scenario': <String, Object?>{
        'name': scenarioName,
        if (scenarioDescription != null) 'description': scenarioDescription,
      },
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'durationMs': durationMs,
      if (failureReason != null) 'failureReason': failureReason,
      'steps': <Object?>[for (final StepRunReport step in steps) step.toJson()],
    };
  }
}

/// JSON-serializable report entry for one executed Step.
class StepRunReport {
  const StepRunReport({
    required this.index,
    required this.label,
    required this.action,
    required this.status,
    required this.durationMs,
    this.failureReason,
  });

  final int index;
  final String? label;
  final String action;
  final StepStatus status;
  final int durationMs;

  /// Human-readable failure reason when `status` is `failed`.
  final String? failureReason;

  /// Convert this Step entry to the first-version `run_report.json` shape.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      if (label != null) 'label': label,
      'action': action,
      'status': status.name,
      'durationMs': durationMs,
      if (failureReason != null) 'failureReason': failureReason,
    };
  }
}

/// Controlled Step failure that should be recorded in the run report.
class _StepFailureException implements Exception {
  const _StepFailureException({
    required this.actionName,
    required this.message,
  });

  final String actionName;
  final String message;
}
