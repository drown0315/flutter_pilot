import 'dart:convert';
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

/// Captured output for commands whose stdout is binary data.
class ScreenRecorderByteCommandResult {
  /// Creates captured binary stdout and text stderr for one completed command.
  const ScreenRecorderByteCommandResult({
    required this.exitCode,
    required this.stdoutBytes,
    required this.stderr,
  });

  /// Exit code reported by the host command.
  final int exitCode;

  /// Raw standard output bytes captured from the command.
  final List<int> stdoutBytes;

  /// Standard error captured as text.
  final String stderr;
}

/// Started host process controlled by a recording backend.

abstract interface class ScreenRecorderProcess {
  /// Terminates the process with the requested signal.
  ///
  /// Backends use the default signal for most host processes. Android
  /// `screenrecord` uses `sigint` so the device-side recorder can finalize the
  /// mp4 before the file is pulled from the device.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);

  /// Completes with the process exit code after it exits.
  Future<int> get exitCode;

  /// Captured stdout emitted before the process exits.
  Future<String> get stdout;

  /// Captured stderr emitted before the process exits.
  Future<String> get stderr;
}

/// Boundary for running host commands and starting long-running processes.

abstract interface class ScreenRecorderCommandRunner {
  /// Runs a host command to completion and captures stdout/stderr.
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  );

  /// Runs a host command to completion and captures raw stdout bytes.
  Future<ScreenRecorderByteCommandResult> runBytes(
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
  Future<ScreenRecorderByteCommandResult> runBytes(
    String executable,
    List<String> arguments,
  ) async {
    final ProcessResult result = await Process.run(
      executable,
      arguments,
      stdoutEncoding: null,
    );
    return ScreenRecorderByteCommandResult(
      exitCode: result.exitCode,
      stdoutBytes: result.stdout as List<int>,
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
  _DartIoScreenRecorderProcess(this._process)
      : _stdout = utf8.decodeStream(_process.stdout),
        _stderr = utf8.decodeStream(_process.stderr);

  final Process _process;
  final Future<String> _stdout;
  final Future<String> _stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<String> get stdout => _stdout;

  @override
  Future<String> get stderr => _stderr;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }
}
