import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart' as screen_recorder;

import 'target_device.dart';
import '../execution/test_command_models.dart';

/// Discovers Flutter Devices and Recording Devices for `test`.
abstract interface class TestDeviceDiscovery {
  /// Return Flutter Devices from `flutter devices --machine`.
  Future<List<FlutterDevice>> listFlutterDevices();

  /// Return Recording Device identities available for Scenario Recording.
  Future<List<RecordingDeviceIdentity>> listRecordingDevices();
}

/// Default device discovery backed by Flutter CLI and `screen_recorder`.
class DefaultTestDeviceDiscovery implements TestDeviceDiscovery {
  /// Creates default Target Device discovery.
  const DefaultTestDeviceDiscovery();

  @override
  Future<List<FlutterDevice>> listFlutterDevices() async {
    final ProcessResult result;
    try {
      result = await Process.run('flutter', <String>['devices', '--machine']);
    } on ProcessException catch (error) {
      throw DeviceDiscoveryException(error.message);
    }
    if (result.exitCode != 0) {
      throw DeviceDiscoveryException(result.stderr.toString());
    }
    try {
      return TargetDeviceParser.parseMachineJson(result.stdout.toString());
    } on FormatException catch (e) {
      throw DeviceDiscoveryException(e.message);
    }
  }

  @override
  Future<List<RecordingDeviceIdentity>> listRecordingDevices() async {
    final screen_recorder.ScreenRecorder recorder =
        screen_recorder.ScreenRecorder.defaultRecorder();
    final List<screen_recorder.RecordingDevice> devices = await recorder
        .listDevices();
    return <RecordingDeviceIdentity>[
      for (final screen_recorder.RecordingDevice device in devices)
        RecordingDeviceIdentity(id: device.id, name: device.name),
    ];
  }
}
