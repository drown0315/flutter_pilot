import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';

/// Demonstrates the programmatic screen_recorder API with the fake backend.
Future<void> main() async {
  final RecordingDevice device = RecordingDevice(
    id: 'android-1',
    name: 'PHK110',
    platform: RecordingDevicePlatform.android,
  );
  final ScreenRecorder recorder = ScreenRecorder.fake(
    devices: <RecordingDevice>[device],
  );
  final Directory outputDirectory = Directory.systemTemp.createTempSync(
    'screen_recorder_example_',
  );

  final RecordingSession session = await recorder.startRecord(
    deviceSelector: 'PHK',
    outputDirectory: outputDirectory.path,
    outputName: 'example_recording',
  );
  final RecordingResult result = await recorder.stopRecord(session);

  assert(result.outputPath.endsWith('example_recording.mp4'));
  assert(result.fileSizeBytes > 0);
}
