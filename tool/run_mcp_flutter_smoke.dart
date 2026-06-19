import 'dart:io';

import 'package:flutter_pilot/src/smoke_verifier.dart';

/// Run the real Flutter Pilot smoke path against a running sample app.
///
/// Usage:
/// `dart run tool/run_mcp_flutter_smoke.dart ws://127.0.0.1:1234/token=/ws`
///
/// The script expects `examples/smoke_app` to already be running in debug mode.
/// It validates the Runtime Target with `flutter-mcp-toolkit`, then runs the
/// smoke Scenario through the Flutter Pilot CLI and verifies the produced
/// `run_report.json` for CI-friendly pass/fail output.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/run_mcp_flutter_smoke.dart <vm-service-ws-uri>',
    );
    exitCode = SmokeVerifierExitCodes.usage;
    return;
  }

  final String target = arguments.single;
  final Directory smokeAppDirectory = Directory('examples/smoke_app');
  if (!smokeAppDirectory.existsSync()) {
    stderr.writeln(
      'Missing examples/smoke_app. Run this script from repo root.',
    );
    exitCode = SmokeVerifierExitCodes.usage;
    return;
  }

  final ProcessResult validationResult =
      await _runProcess('flutter-mcp-toolkit', [
        '--flutter-project-dir',
        smokeAppDirectory.path,
        'validate-runtime',
        '--target',
        target,
        '--timeout-ms',
        '10000',
      ]);
  if (validationResult.exitCode != 0) {
    stderr.writeln(
      'Runtime validation failed with exit code '
      '${validationResult.exitCode}.',
    );
    exitCode = SmokeVerifierExitCodes.runtimeValidationFailed;
    return;
  }

  final ProcessResult runResult =
      await _runProcess(Platform.resolvedExecutable, [
        'run',
        'bin/flutter_pilot.dart',
        'run',
        'examples/smoke_scenario.yaml',
        '--target',
        target,
      ]);
  final String? runReportPath = SmokeRunVerifier.runReportPathFromStdout(
    runResult.stdout.toString(),
  );
  if (runReportPath == null) {
    stderr.writeln('Could not find "Run report:" in Flutter Pilot output.');
    exitCode = SmokeVerifierExitCodes.missingReport;
    return;
  }

  final SmokeVerificationResult verification =
      SmokeRunVerifier.verifyReportFile(File(runReportPath));
  if (!verification.passed) {
    stderr.writeln('Smoke verification failed:');
    for (final String error in verification.errors) {
      stderr.writeln('- $error');
    }
    exitCode = runResult.exitCode == 0
        ? SmokeVerifierExitCodes.reportVerificationFailed
        : SmokeVerifierExitCodes.scenarioRunFailed;
    return;
  }

  if (runResult.exitCode != 0) {
    stderr.writeln(
      'Flutter Pilot run failed with exit code ${runResult.exitCode}.',
    );
    exitCode = SmokeVerifierExitCodes.scenarioRunFailed;
    return;
  }

  stdout.writeln('Smoke verification passed: ${verification.reportPath}');
}

/// Run a child process, then forward its stdout and stderr.
///
/// Args:
/// `executable` is the command to start.
/// `arguments` are passed as separate process arguments.
///
/// Returns:
/// The completed process result so the verifier can inspect stdout.
Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
) async {
  stdout.writeln('\$ $executable ${arguments.join(' ')}');
  final ProcessResult result = await Process.run(executable, arguments);
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  return result;
}
