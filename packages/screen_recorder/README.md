# screen_recorder

Device-level screen recording API for Recording Devices.

`screen_recorder` records the selected device display. It is independent from
Flutter Pilot Scenario execution and Flutter Runtime Targets, and it does not
use Flutter VM service discovery.

## Core API

- `listDevices`: return Recording Devices visible to the configured backend.
- `prepare`: prepare a Recording Device for one or more later Recording
  Sessions when a backend supports a separate prepared capture lifecycle.
- `startRecord`: start a Recording Session for a selected device.
- `stopRecord`: stop a Recording Session and return a Recording Result with the
  saved file path, timestamps, duration, file size, and MIME type.
- `discardRecord`: stop a Recording Session and remove backend/local artifacts
  without returning a saved recording.
- `dispose`: release a prepared capture.

```dart
final ScreenRecorder recorder = ScreenRecorder.defaultRecorder();

final RecordingSession session = await recorder.startRecord(
  deviceSelector: 'PHK110',
  outputDirectory: '/tmp',
  outputName: 'login_flow',
);

final RecordingResult result = await recorder.stopRecord(session);
print(result.outputPath);
```

Prepared capture is optional. Backends without a separate prepared mode keep
their direct recording behavior; physical iOS uses preparation to start native
device capture before the saved movie segment begins.

```dart
final PreparedCapture capture = await recorder.prepare(deviceSelector: 'iPhone');

final RecordingSession session = await recorder.startRecord(
  preparedCapture: capture,
  outputDirectory: '/tmp',
  outputName: 'login_flow',
);

final RecordingResult result = await recorder.stopRecord(session);
await recorder.dispose(capture);
print(result.outputPath);
```

Tests and tools can use `ScreenRecorder.fake(...)` to exercise the same API
without real devices.

## CLI

The package exposes a `screen_recorder` executable.

```sh
dart run screen_recorder --device PHK110 --output-directory /tmp --output-name login_flow
```

Press `s` to stop/save. The CLI prints:

```text
Saved recording: <final-path>
```

Press `q` to discard. Discard exits without printing a saved recording path.

CLI errors render `ScreenRecorderException` codes, so scripts can distinguish
failures such as `deviceNotFound`, `missingDependency`, `permissionDenied`, and
`stopFailed`.

## Device Discovery

The default recorder searches backends in this fixed order:

```text
Android -> iOS Simulator -> physical iOS
```

Selection accepts:

- exact id, such as an ADB serial or simulator UDID
- exact name
- case-insensitive name prefix

Resolution stops at the first backend with a match. Use the optional
platform filter when names overlap:

```dart
final ScreenRecorder recorder = ScreenRecorder.defaultRecorder(
  platform: RecordingDevicePlatform.iosSimulator,
);
```

## Output Files

Callers pass `outputDirectory` and optional `outputName`.

- `outputName` must not include a path separator.
- `outputName` must not include a file extension.
- When `outputName` is omitted, the package generates one from UTC time and
  device context.
- Existing final output files fail by default. Pass `overwrite: true` to
  `startRecord` to replace an existing file.

Backends choose native formats:

- Android: `.mp4`, MIME type `video/mp4`
- iOS Simulator: `.mov`, MIME type `video/quicktime`
- physical iOS: `.mov`, MIME type `video/quicktime`

## Prerequisites

Android:

- `adb` available on `PATH`
- `scrcpy` available on `PATH` for the preferred Android recording path;
  falls back to device `screenrecord`, then to host `ffmpeg` frame capture
- USB debugging or emulator access
- `adb devices` shows the target device in `device` state
- optional fallback dependencies (used when `scrcpy` is unavailable):
  - Android `screenrecord` support on the target device
  - `ffmpeg` available on `PATH` for screenshot-sequence fallback recording
    (last resort when `screenrecord` fails with permission errors)

iOS Simulator:

- macOS with Xcode Command Line Tools
- `xcrun simctl` available
- target simulator is booted and visible as `Booted` in
  `xcrun simctl list devices`

Physical iOS:

- macOS with Xcode Command Line Tools, including `swiftc`
- iPhone connected over USB, unlocked, and trusted by this Mac
- macOS camera permission granted to the current terminal/Codex process
- no competing app such as QuickTime or meeting software owning the capture
  device

The physical iOS backend builds and runs the in-package Swift helper at
`tool/ios_physical/ios_physical_capture.swift`. Its prepared mode starts a
stateful helper, waits until native capture has produced a real frame, writes a
saved `.mov` segment only between `startRecord` and `stopRecord`, and shuts the
helper down on `dispose`. It does not depend on any local prototype directory.

## Manual Smoke Checklist

Android:

```sh
adb devices
dart run screen_recorder --device <adb-serial-or-name-prefix> --output-directory /tmp --output-name android_smoke
```

Press `s`, then verify `/tmp/android_smoke.mp4` exists and is playable.

iOS Simulator:

```sh
xcrun simctl list devices
dart run screen_recorder --device <simulator-udid-or-name-prefix> --output-directory /tmp --output-name simulator_smoke
```

Press `s`, then verify `/tmp/simulator_smoke.mov` exists and is playable.

Physical iOS:

```sh
xcode-select -p
dart run screen_recorder --device <iphone-name-prefix> --output-directory /tmp --output-name iphone_smoke
```

Press `s`, then verify `/tmp/iphone_smoke.mov` exists and is playable. If no
device appears, unlock and trust the iPhone, check camera permission, unplug and
replug USB, and close apps that may own the capture device.

Discard behavior:

```sh
dart run screen_recorder --device <device> --output-directory /tmp --output-name discard_smoke
```

Press `q`, then verify no saved recording path is printed.

## Out Of Scope

- Flutter Pilot integration
- Scenario YAML video actions
- VM service discovery or Flutter Runtime Target discovery
- Snapshot, Widget Tree, Finder Match, or Flutter log capture
- audio recording
- transcoding `.mov` to `.mp4`
