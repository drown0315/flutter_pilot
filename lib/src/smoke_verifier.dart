import 'dart:convert';
import 'dart:io';

/// Exit codes used by the real Runtime Adapter smoke verifier.
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
/// A passed report where every required smoke Step passed has an empty
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
/// - the Finder Steps in `examples/smoke_app/smoke_scenario.yaml` passed
/// - the explicit capture Step passed and wrote the default capture bundle
class SmokeRunVerifier {
  SmokeRunVerifier._();

  static const String runReportPrefix = 'Run report:';
  static const String _captureStepLabel = 'capture_error';
  static const Set<String> _finderStepLabels = <String>{
    'wait_for_smoke_form',
    'enter_email',
    'submit_form',
    'wait_for_error',
  };
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

  /// Check one `run_report.json` file and its required smoke Steps.
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
    _verifyCaptureStep(steps, errors);
    _verifyCaptureArtifacts(decoded, errors);

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

  /// Verify the smoke Scenario Step that exercises capture artifact writing.
  static void _verifyCaptureStep(
    List<Map<String, Object?>> steps,
    List<String> errors,
  ) {
    final Map<String, Object?>? step = _stepByLabel(steps, _captureStepLabel);
    if (step == null) {
      errors.add('Missing capture Step: $_captureStepLabel.');
      return;
    }
    if (step['status'] != 'passed') {
      errors.add(
        'Expected capture Step $_captureStepLabel to pass, got '
        '${step['status']}.',
      );
    }
  }

  /// Verify that the explicit capture Step wrote the default artifact bundle.
  static void _verifyCaptureArtifacts(
    Map<String, Object?> report,
    List<String> errors,
  ) {
    final Object? artifacts = report['artifacts'];
    if (artifacts is! List<Object?>) {
      errors.add('Expected run report artifacts to be a list.');
      return;
    }

    final Set<String> captureArtifactTypes = <String>{};
    for (final Object? artifact in artifacts) {
      if (artifact is! Map<String, Object?>) {
        continue;
      }
      if (artifact['purpose'] != 'capture') {
        continue;
      }
      final Object? type = artifact['type'];
      if (type is String) {
        captureArtifactTypes.add(type);
      }
    }

    for (final String requiredType in _requiredCaptureArtifactTypes) {
      if (!captureArtifactTypes.contains(requiredType)) {
        errors.add('Missing capture artifact type: $requiredType.');
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
}
