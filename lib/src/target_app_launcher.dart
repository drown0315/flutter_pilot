/// Launches the Target App Package and discovers its Runtime Target URI.
///
/// This module owns `flutter run --machine` process orchestration. It does not
/// parse Scenarios, resolve Target Devices, run Steps, or control Scenario
/// Recording.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Flutter app launch options supported by Flutter Pilot's `test` flow.
class TargetAppLaunchCommand {
  /// Creates a command for `flutter run --machine`.
  ///
  /// `deviceId`, `flavor`, and `target` are omitted when null. The launcher does
  /// not add debug, pub, VM service port, or timeout flags.
  const TargetAppLaunchCommand({this.deviceId, this.flavor, this.target});

  /// Resolved Target Device id passed to Flutter, when selected.
  final String? deviceId;

  /// Flutter flavor passed through to `flutter run --flavor`.
  final String? flavor;

  /// Flutter app entrypoint file passed through to `flutter run --target`.
  final String? target;

  /// Executable used to launch the Target App Package.
  String get executable => 'flutter';

  /// Arguments passed to the Flutter executable.
  List<String> get arguments {
    return <String>[
      'run',
      '--machine',
      if (deviceId != null) ...<String>['--device-id', deviceId!],
      if (flavor != null) ...<String>['--flavor', flavor!],
      if (target != null) ...<String>['--target', target!],
    ];
  }
}

/// Started Target App process that can be cleaned up after a Scenario run.
class TargetAppLaunch {
  /// Creates a launched Target App handle.
  const TargetAppLaunch({
    required this.runtimeTargetUri,
    required TargetAppProcess process,
  }) : _process = process;

  /// Runtime Target URI extracted from Flutter machine output.
  final Uri runtimeTargetUri;

  final TargetAppProcess _process;

  /// Stop the launched Flutter process.
  ///
  /// The cleanup path first sends Flutter CLI's quit command. If the process
  /// does not exit before `gracePeriod`, it falls back to terminating the
  /// process.
  Future<void> cleanup({
    Duration gracePeriod = const Duration(seconds: 2),
  }) async {
    _process.writeStdin('q\n');
    try {
      await _process.exitCode.timeout(gracePeriod);
    } on TimeoutException {
      _process.kill();
    }
  }
}

/// Failure raised when the Target App Package cannot provide a Runtime Target.
class TargetAppLaunchException implements Exception {
  /// Creates a Target App launch failure.
  const TargetAppLaunchException({
    required this.message,
    this.stderrLines = const <String>[],
  });

  /// Human-readable launch failure.
  final String message;

  /// Buffered Flutter stderr lines, capped to the last 40 lines.
  final List<String> stderrLines;

  @override
  String toString() {
    return message;
  }
}

/// Starts Target App processes.
abstract interface class TargetAppProcessStarter {
  /// Start `executable` with `arguments` in the current Target App Package.
  Future<TargetAppProcess> start(String executable, List<String> arguments);
}

/// Running process contract used by `TargetAppLauncher`.
abstract interface class TargetAppProcess {
  /// Machine stdout emitted by `flutter run --machine`.
  Stream<List<int>> get stdout;

  /// Flutter stderr used for launch diagnostics.
  Stream<List<int>> get stderr;

  /// Process exit code.
  Future<int> get exitCode;

  /// Write text to process stdin.
  void writeStdin(String text);

  /// Terminate the process if graceful cleanup is unavailable.
  bool kill();
}

/// Default process starter backed by `dart:io`.
class IoTargetAppProcessStarter implements TargetAppProcessStarter {
  /// Creates the default process starter.
  const IoTargetAppProcessStarter();

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    final Process process = await Process.start(executable, arguments);
    return _IoTargetAppProcess(process);
  }
}

/// Launches the current Target App Package and waits for its Runtime Target URI.
class TargetAppLauncher {
  /// Creates a Target App launcher.
  const TargetAppLauncher({this.starter = const IoTargetAppProcessStarter()});

  final TargetAppProcessStarter starter;

  /// Start Flutter and return after `app.debugPort.wsUri` is available.
  Future<TargetAppLaunch> launch(TargetAppLaunchCommand command) async {
    final TargetAppProcess process = await starter.start(
      command.executable,
      command.arguments,
    );
    final Completer<TargetAppLaunch> completer = Completer<TargetAppLaunch>();
    final _LastLinesBuffer stderrBuffer = _LastLinesBuffer(limit: 40);
    final StreamSubscription<String> stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          stderrBuffer.add,
          onError: (Object error) {
            // Non-fatal; continue with buffered stderr lines.
          },
        );
    final Future<void> stderrDone = stderrSub.asFuture<void>();
    StreamSubscription<String>? stdoutSub;
    stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (String line) {
            final Uri? runtimeTargetUri = _runtimeTargetUriFromMachineLine(line);
            if (runtimeTargetUri != null && !completer.isCompleted) {
              stdoutSub?.cancel();
              completer.complete(
                TargetAppLaunch(
                  runtimeTargetUri: runtimeTargetUri,
                  process: process,
                ),
              );
            }
          },
          onError: (Object error) {
            stdoutSub?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(
                TargetAppLaunchException(
                  message: 'Error reading Flutter stdout: $error',
                ),
              );
            }
          },
        );
    process.exitCode.then((int exitCode) async {
      await stderrDone;
      if (!completer.isCompleted) {
        completer.completeError(
          TargetAppLaunchException(
            message:
                'Flutter exited before Runtime Target URI was available. Exit code: $exitCode.',
            stderrLines: stderrBuffer.lines,
          ),
        );
      }
    });
    return completer.future;
  }

  /// Extract a Runtime Target URI from one Flutter machine stdout line.
  static Uri? _runtimeTargetUriFromMachineLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return null;
    }
    for (final Map<String, Object?> event in _machineEvents(decoded)) {
      if (event['event'] != 'app.debugPort') {
        continue;
      }
      final Object? params = event['params'];
      if (params is! Map<String, Object?>) {
        continue;
      }
      final Object? wsUri = params['wsUri'];
      if (wsUri is! String || wsUri.isEmpty) {
        continue;
      }
      final Uri uri = Uri.parse(wsUri);
      return uri.isAbsolute ? uri : null;
    }
    return null;
  }

  /// Normalize object-shaped and list-shaped Flutter machine events.
  static Iterable<Map<String, Object?>> _machineEvents(Object? decoded) sync* {
    if (decoded is Map<String, Object?>) {
      yield decoded;
      return;
    }
    if (decoded is List<Object?>) {
      for (final Object? item in decoded) {
        if (item is Map<String, Object?>) {
          yield item;
        }
      }
    }
  }
}

class _IoTargetAppProcess implements TargetAppProcess {
  _IoTargetAppProcess(this._process);

  final Process _process;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void writeStdin(String text) {
    _process.stdin.write(text);
    _process.stdin.flush();
  }

  @override
  bool kill() {
    return _process.kill();
  }
}

class _LastLinesBuffer {
  _LastLinesBuffer({required this.limit});

  final int limit;
  final List<String> _lines = <String>[];

  List<String> get lines => List<String>.unmodifiable(_lines);

  void add(String line) {
    _lines.add(line);
    if (_lines.length > limit) {
      _lines.removeAt(0);
    }
  }
}
