import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;

import '../scenario.dart';
import 'recording_contract.dart';

/// Recording Controller backed by the `screen_recorder` package.
///
/// It keeps device-level recording outside the Runtime Adapter and translates
/// `screen_recorder` sessions into Flutter Pilot's narrow recording contract.
class ScreenRecorderRecordingController implements RecordingController {
  ScreenRecorderRecordingController({
    required screen_recorder.ScreenRecorder recorder,
    required this.deviceSelector,
    required this.outputDirectory,
  }) : _recorder = recorder;

  final screen_recorder.ScreenRecorder _recorder;
  final String deviceSelector;
  final Directory outputDirectory;
  screen_recorder.RecordingSession? _session;

  @override
  Future<void> start(Scenario scenario) async {
    try {
      _session = await _recorder.startRecord(
        deviceSelector: deviceSelector,
        outputDirectory: outputDirectory.path,
        outputName: scenario.name,
        overwrite: true,
      );
    } on screen_recorder.ScreenRecorderException catch (error) {
      throw RecordingException(
        operation: RecordingOperation.start,
        message: error.message,
        cause: error,
      );
    }
  }

  @override
  Future<RecordingResult> stop() async {
    final screen_recorder.RecordingSession? session = _session;
    if (session == null) {
      throw const RecordingException(
        operation: RecordingOperation.stop,
        message: 'No active Recording Session exists.',
      );
    }

    try {
      final screen_recorder.RecordingResult result = await _recorder.stopRecord(
        session,
      );
      _session = null;
      return RecordingResult(
        path: p.normalize(result.outputPath),
        mimeType: result.mimeType,
      );
    } on screen_recorder.ScreenRecorderException catch (error) {
      throw RecordingException(
        operation: RecordingOperation.stop,
        message: error.message,
        cause: error,
      );
    }
  }
}
