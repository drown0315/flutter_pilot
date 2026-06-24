# screen_recorder

Device-level screen recording API for Recording Devices.

This package is independent from Flutter Pilot Scenario execution and Flutter
Runtime Targets. It records a selected device display through recording
backends and exposes a programmatic API for starting, stopping, and discarding
Recording Sessions.

The first implementation slice includes the public core API and an in-memory
fake backend for tests and callers that need to exercise the lifecycle without
real Android or iOS tooling.

## Core API

- `listDevices`
- `startRecord`
- `stopRecord`
- `discardRecord`

Callers provide an output directory and an output name without an extension.
The backend chooses the native extension. Android uses `.mp4`; iOS simulator
and physical iOS devices use `.mov`.

```dart
final ScreenRecorder recorder = ScreenRecorder.fake(
  devices: <RecordingDevice>[
    RecordingDevice(
      id: 'android-1',
      name: 'PHK110',
      platform: RecordingDevicePlatform.android,
    ),
  ],
);

final RecordingSession session = await recorder.startRecord(
  deviceSelector: 'PHK110',
  outputDirectory: '/tmp',
  outputName: 'login_flow',
);

final RecordingResult result = await recorder.stopRecord(session);
print(result.outputPath);
```
