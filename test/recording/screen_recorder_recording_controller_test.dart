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

  test(
    'prepares before starting a screen_recorder Recording Session',
    () async {
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

        await controller.prepare();
        await controller.start(
          const Scenario(name: 'prepared_run', steps: <ScenarioStep>[]),
        );
        final RecordingResult result = await controller.stop();
        await controller.dispose();
        await controller.dispose();

        expect(result.path, endsWith('prepared_run.mp4'));
        expect(result.mimeType, 'video/mp4');
        expect(File(result.path).existsSync(), isTrue);
      });
    },
  );

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

  test('keeps prepared capture retryable when disposal fails', () async {
    await FileTestkit.runZoned(() async {
      final _DisposeFailingScreenRecorder recorder =
          _DisposeFailingScreenRecorder();
      final ScreenRecorderRecordingController controller =
          ScreenRecorderRecordingController(
            recorder: recorder,
            deviceSelector: 'Pixel',
            outputDirectory: Directory('screen_recording_output'),
          );

      await controller.prepare();
      await expectLater(
        controller.dispose(),
        throwsA(
          isA<RecordingException>().having(
            (RecordingException error) => error.operation,
            'operation',
            RecordingOperation.dispose,
          ),
        ),
      );

      recorder.disposeShouldFail = false;
      await controller.dispose();

      expect(recorder.disposeCount, 2);
    });
  });
}

class _DisposeFailingScreenRecorder implements screen_recorder.ScreenRecorder {
  final screen_recorder.PreparedCapture _capture =
      screen_recorder.PreparedCapture(
        id: 'capture-1',
        device: const screen_recorder.RecordingDevice(
          id: 'device-1',
          name: 'Pixel 8',
          platform: screen_recorder.RecordingDevicePlatform.android,
        ),
      );

  bool disposeShouldFail = true;
  int disposeCount = 0;

  @override
  Future<List<screen_recorder.RecordingDevice>> listDevices() async {
    return <screen_recorder.RecordingDevice>[_capture.device];
  }

  @override
  Future<screen_recorder.PreparedCapture> prepare({
    required String deviceSelector,
  }) async {
    return _capture;
  }

  @override
  Future<screen_recorder.RecordingSession> startRecord({
    String? deviceSelector,
    screen_recorder.PreparedCapture? preparedCapture,
    required String outputDirectory,
    String? outputName,
    bool overwrite = false,
  }) async {
    return screen_recorder.RecordingSession(
      id: 'recording-1',
      device: _capture.device,
      startTime: DateTime.utc(2026, 7, 13),
      expectedOutputPath: '$outputDirectory/$outputName.mp4',
    );
  }

  @override
  Future<screen_recorder.RecordingResult> stopRecord(
    screen_recorder.RecordingSession session,
  ) async {
    return screen_recorder.RecordingResult(
      session: session,
      outputPath: session.expectedOutputPath,
      startTime: session.startTime,
      stopTime: session.startTime,
      duration: Duration.zero,
      fileSizeBytes: 0,
      mimeType: 'video/mp4',
    );
  }

  @override
  Future<void> discardRecord(screen_recorder.RecordingSession session) async {}

  @override
  Future<void> dispose(screen_recorder.PreparedCapture capture) async {
    disposeCount++;
    if (disposeShouldFail) {
      throw const screen_recorder.ScreenRecorderException(
        code: screen_recorder.ScreenRecorderErrorCode.discardFailed,
        message: 'Dispose failed.',
      );
    }
  }
}
