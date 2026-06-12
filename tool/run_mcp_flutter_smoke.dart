import 'dart:io';

/// Run the real Flutter Pilot smoke path against a running sample app.
///
/// Usage:
/// `dart run tool/run_mcp_flutter_smoke.dart ws://127.0.0.1:1234/token=/ws`
///
/// The script expects `examples/smoke_app` to already be running in debug mode.
/// It validates the Runtime Target with `flutter-mcp-toolkit`, then runs the
/// smoke Scenario through the Flutter Pilot CLI.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/run_mcp_flutter_smoke.dart <vm-service-ws-uri>',
    );
    exitCode = 64;
    return;
  }

  final String target = arguments.single;
  final Directory smokeAppDirectory = Directory('examples/smoke_app');
  if (!smokeAppDirectory.existsSync()) {
    stderr.writeln(
      'Missing examples/smoke_app. Run this script from repo root.',
    );
    exitCode = 64;
    return;
  }

  final int validationExitCode = await _runProcess('flutter-mcp-toolkit', [
    '--flutter-project-dir',
    smokeAppDirectory.path,
    'validate-runtime',
    '--target',
    target,
    '--timeout-ms',
    '10000',
  ]);
  if (validationExitCode != 0) {
    stderr.writeln(
      'Warning: validate-runtime exited with $validationExitCode; '
      'continuing so Flutter Pilot can still write a run report.',
    );
  }

  final int runExitCode = await _runProcess(Platform.resolvedExecutable, [
    'run',
    'bin/flutter_pilot.dart',
    'run',
    'examples/smoke_scenario.yaml',
    '--target',
    target,
  ]);
  exitCode = runExitCode == 0 ? validationExitCode : runExitCode;
}

/// Run a child process and forward its stdout and stderr to this process.
Future<int> _runProcess(String executable, List<String> arguments) async {
  stdout.writeln('\$ $executable ${arguments.join(' ')}');
  final Process process = await Process.start(executable, arguments);
  await stdout.addStream(process.stdout);
  await stderr.addStream(process.stderr);
  return process.exitCode;
}
