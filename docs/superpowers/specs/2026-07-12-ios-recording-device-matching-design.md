# iOS Recording Device Matching Design

## Problem

Flutter Pilot currently assumes that a Flutter Device and its corresponding
Recording Device have the same id. That holds for Android devices and iOS
Simulators, but not for physical iOS devices: Flutter uses the device UDID while
the AVFoundation recording backend exposes a different device id.

On a physical iPhone, Flutter Pilot can therefore launch the correct Target App
Package but pass an unresolvable Flutter UDID to `screen_recorder`. Recording
then fails with `deviceNotFound`, even though the same iPhone is recordable by
its AVFoundation name or id.

## Scope

This change fixes Target Device to Recording Device matching for Scenario
Recording. It does not change Target App launch timeouts, the Scenario YAML
schema, recording lifecycle, or video artifact layout.

## Design

Recording Device discovery will retain both the backend-specific device id and
the human-readable device name. Target Device resolution will pair a supported
Flutter Device with a Recording Device using this priority:

1. exact device id
2. exact device name when no id match exists

The resolved run context will retain the selected Recording Device selector
separately from the Target Device. Flutter Pilot will continue passing the
Flutter Device id to `flutter run`, while `ScreenRecorderRecordingController`
will receive the paired Recording Device id.

The pairing is an execution concern rather than Target Device metadata. Run
reports continue to describe the Flutter-selected Target Device and do not
expose backend-specific recording identity.

## Ambiguity And Failure Handling

An exact id match always wins over name matching. A name fallback must resolve
to exactly one Recording Device. Multiple Recording Devices with the same name
are ambiguous and cause Target Device resolution to fail before app launch.

When recording is required, a Flutter Device with neither an id match nor a
unique exact-name match is not recordable. Existing clear pre-launch failure
behavior remains in place.

Non-recording runs do not discover or pair Recording Devices. Existing Android
and iOS Simulator behavior remains unchanged because their exact id matches
continue to take precedence.

## Data Flow

1. Device discovery reads Flutter Devices and Recording Devices.
2. Target Device resolution selects the Flutter Device requested by `--device`
   or the unique recordable Flutter Device.
3. Recording Device pairing selects an exact id match or unique exact-name
   match.
4. The Test Execution Session launches the app with the Flutter Device id and
   retains the paired Recording Device id.
5. The test or Project Run executor creates the recording controller with the
   paired Recording Device id.

## Tests

Public behavior tests will cover:

- exact id pairing remains preferred
- different ids with the same exact name pair successfully
- duplicate Recording Device names fail as ambiguous
- unmatched devices remain non-recordable
- the app launcher receives the Flutter Device id
- the recording controller receives the paired Recording Device id
- Project Run uses the same paired selector behavior

The tests use fake discovery and recording boundaries; the manual physical iOS
probe remains the external evidence that Flutter UDID lookup fails while the
paired AVFoundation device succeeds.
