import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Extract the VM service websocket URI from `flutter run --machine` output.
///
/// Usage:
/// `dart run tool/extract_flutter_machine_ws_uri.dart machine.log \
///   --timeout-seconds 90`
///
/// The script prints a GitHub Actions output line:
/// `vm_service_uri=<ws-uri>`.
Future<void> main(List<String> arguments) async {
  final _Arguments? parsedArguments = _Arguments.parse(arguments);
  if (parsedArguments == null) {
    stderr.writeln(
      'Usage: dart run tool/extract_flutter_machine_ws_uri.dart '
      '<machine-log> [--timeout-seconds <seconds>]',
    );
    exitCode = 64;
    return;
  }

  final File logFile = File(parsedArguments.logPath);
  final DateTime deadline = DateTime.now().add(parsedArguments.timeout);
  while (DateTime.now().isBefore(deadline)) {
    final String? uri = _readVmServiceUri(logFile);
    if (uri != null) {
      stdout.writeln('vm_service_uri=$uri');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  stderr.writeln(
    'Timed out waiting for app.debugPort.wsUri in ${logFile.path}.',
  );
  exitCode = 1;
}

/// Parsed command-line arguments for the machine log extractor.
class _Arguments {
  const _Arguments({required this.logPath, required this.timeout});

  final String logPath;
  final Duration timeout;

  /// Parse the log path and optional timeout.
  static _Arguments? parse(List<String> arguments) {
    if (arguments.isEmpty) {
      return null;
    }
    final String logPath = arguments.first;
    var timeout = const Duration(seconds: 90);
    for (var index = 1; index < arguments.length; index++) {
      final String argument = arguments[index];
      if (argument != '--timeout-seconds') {
        return null;
      }
      if (index + 1 >= arguments.length) {
        return null;
      }
      final int? seconds = int.tryParse(arguments[index + 1]);
      if (seconds == null || seconds <= 0) {
        return null;
      }
      timeout = Duration(seconds: seconds);
      index++;
    }
    return _Arguments(logPath: logPath, timeout: timeout);
  }
}

/// Return the first `app.debugPort.wsUri` found in a Flutter machine log.
String? _readVmServiceUri(File logFile) {
  if (!logFile.existsSync()) {
    return null;
  }
  final List<String> lines = logFile.readAsLinesSync();
  for (final String line in lines) {
    final String? uri = _debugPortUriFromLine(line);
    if (uri != null) {
      return uri;
    }
  }
  return null;
}

/// Return `wsUri` when a line is an `app.debugPort` machine event.
String? _debugPortUriFromLine(String line) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  if (decoded['event'] != 'app.debugPort') {
    return null;
  }
  final Object? params = decoded['params'];
  if (params is! Map<String, Object?>) {
    return null;
  }
  final Object? wsUri = params['wsUri'];
  return wsUri is String && wsUri.isNotEmpty ? wsUri : null;
}
