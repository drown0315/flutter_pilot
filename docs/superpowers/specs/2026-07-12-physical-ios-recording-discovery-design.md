# Physical iOS Recording Discovery Design

## Problem

The physical iOS recording backend combines two different discovery sources:
AVFoundation devices that the Swift helper can record and `xctrace` devices
that Xcode can run. An `xctrace` device may share the Flutter Device UDID while
remaining absent from AVFoundation.

Flutter Pilot therefore prefers the exact UDID match, starts the helper with an
id the helper cannot resolve, executes every Scenario Step, and only reports a
missing recording when the run stops.

## Scope

This change corrects physical iOS Recording Device discovery and startup
failure timing. It does not change Scenario YAML, Target App launch behavior,
video artifact layout, or Android and iOS Simulator recording.

## Design

`IosPhysicalRecordingBackend.listDevices` will return only devices discovered
by the AVFoundation Swift helper. `xctrace` metadata will no longer be added to
the Recording Device list because the `screen_recorder` contract promises that
listed devices are recordable by their returned ids.

Flutter Pilot's existing id-first, unique-exact-name-second pairing will then
match a physical iOS Flutter Device to the AVFoundation Recording Device by
name and pass the AVFoundation id to the helper.

Physical recording startup will probe the helper process for an immediate exit,
matching the existing iOS Simulator behavior. An immediate exit becomes a
`startFailed` exception containing the helper exit code, stdout, and stderr.
Flutter Pilot will therefore fail before the first Scenario Step instead of
waiting until recording shutdown.

## Tests

Public package tests will verify that:

- physical discovery excludes devices found only by `xctrace`
- AVFoundation helper devices remain discoverable
- an immediately exiting helper fails `startRecord` with `startFailed`
- immediate-exit diagnostics retain the helper error text
- a long-running helper still starts and produces a finalized MOV on stop

Flutter Pilot tests will continue verifying that differing Flutter and
AVFoundation ids pair by exact device name and that the recording controller
receives the AVFoundation id.
