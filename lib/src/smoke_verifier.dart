import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Exit codes used by the real `mcp_flutter` smoke verifier.
///
/// These codes keep CI failures distinguishable:
/// - `usage`: invalid verifier invocation
/// - `runtimeValidationFailed`: the Runtime Target failed toolkit validation
/// - `scenarioRunFailed`: Flutter Pilot could not run the smoke Scenario
/// - `missingReport`: the verifier could not locate `run_report.json`
/// - `reportVerificationFailed`: the report exists but does not satisfy the
///   smoke contract
class SmokeVerifierExitCodes {
  SmokeVerifierExitCodes._();

  static const int usage = 64;
  static const int runtimeValidationFailed = 70;
  static const int scenarioRunFailed = 1;
  static const int missingReport = 66;
  static const int reportVerificationFailed = 65;
}

/// Result from checking one smoke `run_report.json`.
///
/// It contains:
/// - `reportPath`: the report file that was checked
/// - `errors`: every contract failure found in the report or artifacts
///
/// Example:
/// A passed report with screenshot, Widget Tree, and Logs artifacts has an empty
/// `errors` list.
class SmokeVerificationResult {
  const SmokeVerificationResult({
    required this.reportPath,
    required this.errors,
  });

  final String reportPath;
  final List<String> errors;

  bool get passed => errors.isEmpty;
}

/// Verifier for the real Runtime Target smoke Scenario output.
///
/// It reads the `run_report.json` written by `flutter_pilot test` and checks the
/// current real Finder integration contract:
/// - the run status is `passed`
/// - the Finder Steps in `examples/smoke_scenario.yaml` passed
/// - the capture Step lists screenshot, Widget Tree, and Logs artifacts
/// - each required artifact path exists under the run directory
class SmokeRunVerifier {
  SmokeRunVerifier._();

  static const String runReportPrefix = 'Run report:';
  static const Set<String> _finderStepLabels = <String>{
    'enter_email',
    'submit_form',
    'wait_for_error',
  };
  static const String _captureStepLabel = 'capture_runtime';
  static const Set<String> _requiredCaptureArtifactTypes = <String>{
    'screenshot',
    'widgetTree',
    'logs',
  };

  /// Return the report path printed by `flutter_pilot test`.
  ///
  /// Args:
  /// `stdoutText` is the complete stdout emitted by the Flutter Pilot CLI.
  ///
  /// Returns:
  /// The path after `Run report:`, or `null` when stdout does not include that
  /// line.
  static String? runReportPathFromStdout(String stdoutText) {
    final List<String> lines = const LineSplitter().convert(stdoutText);
    for (final String line in lines) {
      if (!line.startsWith(runReportPrefix)) {
        continue;
      }
      final String path = line.substring(runReportPrefix.length).trim();
      return path.isEmpty ? null : path;
    }
    return null;
  }

  /// Check one `run_report.json` file and its referenced capture artifacts.
  ///
  /// Args:
  /// `reportFile` points to the report produced by the smoke Scenario run.
  ///
  /// Returns:
  /// A `SmokeVerificationResult` containing all discovered failures. Missing or
  /// malformed files are reported as verification errors instead of throwing.
  static SmokeVerificationResult verifyReportFile(File reportFile) {
    final List<String> errors = <String>[];
    if (!reportFile.existsSync()) {
      return SmokeVerificationResult(
        reportPath: reportFile.path,
        errors: <String>['Missing run report: ${reportFile.path}'],
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(reportFile.readAsStringSync());
    } on FormatException catch (error) {
      return SmokeVerificationResult(
        reportPath: reportFile.path,
        errors: <String>['Invalid run report JSON: ${error.message}'],
      );
    } on FileSystemException catch (error) {
      return SmokeVerificationResult(
        reportPath: reportFile.path,
        errors: <String>['Could not read run report: ${error.message}'],
      );
    }

    if (decoded is! Map<String, Object?>) {
      return SmokeVerificationResult(
        reportPath: reportFile.path,
        errors: <String>['Expected run report to be a JSON object.'],
      );
    }

    _verifyRunStatus(decoded, errors);
    final List<Map<String, Object?>> steps = _reportSteps(decoded, errors);
    _verifyFinderSteps(steps, errors);
    _verifyCaptureArtifacts(
      steps: steps,
      runDirectory: reportFile.parent,
      errors: errors,
    );

    return SmokeVerificationResult(reportPath: reportFile.path, errors: errors);
  }

  /// Add an error unless the run-level status is `passed`.
  static void _verifyRunStatus(
    Map<String, Object?> report,
    List<String> errors,
  ) {
    if (report['status'] != 'passed') {
      errors.add('Expected run status passed, got ${report['status']}.');
    }
  }

  /// Return Step report objects from the report.
  static List<Map<String, Object?>> _reportSteps(
    Map<String, Object?> report,
    List<String> errors,
  ) {
    final Object? steps = report['steps'];
    if (steps is! List<Object?>) {
      errors.add('Expected run report steps to be a list.');
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      for (final Object? step in steps)
        if (step is Map<String, Object?>) step,
    ];
  }

  /// Verify the smoke Scenario Steps that exercise Finder mappings.
  static void _verifyFinderSteps(
    List<Map<String, Object?>> steps,
    List<String> errors,
  ) {
    for (final String label in _finderStepLabels) {
      final Map<String, Object?>? step = _stepByLabel(steps, label);
      if (step == null) {
        errors.add('Missing Finder Step: $label.');
        continue;
      }
      if (step['status'] != 'passed') {
        errors.add(
          'Expected Finder Step $label to pass, got ${step['status']}.',
        );
      }
    }
  }

  /// Verify capture Step artifacts are listed and present on disk.
  static void _verifyCaptureArtifacts({
    required List<Map<String, Object?>> steps,
    required Directory runDirectory,
    required List<String> errors,
  }) {
    final Map<String, Object?>? captureStep = _stepByLabel(
      steps,
      _captureStepLabel,
    );
    if (captureStep == null) {
      errors.add('Missing capture Step: $_captureStepLabel.');
      return;
    }
    if (captureStep['status'] != 'passed') {
      errors.add(
        'Expected capture Step $_captureStepLabel to pass, '
        'got ${captureStep['status']}.',
      );
    }

    final Object? rawArtifacts = captureStep['artifacts'];
    if (rawArtifacts is! List<Object?>) {
      errors.add('Expected capture Step artifacts to be a list.');
      return;
    }
    final List<Map<String, Object?>> artifacts = <Map<String, Object?>>[
      for (final Object? artifact in rawArtifacts)
        if (artifact is Map<String, Object?>) artifact,
    ];

    for (final String requiredType in _requiredCaptureArtifactTypes) {
      final Map<String, Object?>? artifact = _artifactByType(
        artifacts,
        requiredType,
      );
      if (artifact == null) {
        errors.add('Missing capture artifact type: $requiredType.');
        continue;
      }
      final Object? relativePath = artifact['path'];
      if (relativePath is! String || relativePath.isEmpty) {
        errors.add('Capture artifact $requiredType has no path.');
        continue;
      }
      final File artifactFile = File(p.join(runDirectory.path, relativePath));
      if (!artifactFile.existsSync()) {
        errors.add(
          'Missing capture artifact file for $requiredType: '
          '${artifactFile.path}',
        );
      }
    }
  }

  /// Return the Step with the requested label.
  static Map<String, Object?>? _stepByLabel(
    List<Map<String, Object?>> steps,
    String label,
  ) {
    for (final Map<String, Object?> step in steps) {
      if (step['label'] == label) {
        return step;
      }
    }
    return null;
  }

  /// Return the artifact with the requested type.
  static Map<String, Object?>? _artifactByType(
    List<Map<String, Object?>> artifacts,
    String type,
  ) {
    for (final Map<String, Object?> artifact in artifacts) {
      if (artifact['type'] == type) {
        return artifact;
      }
    }
    return null;
  }
}
