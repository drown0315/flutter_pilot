import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies the public screen_recorder API using an in-memory recording backend.
void main() {
  group('ScreenRecorder', () {
    test('lists Recording Devices from a fake backend', () async {
      final RecordingDevice device = RecordingDevice(
        id: 'device-1',
        name: 'PHK110',
        platform: RecordingDevicePlatform.android,
      );
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[device],
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, <RecordingDevice>[device]);
    });

    test('starts and stops a fake Recording Session with result metadata',
        () async {
      final RecordingDevice device = RecordingDevice(
        id: 'android-1',
        name: 'PHK110',
        platform: RecordingDevicePlatform.android,
      );
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[device],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'login_flow',
      );
      final RecordingResult result = await recorder.stopRecord(session);

      expect(session.device, device);
      expect(session.expectedOutputPath, endsWith('login_flow.mp4'));
      expect(result.session, session);
      expect(result.outputPath, session.expectedOutputPath);
      expect(File(result.outputPath).existsSync(), isTrue);
      expect(result.fileSizeBytes, greaterThan(0));
      expect(result.mimeType, 'video/mp4');
      expect(result.stopTime.isAfter(result.startTime), isTrue);
      expect(result.duration, result.stopTime.difference(result.startTime));
    });

    test('generates an output name when none is provided', () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK',
        outputDirectory: outputDirectory,
      );

      expect(session.expectedOutputPath, startsWith(outputDirectory));
      expect(session.expectedOutputPath, contains('phk110'));
      expect(session.expectedOutputPath, endsWith('.mp4'));

      await recorder.discardRecord(session);
    });

    test('reports device-not-found with a stable error code', () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'missing',
          outputDirectory: outputDirectory,
          outputName: 'missing_device',
        ),
        throwsA(_hasCode(ScreenRecorderErrorCode.deviceNotFound)),
      );
    });

    test('rejects output names with path separators or file extensions',
        () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'nested/login_flow',
        ),
        throwsA(_hasCode(ScreenRecorderErrorCode.invalidOutputName)),
      );
      await expectLater(
        recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'login_flow.mp4',
        ),
        throwsA(_hasCode(ScreenRecorderErrorCode.invalidOutputName)),
      );
    });

    test('fails on existing outputs unless overwrite is explicit', () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;
      File('$outputDirectory${Platform.pathSeparator}login_flow.mp4')
        ..createSync(recursive: true)
        ..writeAsStringSync('existing');

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'PHK110',
          outputDirectory: outputDirectory,
          outputName: 'login_flow',
        ),
        throwsA(_hasCode(ScreenRecorderErrorCode.outputAlreadyExists)),
      );

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'login_flow',
        overwrite: true,
      );
      final RecordingResult result = await recorder.stopRecord(session);

      expect(result.outputPath, endsWith('login_flow.mp4'));
    });

    test('allows parallel sessions on different devices', () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[
          _androidDevice(),
          const RecordingDevice(
            id: 'android-2',
            name: 'Pixel 9',
            platform: RecordingDevicePlatform.android,
          ),
        ],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;

      final RecordingSession firstSession = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'first',
      );
      final RecordingSession secondSession = await recorder.startRecord(
        deviceSelector: 'Pixel 9',
        outputDirectory: outputDirectory,
        outputName: 'second',
      );

      expect(firstSession.device.id, 'android-1');
      expect(secondSession.device.id, 'android-2');

      await recorder.stopRecord(firstSession);
      await recorder.stopRecord(secondSession);
    });

    test('rejects a second active Recording Session for the same device',
        () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;
      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'first',
      );

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'android-1',
          outputDirectory: outputDirectory,
          outputName: 'second',
        ),
        throwsA(_hasCode(ScreenRecorderErrorCode.alreadyRecording)),
      );

      await recorder.stopRecord(session);
    });

    test('discards an active Recording Session without saving a result',
        () async {
      final ScreenRecorder recorder = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;
      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'discarded',
      );

      await recorder.discardRecord(session);

      expect(File(session.expectedOutputPath).existsSync(), isFalse);

      final RecordingSession nextSession = await recorder.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'saved_after_discard',
      );
      final RecordingResult result = await recorder.stopRecord(nextSession);
      expect(result.outputPath, endsWith('saved_after_discard.mp4'));
    });

    test('rejects stopping or discarding a session from another recorder',
        () async {
      final ScreenRecorder owner = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final ScreenRecorder other = ScreenRecorder.fake(
        devices: <RecordingDevice>[_androidDevice()],
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_test_').path;
      final RecordingSession ownerSession = await owner.startRecord(
        deviceSelector: 'PHK110',
        outputDirectory: outputDirectory,
        outputName: 'owned',
      );

      await expectLater(
        other.stopRecord(ownerSession),
        throwsA(_hasCode(ScreenRecorderErrorCode.sessionNotFound)),
      );
      await expectLater(
        other.discardRecord(ownerSession),
        throwsA(_hasCode(ScreenRecorderErrorCode.sessionNotFound)),
      );

      await owner.discardRecord(ownerSession);
    });
  });
}

/// Builds the Android Recording Device reused by lifecycle tests.
RecordingDevice _androidDevice() {
  return const RecordingDevice(
    id: 'android-1',
    name: 'PHK110',
    platform: RecordingDevicePlatform.android,
  );
}

/// Matches a ScreenRecorderException by stable error code.
Matcher _hasCode(ScreenRecorderErrorCode code) {
  return isA<ScreenRecorderException>().having(
    (ScreenRecorderException exception) => exception.code,
    'code',
    code,
  );
}
