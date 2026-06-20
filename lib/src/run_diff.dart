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
/// It contains the run directory paths, warnings, and Step-level findings that
/// a renderer can turn into human-readable or machine-readable output.
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

  final String beforeRunDirectory;
  final String afterRunDirectory;
  final List<String> warnings;
  final List<RunDiffStepFinding> regressions;
  final List<RunDiffStepFinding> resolvedSteps;
  final List<RunDiffStepFinding> missingSteps;
  final List<RunDiffStepFinding> addedSteps;
  final List<RunDiffStepFinding> actionChanges;
}

/// One Step-level Run Diff finding.
///
/// The first slice records a human-readable description only. Later slices can
/// add stable machine-readable fields without changing the CLI command shape.
class RunDiffStepFinding {
  const RunDiffStepFinding({
    required this.stepName,
    required this.description,
    this.failureReason,
  });

  final String stepName;
  final String description;
  final String? failureReason;
}

/// Load Scenario Run reports and compare their Step outcomes.
class RunDiffEngine {
  RunDiffEngine._();

  /// Compare two run directories using their `run_report.json` files.
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
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: passed -> failed (${alignedStep.before.action})',
            failureReason: alignedStep.after.failureReason,
          ),
      for (final _RunReportStep missingStep in alignment.missingBeforeSteps)
        if (missingStep.label != null)
          RunDiffStepFinding(
            stepName: missingStep.name,
            description:
                '${missingStep.name}: missing labeled Step in after run (${missingStep.action})',
          ),
    ];
    final List<RunDiffStepFinding> resolvedSteps = <RunDiffStepFinding>[
      for (final _AlignedRunReportStep alignedStep in alignment.alignedSteps)
        if (alignedStep.before.status == 'failed' &&
            alignedStep.after.status == 'passed')
          RunDiffStepFinding(
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: failed -> passed (${alignedStep.before.action})',
            failureReason: alignedStep.before.failureReason,
          ),
    ];
    final List<RunDiffStepFinding> missingSteps = <RunDiffStepFinding>[
      for (final _RunReportStep missingStep in alignment.missingBeforeSteps)
        if (missingStep.label == null)
          RunDiffStepFinding(
            stepName: missingStep.name,
            description:
                '${missingStep.name}: missing from after run (${missingStep.action})',
          ),
    ];
    final List<RunDiffStepFinding> addedSteps = <RunDiffStepFinding>[
      for (final _RunReportStep addedStep in alignment.addedAfterSteps)
        RunDiffStepFinding(
          stepName: addedStep.name,
          description:
              '${addedStep.name}: added in after run (${addedStep.action})',
        ),
    ];
    final List<RunDiffStepFinding> actionChanges = <RunDiffStepFinding>[
      for (final _AlignedRunReportStep alignedStep in alignment.alignedSteps)
        if (alignedStep.before.action != alignedStep.after.action)
          RunDiffStepFinding(
            stepName: alignedStep.before.name,
            description:
                '${alignedStep.before.name}: ${alignedStep.before.action} -> ${alignedStep.after.action}',
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

  /// Align Steps by Step Label first, then by Step index for unlabeled Steps.
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
    final List<_AlignedRunReportStep> alignedSteps = <_AlignedRunReportStep>[];
    final List<_RunReportStep> missingBeforeSteps = <_RunReportStep>[];
    final Set<_StepKey> consumedAfterKeys = <_StepKey>{};
    for (final _RunReportStep beforeStep in beforeSteps) {
      final _RunReportStep? afterStep = beforeStep.label == null
          ? unlabeledAfterSteps[beforeStep.index]
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

/// Human-readable renderer for the first Run Diff CLI output.
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

  /// Write a titled finding list when the list has content.
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

/// Complete Step alignment result for before and after runs.
class _StepAlignment {
  const _StepAlignment({
    required this.alignedSteps,
    required this.missingBeforeSteps,
    required this.addedAfterSteps,
  });

  final List<_AlignedRunReportStep> alignedSteps;
  final List<_RunReportStep> missingBeforeSteps;
  final List<_RunReportStep> addedAfterSteps;
}

/// Pair of Step reports matched across before and after runs.
class _AlignedRunReportStep {
  const _AlignedRunReportStep({required this.before, required this.after});

  final _RunReportStep before;
  final _RunReportStep after;
}

/// Minimal report data needed by Step outcome Run Diff.
class _RunReport {
  const _RunReport({required this.scenarioName, required this.steps});

  final String scenarioName;
  final List<_RunReportStep> steps;
}

/// Minimal Step report fields used by the first Run Diff slice.
class _RunReportStep {
  const _RunReportStep({
    required this.index,
    required this.label,
    required this.action,
    required this.status,
    required this.failureReason,
  });

  final int index;
  final String? label;
  final String action;
  final String status;
  final String? failureReason;

  String get name => label == null ? 'Step $index' : 'Step $index "$label"';

  _StepKey get key =>
      label == null ? _StepKey.index(index) : _StepKey.label(label!);
}

/// Stable key used to track which after-run Steps were aligned.
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
