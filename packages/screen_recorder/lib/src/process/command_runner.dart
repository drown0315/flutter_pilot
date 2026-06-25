import 'dart:io';

/// Host command execution boundary used by recording backends.

class ScreenRecorderCommandResult {
  /// Creates captured output for one completed host command.
  const ScreenRecorderCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Exit code reported by the host command.
  final int exitCode;

  /// Standard output captured as text.
  final String stdout;

  /// Standard error captured as text.
  final String stderr;
}

/// Started host process controlled by a recording backend.

abstract interface class ScreenRecorderProcess {
  /// Terminates the process with the backend's default signal.
  bool kill();

  /// Completes with the process exit code after it exits.
  Future<int> get exitCode;
}

/// Boundary for running host commands and starting long-running processes.

abstract interface class ScreenRecorderCommandRunner {
  /// Runs a host command to completion and captures stdout/stderr.
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  );

  /// Starts a long-running host process for an active Recording Session.
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  );
}

class ProcessCommandRunner implements ScreenRecorderCommandRunner {
  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final ProcessResult result = await Process.run(executable, arguments);
    return ScreenRecorderCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }

  @override
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final Process process = await Process.start(executable, arguments);
    return _DartIoScreenRecorderProcess(process);
  }
}

class _DartIoScreenRecorderProcess implements ScreenRecorderProcess {
  _DartIoScreenRecorderProcess(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill() => _process.kill();
}

/// Backend boundary used by the core recorder to discover Recording Devices.
