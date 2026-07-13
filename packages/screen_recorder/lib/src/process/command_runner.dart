import 'dart:async';
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

  /// Text stdout emitted by the process as individual lines.
  ///
  /// Backends use this stream for long-running helper protocols that signal
  /// readiness before the process exits. The complete stdout remains available
  /// through [stdout] for diagnostics.
  Stream<String> get stdoutLines;

  /// Writes one protocol line to the process stdin.
  void writeLine(String line);

  /// Closes stdin after all protocol commands have been written.
  Future<void> closeStdin();
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
      : _stderr = utf8.decodeStream(_process.stderr) {
    _process.stdout.transform(utf8.decoder).listen(
          _handleStdoutChunk,
          onError: _handleStdoutError,
          onDone: _handleStdoutDone,
        );
  }

  final Process _process;
  final Completer<String> _stdout = Completer<String>();
  final Future<String> _stderr;
  final StreamController<String> _stdoutLines = StreamController<String>();
  final StringBuffer _stdoutBuffer = StringBuffer();
  String _pendingStdoutLine = '';

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<String> get stdout => _stdout.future;

  @override
  Future<String> get stderr => _stderr;

  @override
  Stream<String> get stdoutLines => _stdoutLines.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process.kill(signal);
  }

  @override
  void writeLine(String line) {
    _process.stdin.writeln(line);
  }

  @override
  Future<void> closeStdin() async {
    await _process.stdin.close();
  }

  void _handleStdoutChunk(String chunk) {
    _stdoutBuffer.write(chunk);
    _pendingStdoutLine += chunk;
    int newlineIndex = _pendingStdoutLine.indexOf('\n');
    while (newlineIndex != -1) {
      String line = _pendingStdoutLine.substring(0, newlineIndex);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      _stdoutLines.add(line);
      _pendingStdoutLine = _pendingStdoutLine.substring(newlineIndex + 1);
      newlineIndex = _pendingStdoutLine.indexOf('\n');
    }
  }

  void _handleStdoutError(Object error, StackTrace stackTrace) {
    if (!_stdout.isCompleted) {
      _stdout.completeError(error, stackTrace);
    }
    _stdoutLines.addError(error, stackTrace);
    unawaited(_stdoutLines.close());
  }

  void _handleStdoutDone() {
    if (_pendingStdoutLine.isNotEmpty) {
      _stdoutLines.add(_pendingStdoutLine);
      _pendingStdoutLine = '';
    }
    if (!_stdout.isCompleted) {
      _stdout.complete(_stdoutBuffer.toString());
    }
    unawaited(_stdoutLines.close());
  }
}
