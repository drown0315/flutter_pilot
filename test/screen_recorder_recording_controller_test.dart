import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;
import 'package:test/test.dart';

/// Verifies Flutter Pilot's integration boundary for the screen_recorder
/// package without requiring a real device.
void main() {
  test('starts and stops a screen_recorder Recording Session', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('screen_recording_output');
      final ScreenRecorderRecordingController controller =
          ScreenRecorderRecordingController(
            recorder: screen_recorder.ScreenRecorder.fake(
              devices: const <screen_recorder.RecordingDevice>[
                screen_recorder.RecordingDevice(
                  id: 'device-1',
                  name: 'Pixel 8',
                  platform: screen_recorder.RecordingDevicePlatform.android,
                ),
              ],
            ),
            deviceSelector: 'Pixel',
            outputDirectory: outputDirectory,
          );

      await controller.start(
        const Scenario(name: 'recorded_run', steps: <ScenarioStep>[]),
      );
      final RecordingResult result = await controller.stop();

      expect(result.path, endsWith('recorded_run.mp4'));
      expect(result.mimeType, 'video/mp4');
      expect(File(result.path).existsSync(), isTrue);
    });
  });

  test('normalizes screen_recorder startup failures', () async {
    await FileTestkit.runZoned(() async {
      final ScreenRecorderRecordingController controller =
          ScreenRecorderRecordingController(
            recorder: screen_recorder.ScreenRecorder.fake(),
            deviceSelector: 'missing-device',
            outputDirectory: Directory('screen_recording_output'),
          );

      expect(
        () => controller.start(
          const Scenario(name: 'recorded_run', steps: <ScenarioStep>[]),
        ),
        throwsA(
          isA<RecordingException>().having(
            (RecordingException error) => error.operation,
            'operation',
            RecordingOperation.start,
          ),
        ),
      );
    });
  });
}
