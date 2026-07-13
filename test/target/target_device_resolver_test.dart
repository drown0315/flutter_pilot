import 'dart:convert';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies Target Device selection without invoking Flutter tooling.
///
/// These tests exercise the resolver with parsed Flutter Device records and
/// fake Recording Device data so command code can fail before app launch when
/// device selection is invalid.
void main() {
  group('TargetDeviceResolver', () {
    test(
      'returns null when no selector is provided and recording is not required',
      () {
        final ResolvedTargetDevice? device = TargetDeviceResolver.resolve(
          selector: null,
          recordingRequired: false,
          flutterDevices: const <FlutterDevice>[],
          recordingDevices: const <RecordingDeviceIdentity>[],
        );

        expect(device, isNull);
      },
    );

    test('resolves a selector by id, exact name, or unique prefix', () {
      const List<FlutterDevice> devices = <FlutterDevice>[
        FlutterDevice(
          id: 'emulator-5554',
          name: 'Pixel 8',
          targetPlatform: 'android-arm64',
          isSupported: true,
          emulator: true,
          sdk: 'Android 35',
        ),
        FlutterDevice(
          id: '00008110-001C2D',
          name: 'Drown iPhone',
          targetPlatform: 'ios',
          isSupported: true,
          emulator: false,
          sdk: 'iOS 18.5',
        ),
      ];

      final ResolvedTargetDevice byId = TargetDeviceResolver.resolve(
        selector: 'emulator-5554',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;
      final ResolvedTargetDevice byName = TargetDeviceResolver.resolve(
        selector: 'Drown iPhone',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;
      final ResolvedTargetDevice byPrefix = TargetDeviceResolver.resolve(
        selector: 'Pixel',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;

      expect(byId.targetDevice.id, 'emulator-5554');
      expect(byName.targetDevice.id, '00008110-001C2D');
      expect(byPrefix.targetDevice.name, 'Pixel 8');
      expect(byId.recordingDevice, isNull);
    });

    test('rejects empty, ambiguous, unsupported, and missing selectors', () {
      const List<FlutterDevice> devices = <FlutterDevice>[
        FlutterDevice(
          id: 'pixel-8',
          name: 'Pixel 8',
          targetPlatform: 'android-arm64',
          isSupported: true,
          emulator: true,
          sdk: 'Android 35',
        ),
        FlutterDevice(
          id: 'pixel-8-pro',
          name: 'Pixel 8 Pro',
          targetPlatform: 'android-arm64',
          isSupported: true,
          emulator: true,
          sdk: 'Android 35',
        ),
        FlutterDevice(
          id: 'chrome',
          name: 'Chrome',
          targetPlatform: 'web-javascript',
          isSupported: false,
          emulator: false,
          sdk: 'Google Chrome',
        ),
      ];

      expect(
        () => TargetDeviceResolver.resolve(
          selector: '  ',
          recordingRequired: false,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            contains('Target Device selector must not be empty.'),
          ),
        ),
      );
      expect(
        () => TargetDeviceResolver.resolve(
          selector: 'Pixel',
          recordingRequired: false,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            allOf(contains('ambiguous Target Device'), contains('pixel-8')),
          ),
        ),
      );
      expect(
        () => TargetDeviceResolver.resolve(
          selector: 'chrome',
          recordingRequired: false,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            contains('unsupported Target Device'),
          ),
        ),
      );
      expect(
        () => TargetDeviceResolver.resolve(
          selector: 'iPhone',
          recordingRequired: false,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[],
        ),
        throwsA(isA<TargetDeviceResolutionException>()),
      );
    });

    test('pairs a Recording Device by exact id before exact name', () {
      const List<FlutterDevice> devices = <FlutterDevice>[
        FlutterDevice(
          id: 'pixel-8',
          name: 'Pixel 8',
          targetPlatform: 'android-arm64',
          isSupported: true,
          emulator: true,
          sdk: 'Android 35',
        ),
        FlutterDevice(
          id: 'iphone-15',
          name: 'iPhone 15',
          targetPlatform: 'ios',
          isSupported: true,
          emulator: true,
          sdk: 'iOS 18.5',
        ),
      ];

      final ResolvedTargetDevice selected = TargetDeviceResolver.resolve(
        selector: 'Pixel 8',
        recordingRequired: true,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[
          RecordingDeviceIdentity(id: 'pixel-8', name: 'Wrong name'),
          RecordingDeviceIdentity(id: 'other-id', name: 'Pixel 8'),
        ],
      )!;

      expect(selected.targetDevice.id, 'pixel-8');
      expect(selected.recordingDevice?.id, 'pixel-8');
    });

    test('pairs a Recording Device by a unique exact name', () {
      const FlutterDevice flutterDevice = FlutterDevice(
        id: '00008110-001C2D',
        name: 'Drown iPhone',
        targetPlatform: 'ios',
        isSupported: true,
        emulator: false,
        sdk: 'iOS 18.5',
      );

      final ResolvedTargetDevice selected = TargetDeviceResolver.resolve(
        selector: flutterDevice.id,
        recordingRequired: true,
        flutterDevices: const <FlutterDevice>[flutterDevice],
        recordingDevices: const <RecordingDeviceIdentity>[
          RecordingDeviceIdentity(
            id: 'screen-recorder-ios-id',
            name: 'Drown iPhone',
          ),
        ],
      )!;

      expect(selected.targetDevice.id, flutterDevice.id);
      expect(selected.recordingDevice?.id, 'screen-recorder-ios-id');
      expect(selected.recordingDevice?.name, 'Drown iPhone');
    });

    test('rejects duplicate exact Recording Device names as ambiguous', () {
      expect(
        () => TargetDeviceResolver.resolve(
          selector: 'Drown iPhone',
          recordingRequired: true,
          flutterDevices: const <FlutterDevice>[
            FlutterDevice(
              id: 'flutter-ios-id',
              name: 'Drown iPhone',
              targetPlatform: 'ios',
              isSupported: true,
              emulator: false,
              sdk: 'iOS 18.5',
            ),
          ],
          recordingDevices: const <RecordingDeviceIdentity>[
            RecordingDeviceIdentity(id: 'recorder-1', name: 'Drown iPhone'),
            RecordingDeviceIdentity(id: 'recorder-2', name: 'Drown iPhone'),
          ],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            contains('ambiguous Recording Device'),
          ),
        ),
      );
    });

    test('rejects an unmatched recording-required Target Device', () {
      expect(
        () => TargetDeviceResolver.resolve(
          selector: 'iphone-15',
          recordingRequired: true,
          flutterDevices: const <FlutterDevice>[
            FlutterDevice(
              id: 'iphone-15',
              name: 'iPhone 15',
              targetPlatform: 'ios',
              isSupported: true,
              emulator: true,
              sdk: 'iOS 18.5',
            ),
          ],
          recordingDevices: const <RecordingDeviceIdentity>[
            RecordingDeviceIdentity(id: 'other', name: 'Other iPhone'),
          ],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            contains('is not available as a Recording Device'),
          ),
        ),
      );
    });

    test('auto-selects only one recordable supported Flutter Device', () {
      const List<FlutterDevice> devices = <FlutterDevice>[
        FlutterDevice(
          id: 'pixel-8',
          name: 'Pixel 8',
          targetPlatform: 'android-arm64',
          isSupported: true,
          emulator: true,
          sdk: 'Android 35',
        ),
        FlutterDevice(
          id: 'iphone-15',
          name: 'iPhone 15',
          targetPlatform: 'ios',
          isSupported: true,
          emulator: true,
          sdk: 'iOS 18.5',
        ),
        FlutterDevice(
          id: 'macos',
          name: 'macOS',
          targetPlatform: 'darwin',
          isSupported: false,
          emulator: false,
          sdk: 'macOS 15',
        ),
      ];

      final ResolvedTargetDevice selected = TargetDeviceResolver.resolve(
        selector: null,
        recordingRequired: true,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[
          RecordingDeviceIdentity(id: 'iphone-15', name: 'iPhone 15'),
          RecordingDeviceIdentity(id: 'macos', name: 'macOS'),
        ],
      )!;

      expect(selected.targetDevice.id, 'iphone-15');
      expect(selected.recordingDevice?.id, 'iphone-15');
      expect(
        () => TargetDeviceResolver.resolve(
          selector: null,
          recordingRequired: true,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            contains('No recordable Target Device'),
          ),
        ),
      );
      expect(
        () => TargetDeviceResolver.resolve(
          selector: null,
          recordingRequired: true,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[
            RecordingDeviceIdentity(id: 'pixel-8', name: 'Pixel 8'),
            RecordingDeviceIdentity(id: 'iphone-15', name: 'iPhone 15'),
          ],
        ),
        throwsA(
          isA<TargetDeviceResolutionException>().having(
            (TargetDeviceResolutionException error) => error.message,
            'message',
            allOf(
              contains('Multiple recordable Target Devices'),
              contains('pixel-8'),
              contains('iphone-15'),
            ),
          ),
        ),
      );
    });

    test('parses Flutter devices machine output', () {
      final List<FlutterDevice> devices = TargetDeviceParser.parseMachineJson(
        jsonEncode(<Object?>[
          <String, Object?>{
            'id': 'emulator-5554',
            'name': 'Pixel 8',
            'targetPlatform': 'android-arm64',
            'emulator': true,
            'sdk': 'Android 35',
            'isSupported': true,
          },
          <String, Object?>{
            'id': 'chrome',
            'name': 'Chrome',
            'targetPlatform': 'web-javascript',
            'emulator': false,
            'sdk': 'Google Chrome',
            'isSupported': false,
          },
        ]),
      );

      expect(devices, hasLength(2));
      expect(devices.first.id, 'emulator-5554');
      expect(devices.first.name, 'Pixel 8');
      expect(devices.first.targetPlatform, 'android-arm64');
      expect(devices.first.emulator, isTrue);
      expect(devices.first.sdk, 'Android 35');
      expect(devices.first.isSupported, isTrue);
      expect(devices.last.isSupported, isFalse);
    });
  });
}
