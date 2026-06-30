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
        final TargetDevice? device = TargetDeviceResolver.resolve(
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

      final TargetDevice byId = TargetDeviceResolver.resolve(
        selector: 'emulator-5554',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;
      final TargetDevice byName = TargetDeviceResolver.resolve(
        selector: 'Drown iPhone',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;
      final TargetDevice byPrefix = TargetDeviceResolver.resolve(
        selector: 'Pixel',
        recordingRequired: false,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[],
      )!;

      expect(byId.id, 'emulator-5554');
      expect(byName.id, '00008110-001C2D');
      expect(byPrefix.name, 'Pixel 8');
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

    test(
      'requires recording devices to match the resolved Flutter Device id',
      () {
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

        final TargetDevice selected = TargetDeviceResolver.resolve(
          selector: 'Pixel 8',
          recordingRequired: true,
          flutterDevices: devices,
          recordingDevices: const <RecordingDeviceIdentity>[
            RecordingDeviceIdentity(id: 'pixel-8'),
          ],
        )!;

        expect(selected.id, 'pixel-8');
        expect(
          () => TargetDeviceResolver.resolve(
            selector: 'iPhone 15',
            recordingRequired: true,
            flutterDevices: devices,
            recordingDevices: const <RecordingDeviceIdentity>[
              RecordingDeviceIdentity(id: 'Pixel 8'),
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
      },
    );

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

      final TargetDevice selected = TargetDeviceResolver.resolve(
        selector: null,
        recordingRequired: true,
        flutterDevices: devices,
        recordingDevices: const <RecordingDeviceIdentity>[
          RecordingDeviceIdentity(id: 'iphone-15'),
          RecordingDeviceIdentity(id: 'macos'),
        ],
      )!;

      expect(selected.id, 'iphone-15');
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
            RecordingDeviceIdentity(id: 'pixel-8'),
            RecordingDeviceIdentity(id: 'iphone-15'),
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
