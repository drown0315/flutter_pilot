import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Failure while loading or comparing Scenario Run reports.
///
/// The CLI renders the message as an execution error. Usage errors, such as
/// passing the wrong number of arguments, are handled by the command parser
/// before the Run Diff engine is called.
class RunDiffException implements Exception {
  const RunDiffException(this.message);

  final String message;
}

/// Structured comparison between two Scenario Runs.
///
/// It contains:
/// - the before and after run directory paths
/// - warnings that do not stop diff generation, such as Scenario name changes
/// - Step findings grouped by Regression, resolved, missing, added, and action
///   change categories
///
/// Renderers use this object for both terminal text and stable JSON output.
class RunDiff {
  const RunDiff({
    required this.beforeRunDirectory,
    required this.afterRunDirectory,
    required this.warnings,
    required this.regressions,
    required this.resolvedSteps,
    required this.missingSteps,
    required this.addedSteps,
    required this.actionChanges,
  });

  /// Baseline Scenario Run directory used as the before side of the diff.
  final String beforeRunDirectory;

  /// Scenario Run directory compared against the baseline.
  final String afterRunDirectory;

  /// Non-fatal comparison warnings that should be visible to users and tools.
  final List<String> warnings;

  /// Step findings that represent worse after-run behavior.
  final List<RunDiffStepFinding> regressions;

  /// Step findings that represent failed before-run behavior now passing.
  final List<RunDiffStepFinding> resolvedSteps;

  /// Unlabeled before-run Steps that were not found in the after run.
  final List<RunDiffStepFinding> missingSteps;

  /// After-run Steps that were not matched by any before-run Step.
  final List<RunDiffStepFinding> addedSteps;

  /// Matched Steps whose action changed between before and after runs.
  final List<RunDiffStepFinding> actionChanges;

  /// Return the overall Run Diff classification for automation and CI.
  ///
  /// The priority order is:
  /// - `regressed` when any Regression exists
  /// - `improved` when resolved Steps exist and there are no Regressions
  /// - `changed` when only neutral findings or warnings exist
  /// - `unchanged` when there are no findings or warnings
  String get outcome {
    if (regressions.isNotEmpty) {
      return 'regressed';
    }
    if (resolvedSteps.isNotEmpty) {
      return 'improved';
    }
    if (warnings.isNotEmpty ||
        missingSteps.isNotEmpty ||
        addedSteps.isNotEmpty ||
        actionChanges.isNotEmpty) {
      return 'changed';
    }
    return 'unchanged';
  }
}

/// One Step-level Run Diff finding.
///
/// It carries:
/// - `kind`, a stable machine-readable change type such as `statusChanged`
/// - `description`, a compact sentence for terminal output
/// - optional before and after Step identities for JSON consumers
/// - the failure reason that explains a Step Regression or resolved failure
class RunDiffStepFinding {
  const RunDiffStepFinding({
    required this.kind,
    required this.stepName,
    required this.description,
    required this.before,
    required this.after,
    this.failureReason,
  });

  /// Stable change type for JSON consumers, such as `missing` or `added`.
  final String kind;

  /// Human-readable Step name based on index and optional Step Label.
  final String stepName;

  /// Compact explanation used in the text renderer.
  final String description;

  /// Before-run Step identity, or `null` for after-only added Steps.
  final RunDiffStepIdentity? before;

  /// After-run Step identity, or `null` for before-only missing Steps.
  final RunDiffStepIdentity? after;

  /// Failure reason attached to a Step Regression or resolved Step.
  final String? failureReason;
}

/// Stable Step identity exposed in machine-readable Run Diff output.
///
/// It mirrors the Step fields from `run_report.json` that let tools locate and
/// explain a changed Step: index, optional Step Label, action, status, and
/// optional failure reason.
///
/// Example:
/// Step 2 labeled `submit` with action `tap` and status `failed` identifies
/// the same timeline entry a reviewer sees in the HTML report.
class RunDiffStepIdentity {
  const RunDiffStepIdentity({
    required this.index,
    required this.label,
    required this.action,
    required this.status,
    required this.failureReason,
  });

  /// 1-based Step index from `run_report.json`.
  final int index;

  /// Optional Step Label used for preferred Step alignment.
  final String? label;

  /// Scenario action name recorded for this Step, such as `tap` or `waitFor`.
  final String action;

  /// Step execution status recorded in the run report.
  final String status;

  /// Optional failure explanation recorded when the Step failed.
  final String? failureReason;

  /// Convert the Step identity to the stable JSON object shape.
  ///
  /// Returns:
  /// A map with `index`, nullable `label`, `action`, and `status`. The
  /// `failureReason` key is included only when the run report recorded one.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      'label': label,
      'action': action,
      'status': status,
      if (failureReason != null) 'failureReason': failureReason,
    };
  }
}

/// Load Scenario Run reports and compare their Step outcomes.
class RunDiffEngine {
  RunDiffEngine._();

  /// Compare two run directories using their `run_report.json` files.
  ///
  /// This method:
  /// 1. loads the minimal report fields needed for Step outcome comparison
  /// 2. records non-fatal warnings such as Scenario name differences
  /// 3. aligns before and after Steps by Step Label or Step index
  /// 4. groups Step differences into renderer-ready finding lists
  ///
  /// Args:
  /// `beforeRunDirectory` is the baseline Scenario Run directory.
  /// `afterRunDirectory` is the Scenario Run directory being compared against
  /// the baseline.
  ///
  /// Returns:
  /// A `RunDiff` with warnings and Step findings.
  ///
  /// Throws:
  /// `RunDiffException` when either directory or report cannot be loaded.
  static RunDiff diffDirectories({
    required Directory beforeRunDirectory,
    required Directory afterRunDirectory,
  }) {
    final _RunReport beforeReport = _RunReportLoader.load(beforeRunDirectory);
    final _RunReport afterReport = _RunReportLoader.load(afterRunDirectory);
    final List<String> warnings = <String>[];
    if (beforeReport.scenarioName != afterReport.scenarioName) {
      warnings.add(
        'Scenario names differ: ${beforeReport.scenarioName} vs ${afterReport.scenarioName}.',
      );
    }
    final _StepAlignment alignment = _alignSteps(
      beforeReport.steps,
      afterReport.steps,
    );
    final List<RunDiffStepFinding> regressions = <RunDiffStepFinding>[
      for (final _AlignedRunReportStep alignedStep in alignment.alignedSteps)
        if (alignedStep.before.status == 'passed' &&
            alignedStep.after.status == 'failed')
          RunDiffStepFinding(
            kind: 'statusChanged',
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: passed -> failed (${alignedStep.before.action})',
            before: alignedStep.before.identity,
            after: alignedStep.after.identity,
            failureReason: alignedStep.after.failureReason,
          ),
      for (final _RunReportStep missingStep in alignment.missingBeforeSteps)
        if (missingStep.label != null)
          RunDiffStepFinding(
            kind: 'missing',
            stepName: missingStep.name,
            description:
                '${missingStep.name}: missing labeled Step in after run (${missingStep.action})',
            before: missingStep.identity,
            after: null,
          ),
    ];
    final List<RunDiffStepFinding> resolvedSteps = <RunDiffStepFinding>[
      for (final _AlignedRunReportStep alignedStep in alignment.alignedSteps)
        if (alignedStep.before.status == 'failed' &&
            alignedStep.after.status == 'passed')
          RunDiffStepFinding(
            kind: 'statusChanged',
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: failed -> passed (${alignedStep.before.action})',
            before: alignedStep.before.identity,
            after: alignedStep.after.identity,
            failureReason: alignedStep.before.failureReason,
          ),
    ];
    final List<RunDiffStepFinding> missingSteps = <RunDiffStepFinding>[
      for (final _RunReportStep missingStep in alignment.missingBeforeSteps)
        if (missingStep.label == null)
          RunDiffStepFinding(
            kind: 'missing',
            stepName: missingStep.name,
            description:
                '${missingStep.name}: missing from after run (${missingStep.action})',
            before: missingStep.identity,
            after: null,
          ),
    ];
    final List<RunDiffStepFinding> addedSteps = <RunDiffStepFinding>[
      for (final _RunReportStep addedStep in alignment.addedAfterSteps)
        RunDiffStepFinding(
          kind: 'added',
          stepName: addedStep.name,
          description:
              '${addedStep.name}: added in after run (${addedStep.action})',
          before: null,
          after: addedStep.identity,
        ),
    ];
    final List<RunDiffStepFinding> actionChanges = <RunDiffStepFinding>[
      for (final _AlignedRunReportStep alignedStep in alignment.alignedSteps)
        if (alignedStep.before.action != alignedStep.after.action)
          RunDiffStepFinding(
            kind: 'actionChanged',
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: ${alignedStep.before.action} -> ${alignedStep.after.action}',
            before: alignedStep.before.identity,
            after: alignedStep.after.identity,
          ),
    ];
    return RunDiff(
      beforeRunDirectory: beforeRunDirectory.path,
      afterRunDirectory: afterRunDirectory.path,
      warnings: warnings,
      regressions: regressions,
      resolvedSteps: resolvedSteps,
      missingSteps: missingSteps,
      addedSteps: addedSteps,
      actionChanges: actionChanges,
    );
  }

  /// Align before-run Steps to after-run Steps.
  ///
  /// A labeled before Step matches by Step Label so inserted Steps do not make
  /// later labeled Steps look unrelated. An unlabeled before Step falls back to
  /// Step index, and that index fallback can match an after Step even when the
  /// after Step has gained a label.
  ///
  /// Args:
  /// `beforeSteps` are the baseline Steps that drive missing-Step detection.
  /// `afterSteps` are the comparison Steps used for matches and added-Step
  /// detection.
  ///
  /// Returns:
  /// Matched Step pairs, before Steps with no match, and after Steps that were
  /// not consumed by any match.
  static _StepAlignment _alignSteps(
    List<_RunReportStep> beforeSteps,
    List<_RunReportStep> afterSteps,
  ) {
    final Map<String, _RunReportStep> labeledAfterSteps =
        <String, _RunReportStep>{
          for (final _RunReportStep step in afterSteps)
            if (step.label != null) step.label!: step,
        };
    final Map<int, _RunReportStep> unlabeledAfterSteps = <int, _RunReportStep>{
      for (final _RunReportStep step in afterSteps)
        if (step.label == null) step.index: step,
    };
    final Map<int, _RunReportStep> afterStepsByIndex = <int, _RunReportStep>{
      for (final _RunReportStep step in afterSteps) step.index: step,
    };
    final List<_AlignedRunReportStep> alignedSteps = <_AlignedRunReportStep>[];
    final List<_RunReportStep> missingBeforeSteps = <_RunReportStep>[];
    final Set<_StepKey> consumedAfterKeys = <_StepKey>{};
    for (final _RunReportStep beforeStep in beforeSteps) {
      final _RunReportStep? afterStep = beforeStep.label == null
          ? unlabeledAfterSteps[beforeStep.index] ??
                afterStepsByIndex[beforeStep.index]
          : labeledAfterSteps[beforeStep.label];
      if (afterStep != null) {
        consumedAfterKeys.add(afterStep.key);
        alignedSteps.add(
          _AlignedRunReportStep(before: beforeStep, after: afterStep),
        );
      } else {
        missingBeforeSteps.add(beforeStep);
      }
    }
    final List<_RunReportStep> addedAfterSteps = <_RunReportStep>[
      for (final _RunReportStep afterStep in afterSteps)
        if (!consumedAfterKeys.contains(afterStep.key)) afterStep,
    ];
    return _StepAlignment(
      alignedSteps: alignedSteps,
      missingBeforeSteps: missingBeforeSteps,
      addedAfterSteps: addedAfterSteps,
    );
  }
}

/// Human-readable renderer for terminal Run Diff output.
///
/// It prints run paths, warning lines, and grouped Step finding sections. The
/// text renderer intentionally keeps the same content order as the JSON
/// renderer so CLI users and automation see the same categories.
class RunDiffTextRenderer {
  RunDiffTextRenderer._();

  /// Render a compact human-readable Run Diff.
  ///
  /// Args:
  /// `diff` is the structured Run Diff from `RunDiffEngine`.
  ///
  /// Returns:
  /// Text suitable for terminal stdout.
  static String render(RunDiff diff) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Run Diff')
      ..writeln('Before: ${diff.beforeRunDirectory}')
      ..writeln('After: ${diff.afterRunDirectory}');
    if (diff.warnings.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Warnings:');
      for (final String warning in diff.warnings) {
        buffer.writeln('- $warning');
      }
    }
    buffer.writeln();
    if (diff.regressions.isEmpty &&
        diff.resolvedSteps.isEmpty &&
        diff.missingSteps.isEmpty &&
        diff.addedSteps.isEmpty &&
        diff.actionChanges.isEmpty) {
      buffer.writeln('No Step outcome changes.');
    } else {
      _writeFindings(buffer, 'Regressions:', diff.regressions);
      _writeFindings(buffer, 'Resolved Steps:', diff.resolvedSteps);
      _writeFindings(buffer, 'Missing Steps:', diff.missingSteps);
      _writeFindings(buffer, 'Added Steps:', diff.addedSteps);
      _writeFindings(buffer, 'Action Changes:', diff.actionChanges);
    }
    return buffer.toString().trimRight();
  }

  /// Write one titled finding section when the section has content.
  ///
  /// Args:
  /// `buffer` receives terminal lines.
  /// `title` is the section heading, such as `Regressions:`.
  /// `findings` are the Step findings rendered under that heading.
  static void _writeFindings(
    StringBuffer buffer,
    String title,
    List<RunDiffStepFinding> findings,
  ) {
    if (findings.isEmpty) {
      return;
    }
    buffer.writeln(title);
    for (final RunDiffStepFinding finding in findings) {
      buffer.writeln('- ${finding.description}');
      if (finding.failureReason != null) {
        buffer.writeln('  Reason: ${finding.failureReason}');
      }
    }
  }
}

/// Machine-readable renderer for Run Diff automation output.
///
/// It emits a single JSON object with stable top-level keys for run paths,
/// outcome, warnings, and grouped Step findings. Each finding contains a
/// stable `kind`, terminal `description`, and nullable before/after Step
/// identity objects.
class RunDiffJsonRenderer {
  RunDiffJsonRenderer._();

  /// Render a stable JSON object for agents, CI, and downstream tooling.
  ///
  /// Args:
  /// `diff` is the structured Run Diff from `RunDiffEngine`.
  ///
  /// Returns:
  /// Pretty-printed JSON with this top-level shape:
  /// `beforeRunDirectory`, `afterRunDirectory`, `outcome`, `warnings`,
  /// `regressions`, `resolvedSteps`, `missingSteps`, `addedSteps`, and
  /// `actionChanges`.
  static String render(RunDiff diff) {
    final Map<String, Object?> payload = <String, Object?>{
      'beforeRunDirectory': diff.beforeRunDirectory,
      'afterRunDirectory': diff.afterRunDirectory,
      'outcome': diff.outcome,
      'warnings': diff.warnings,
      'regressions': _findingsToJson(diff.regressions),
      'resolvedSteps': _findingsToJson(diff.resolvedSteps),
      'missingSteps': _findingsToJson(diff.missingSteps),
      'addedSteps': _findingsToJson(diff.addedSteps),
      'actionChanges': _findingsToJson(diff.actionChanges),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Convert Step findings to the stable JSON object shape.
  ///
  /// Returns:
  /// A list of finding objects. Each object contains `kind`, `description`,
  /// `stepName`, nullable `before`, nullable `after`, and `failureReason` only
  /// when present.
  static List<Map<String, Object?>> _findingsToJson(
    List<RunDiffStepFinding> findings,
  ) {
    return <Map<String, Object?>>[
      for (final RunDiffStepFinding finding in findings)
        <String, Object?>{
          'kind': finding.kind,
          'description': finding.description,
          'stepName': finding.stepName,
          'before': finding.before?.toJson(),
          'after': finding.after?.toJson(),
          if (finding.failureReason != null)
            'failureReason': finding.failureReason,
        },
    ];
  }
}

/// Complete Step alignment result for before and after runs.
///
/// `alignedSteps` contains matched before/after pairs. `missingBeforeSteps`
/// contains before Steps that had no after match. `addedAfterSteps` contains
/// after Steps that no before Step consumed.
class _StepAlignment {
  const _StepAlignment({
    required this.alignedSteps,
    required this.missingBeforeSteps,
    required this.addedAfterSteps,
  });

  /// Matched before/after Step pairs used for status and action comparison.
  final List<_AlignedRunReportStep> alignedSteps;

  /// Before-run Steps with no matching after-run Step.
  final List<_RunReportStep> missingBeforeSteps;

  /// After-run Steps that were not consumed by any before-run match.
  final List<_RunReportStep> addedAfterSteps;
}

/// Pair of Step reports matched across before and after runs.
///
/// A pair can be matched by Step Label or by Step index depending on the before
/// Step's available identity.
class _AlignedRunReportStep {
  const _AlignedRunReportStep({required this.before, required this.after});

  /// Baseline Step from the before run.
  final _RunReportStep before;

  /// Matching Step from the after run.
  final _RunReportStep after;
}

/// Minimal report data needed by Step outcome Run Diff.
///
/// It contains the Scenario name used for warnings and the Step list used for
/// alignment. Other run report fields are intentionally ignored by this Step
/// outcome slice.
class _RunReport {
  const _RunReport({required this.scenarioName, required this.steps});

  /// Scenario name from `run_report.json`, used for mismatch warnings.
  final String scenarioName;

  /// Step reports in timeline order.
  final List<_RunReportStep> steps;
}

/// Minimal Step report fields used by the Step outcome diff.
///
/// The Step index and optional Step Label identify the Step for alignment and
/// output. Action, status, and failure reason explain what changed after
/// alignment succeeds.
class _RunReportStep {
  const _RunReportStep({
    required this.index,
    required this.label,
    required this.action,
    required this.status,
    required this.failureReason,
  });

  /// 1-based Step index recorded by the Scenario Runner.
  final int index;

  /// Optional Step Label used for preferred alignment when present.
  final String? label;

  /// Scenario action name recorded in the run report.
  final String action;

  /// Step execution status, such as `passed` or `failed`.
  final String status;

  /// Failure explanation recorded by the runner when the Step failed.
  final String? failureReason;

  String get name => label == null ? 'Step $index' : 'Step $index "$label"';

  _StepKey get key =>
      label == null ? _StepKey.index(index) : _StepKey.label(label!);

  RunDiffStepIdentity get identity => RunDiffStepIdentity(
    index: index,
    label: label,
    action: action,
    status: status,
    failureReason: failureReason,
  );
}

/// Stable key used to track which after-run Steps were aligned.
///
/// A labeled Step uses `label:<label>` and an unlabeled Step uses
/// `index:<index>`. The key is only for consumed-after tracking; matching rules
/// still live in `_alignSteps`.
class _StepKey {
  const _StepKey._({required this.value});

  factory _StepKey.index(int index) => _StepKey._(value: 'index:$index');

  factory _StepKey.label(String label) => _StepKey._(value: 'label:$label');

  final String value;

  @override
  bool operator ==(Object other) {
    return other is _StepKey && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

/// Loader for the stable `run_report.json` artifact.
class _RunReportLoader {
  _RunReportLoader._();

  /// Load and validate the minimal report shape needed by Run Diff.
  static _RunReport load(Directory runDirectory) {
    if (!runDirectory.existsSync()) {
      throw RunDiffException(
        'Run directory does not exist: ${runDirectory.path}',
      );
    }
    final File reportFile = File(p.join(runDirectory.path, 'run_report.json'));
    if (!reportFile.existsSync()) {
      throw RunDiffException(
        'Missing run_report.json in run directory: ${runDirectory.path}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(reportFile.readAsStringSync());
    } on FormatException catch (error) {
      throw RunDiffException(
        'Malformed run_report.json in ${runDirectory.path}: ${error.message}',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw RunDiffException(
        'Unsupported run_report.json shape in ${runDirectory.path}: expected an object.',
      );
    }
    final Object? scenario = decoded['scenario'];
    if (scenario is! Map<String, Object?> || scenario['name'] is! String) {
      throw RunDiffException(
        'Unsupported run_report.json shape in ${runDirectory.path}: missing scenario.name.',
      );
    }
    final Object? steps = decoded['steps'];
    if (steps is! List<Object?>) {
      throw RunDiffException(
        'Unsupported run_report.json shape in ${runDirectory.path}: missing steps list.',
      );
    }
    return _RunReport(
      scenarioName: scenario['name'] as String,
      steps: <_RunReportStep>[
        for (int stepIndex = 0; stepIndex < steps.length; stepIndex++)
          _readStep(steps[stepIndex], stepIndex, runDirectory.path),
      ],
    );
  }

  /// Parse one Step report object from `run_report.json`.
  static _RunReportStep _readStep(
    Object? step,
    int stepIndex,
    String runDirectoryPath,
  ) {
    if (step is! Map<String, Object?>) {
      throw RunDiffException(
        'Unsupported run_report.json shape in $runDirectoryPath: steps[$stepIndex] must be an object.',
      );
    }
    if (step['index'] is! int ||
        step['action'] is! String ||
        step['status'] is! String) {
      throw RunDiffException(
        'Unsupported run_report.json shape in $runDirectoryPath: steps[$stepIndex] is missing index, action, or status.',
      );
    }
    final Object? label = step['label'];
    final Object? failureReason = step['failureReason'];
    if (label != null && label is! String) {
      throw RunDiffException(
        'Unsupported run_report.json shape in $runDirectoryPath: steps[$stepIndex].label must be a string when present.',
      );
    }
    if (failureReason != null && failureReason is! String) {
      throw RunDiffException(
        'Unsupported run_report.json shape in $runDirectoryPath: steps[$stepIndex].failureReason must be a string when present.',
      );
    }
    return _RunReportStep(
      index: step['index'] as int,
      label: label as String?,
      action: step['action'] as String,
      status: step['status'] as String,
      failureReason: failureReason as String?,
    );
  }
}
