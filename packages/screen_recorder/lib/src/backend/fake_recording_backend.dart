import 'dart:io';

import '../common/screen_recorder_exception.dart';
import '../model/recording_device.dart';
import '../model/recording_session.dart';
import 'recording_backend.dart';

/// In-memory backend used to drive tests through the public recorder API.

class FakeRecordingBackend implements RecordingBackend {
  FakeRecordingBackend(List<RecordingDevice> devices)
    : _devices = List<RecordingDevice>.unmodifiable(devices);

  final List<RecordingDevice> _devices;

  @override
  RecordingDevicePlatform get platform => RecordingDevicePlatform.android;

  @override
  Future<List<RecordingDevice>> listDevices() async {
    return _devices;
  }

  @override
  Future<RecordingDevice> resolveDevice(String selector) async {
    if (selector.isEmpty) {
      throw const ScreenRecorderException(
        code: ScreenRecorderErrorCode.deviceNotFound,
        message: 'No Recording Device selector was provided.',
      );
    }
    for (final RecordingDevice device in _devices) {
      if (device.id == selector || device.name == selector) {
        return device;
      }
    }
    for (final RecordingDevice device in _devices) {
      if (device.name.toLowerCase().startsWith(selector.toLowerCase())) {
        return device;
      }
    }
    throw ScreenRecorderException(
      code: ScreenRecorderErrorCode.deviceNotFound,
      message: 'No Recording Device matched selector: $selector',
      deviceSelector: selector,
    );
  }

  @override
  Future<void> start(
    RecordingSession session, {
    required bool overwrite,
  }) async {}

  @override
  Future<void> stop(RecordingSession session) async {
    final File outputFile = File(session.expectedOutputPath);
    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsBytesSync(<int>[0, 1, 2, 3]);
  }

  @override
  Future<void> discard(RecordingSession session) async {
    final File outputFile = File(session.expectedOutputPath);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }
  }
}
