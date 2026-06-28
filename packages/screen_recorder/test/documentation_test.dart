import 'dart:io';

import 'package:test/test.dart';

/// Verifies README coverage for the screen_recorder package contract.
void main() {
  test('README documents API, CLI, discovery, prerequisites, smoke, and scope',
      () {
    final String readme = File('README.md').readAsStringSync();

    for (final String expected in <String>[
      'listDevices',
      'startRecord',
      'stopRecord',
      'discardRecord',
      'Press `s`',
      'Press `q`',
      'Android -> iOS Simulator -> physical iOS',
      'platform filter',
      'exact id',
      'case-insensitive name prefix',
      'outputDirectory',
      'outputName',
      '.mp4',
      '.mov',
      'adb',
      'scrcpy',
      'ffmpeg',
      'xcrun simctl',
      'Booted',
      'swiftc',
      'macOS camera permission',
      'Manual Smoke Checklist',
      'Flutter Pilot integration',
      'Scenario YAML video actions',
      'VM service discovery',
    ]) {
      expect(readme, contains(expected));
    }
  });
}
