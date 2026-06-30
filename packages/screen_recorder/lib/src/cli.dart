import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:args/args.dart';

import 'screen_recorder_base.dart';
import 'service/screen_recorder_service.dart';

/// Thin interactive CLI wrapper around the `ScreenRecorder` core API.
///
/// The CLI starts one foreground Recording Session, waits for a single key, and
/// delegates save or discard behavior to the recorder. It does not implement
/// backend-specific recording behavior itself.
class ScreenRecorderCli {
  /// Creates an interactive CLI.
  ///
  /// `recorder` defaults to the multi-backend recorder. Tests can inject a fake
  /// recorder and input stream to avoid real devices and terminal interaction.
  ScreenRecorderCli({ScreenRecorder? recorder, Stream<List<int>>? input})
    : _recorder = recorder ?? ScreenRecorder.defaultRecorder(),
      _input = input ?? io.stdin,
      _usesTerminalInput = input == null;

  final ScreenRecorder _recorder;
  final Stream<List<int>> _input;
  final bool _usesTerminalInput;

  /// Runs the CLI with parsed command-line arguments.
  ///
  /// Returns `0` on saved or discarded recordings and `64` for usage or
  /// recorder errors. `stdout` and `stderr` are injectable for tests.
  Future<int> run(
    List<String> arguments, {
    StringSink? stdout,
    StringSink? stderr,
  }) async {
    final StringSink out = stdout ?? io.stdout;
    final StringSink err = stderr ?? io.stderr;
    final ArgParser parser = _buildParser();
    final bool restoreTerminalModes =
        _usesTerminalInput && io.stdin.hasTerminal;
    bool previousLineMode = false;
    bool previousEchoMode = false;
    bool shouldRestoreLineMode = false;
    bool shouldRestoreEchoMode = false;
    try {
      if (restoreTerminalModes) {
        previousLineMode = _readLineMode();
        previousEchoMode = _readEchoMode();
        shouldRestoreLineMode = _trySetLineMode(false);
        shouldRestoreEchoMode = _trySetEchoMode(false);
      }
      final ArgResults results = parser.parse(arguments);
      final String? deviceSelector = results.option('device');
      final String outputDirectory =
          results.option('output-directory') ?? io.Directory.current.path;
      final String? outputName = results.option('output-name');
      if (deviceSelector == null || deviceSelector.isEmpty) {
        err.writeln('Missing required --device option.');
        return 64;
      }
      ScreenRecorderService.validateOutputName(outputName);

      out.writeln('Starting recording for $deviceSelector...');
      final RecordingSession session = await _recorder.startRecord(
        deviceSelector: deviceSelector,
        outputDirectory: outputDirectory,
        outputName: outputName,
      );
      out.writeln(
        'Recording ${session.device.name}. Press s to save, q to discard.',
      );
      final String command = await _readCommand();
      if (command == 's') {
        final RecordingResult result = await _recorder.stopRecord(session);
        out.writeln('Saved recording: ${result.outputPath}');
        return 0;
      }
      if (command == 'q') {
        await _recorder.discardRecord(session);
        return 0;
      }
      await _recorder.discardRecord(session);
      err.writeln('Unknown command: $command');
      return 64;
    } on ScreenRecorderException catch (error) {
      err.writeln('${error.code.name}: ${error.message}');
      final String? rawOutput = error.rawOutput;
      if (rawOutput != null && rawOutput.trim().isNotEmpty) {
        err.writeln(rawOutput.trim());
      }
      return 64;
    } on FormatException catch (error) {
      err.writeln(error.message);
      return 64;
    } finally {
      if (restoreTerminalModes) {
        if (shouldRestoreEchoMode) {
          _trySetEchoMode(previousEchoMode);
        }
        if (shouldRestoreLineMode) {
          _trySetLineMode(previousLineMode);
        }
      }
    }
  }

  static ArgParser _buildParser() {
    return ArgParser()
      ..addOption(
        'device',
        help: 'Recording Device id, exact name, or name prefix.',
      )
      ..addOption(
        'output-directory',
        help: 'Directory where the saved recording will be written.',
      )
      ..addOption('output-name', help: 'Output file name without extension.');
  }

  Future<String> _readCommand() async {
    await for (final List<int> bytes in _input) {
      final String text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) {
        return text.substring(0, 1);
      }
    }
    return 'q';
  }

  static bool _trySetEchoMode(bool enabled) {
    try {
      io.stdin.echoMode = enabled;
      return true;
    } on io.StdinException {
      return false;
    }
  }

  static bool _trySetLineMode(bool enabled) {
    try {
      io.stdin.lineMode = enabled;
      return true;
    } on io.StdinException {
      return false;
    }
  }

  static bool _readEchoMode() {
    try {
      return io.stdin.echoMode;
    } on io.StdinException {
      return true;
    }
  }

  static bool _readLineMode() {
    try {
      return io.stdin.lineMode;
    } on io.StdinException {
      return true;
    }
  }
}
