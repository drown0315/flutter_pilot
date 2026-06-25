import 'dart:async';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies the interactive CLI through fake input and a fake recorder.
void main() {
  group('ScreenRecorderCli', () {
    test('pressing s stops and prints the saved recording path', () async {
      final RecordingDevice device = _device();
      final ScreenRecorderCli cli = ScreenRecorderCli(
        recorder: ScreenRecorder.fake(devices: <RecordingDevice>[device]),
        input: Stream<List<int>>.fromIterable(<List<int>>[
          <int>['s'.codeUnitAt(0)],
        ]),
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_cli_test_').path;
      final StringBuffer stdout = StringBuffer();
      final StringBuffer stderr = StringBuffer();

      final int exitCode = await cli.run(
        <String>[
          '--device',
          'PHK110',
          '--output-directory',
          outputDirectory,
          '--output-name',
          'cli_recording',
        ],
        stdout: stdout,
        stderr: stderr,
      );

      expect(exitCode, 0);
      expect(
        stdout.toString(),
        contains('Starting recording for PHK110...'),
      );
      expect(
        stdout.toString(),
        contains('Recording PHK110. Press s to save, q to discard.'),
      );
      expect(
        stdout.toString(),
        contains('Saved recording: $outputDirectory/cli_recording.mp4'),
      );
      expect(stderr.toString(), isEmpty);
    });

    test('pressing q discards without printing a saved recording', () async {
      final RecordingDevice device = _device();
      final ScreenRecorderCli cli = ScreenRecorderCli(
        recorder: ScreenRecorder.fake(devices: <RecordingDevice>[device]),
        input: Stream<List<int>>.fromIterable(<List<int>>[
          <int>['q'.codeUnitAt(0)],
        ]),
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_cli_test_').path;
      final StringBuffer stdout = StringBuffer();
      final StringBuffer stderr = StringBuffer();

      final int exitCode = await cli.run(
        <String>[
          '--device',
          'PHK110',
          '--output-directory',
          outputDirectory,
          '--output-name',
          'discarded_recording',
        ],
        stdout: stdout,
        stderr: stderr,
      );

      expect(exitCode, 0);
      expect(stdout.toString(), isNot(contains('Saved recording:')));
      expect(stderr.toString(), isEmpty);
      expect(
        File('$outputDirectory/discarded_recording.mp4').existsSync(),
        isFalse,
      );
    });

    test('renders ScreenRecorderException codes for argument failures',
        () async {
      final ScreenRecorderCli cli = ScreenRecorderCli(
        recorder: ScreenRecorder.fake(devices: <RecordingDevice>[_device()]),
        input: Stream<List<int>>.empty(),
      );
      final String outputDirectory =
          Directory.systemTemp.createTempSync('screen_recorder_cli_test_').path;
      final StringBuffer stdout = StringBuffer();
      final StringBuffer stderr = StringBuffer();

      final int exitCode = await cli.run(
        <String>[
          '--device',
          'PHK110',
          '--output-directory',
          outputDirectory,
          '--output-name',
          'bad.mp4',
        ],
        stdout: stdout,
        stderr: stderr,
      );

      expect(exitCode, 64);
      expect(stdout.toString(), isEmpty);
      expect(stderr.toString(), contains('invalidOutputName:'));
    });
  });
}

RecordingDevice _device() {
  return const RecordingDevice(
    id: 'android-1',
    name: 'PHK110',
    platform: RecordingDevicePlatform.android,
  );
}
