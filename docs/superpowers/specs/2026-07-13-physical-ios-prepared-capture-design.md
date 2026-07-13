# Physical iOS Prepared Capture Design

## Problem

Starting the physical iOS AVFoundation capture session after `flutter run` has
attached to an application can disrupt the device's USB debug transport. The
Flutter tool then loses its debug session and the application exits. Starting
capture before Flutter avoids that failure, but the current one-process,
one-file helper also records the Flutter build, install, and cold-start period.

An accidentally orphaned helper demonstrated that these lifecycles can be
separated: Flutter can launch while the physical-device capture session is
already active, and the Scenario video can begin later. The supported design
must reproduce that behavior with explicit ownership and cleanup rather than
depending on an orphan process.

## Scope

This change adds prepared capture only for physical iOS Recording Devices.
Android recording through ADB and iOS Simulator recording through `simctl`
retain their current direct start and stop behavior. Scenario YAML and the
Device Video Recording artifact name and report shape do not change.

## Lifecycle Contract

The recording boundary gains four lifecycle operations:

1. `prepare` establishes any device-level capture resources required before
   the Target App launches.
2. `start` begins the Recording Session whose frames belong to the final Device
   Video Recording.
3. `stop` finalizes that Recording Session and returns its saved video path.
4. `dispose` releases prepared resources and waits until their process exits.

Direct backends implement `prepare` and `dispose` without starting an early
recording. Physical iOS implements `prepare` by starting a long-lived helper and
waiting until AVFoundation delivers a real frame. Its `start` and `stop`
operations create and finalize a movie segment without restarting the capture
session. Its `dispose` stops the capture session and waits for the helper to
exit.

Flutter Pilot invokes `prepare` after Target Device pairing and before
`flutter run`. It invokes `start` only after the Runtime Adapter is initialized
and before the first Step. It invokes `stop` after Scenario execution and
before Target App shutdown. It invokes `dispose` on every terminal path after a
successful prepare, including Target App launch failure, Runtime Adapter
initialization failure, Step failure, Project Run failure, and interruption.

## Physical iOS Helper Protocol

The Swift helper becomes a stateful process controlled through stdin and
acknowledged through stdout. Protocol messages are line-delimited and contain
an operation plus any required output path. Paths must use an encoding that
cannot be confused with protocol delimiters.

The helper states are:

- `preparing`: configure and start `AVCaptureSession`
- `ready`: at least one real video sample has arrived; no movie is being written
- `recording`: samples are being appended to one `AVAssetWriter`
- `finalizing`: the current writer is finishing its MOV
- `closed`: the capture session is stopped and the helper exits

The helper emits `READY` only after its sample-buffer delegate receives a real
frame. `START` is valid only in `ready`; it creates a fresh writer and begins its
timeline at the next accepted sample. `STOP` is valid only in `recording`; it
marks the writer input finished and emits `SAVED` only after
`finishWriting` succeeds. It then returns to `ready` without reconfiguring or
stopping `AVCaptureSession`. `SHUTDOWN` finalizes or cancels active work by the
caller's requested cleanup policy, stops capture, and exits.

Every movie segment starts its media timeline at its first accepted sample, so
the saved video excludes capture warm-up and Target App launch. Starting or
stopping a segment must not call `AVCaptureSession.startRunning` or
`stopRunning`.

## Single Scenario And Project Run Ownership

A single-file Test Run owns one prepared physical iOS helper. A Project Run
also owns one prepared helper for the entire Target App lifetime and creates a
separate segment for each recording-enabled Scenario. Scenarios with recording
disabled do not create a writer, while the prepared capture session may remain
ready for a later enabled Scenario.

The executor owns preparation and disposal because those operations surround
Target App launch. The Scenario runner continues to own logical Recording
Session start and stop because those operations define the final video's
Scenario boundary.

## Failure And Cleanup Behavior

- Failure before `READY` is a recording preparation failure and prevents Target
  App launch.
- Target App launch failure after `READY` disposes the helper and creates no
  Device Video Recording.
- Segment startup failure prevents Step execution for that Scenario.
- Scenario or Step failure still stops and saves the active segment so the
  failure remains visible in the video.
- Segment finalization failure fails that Scenario and preserves diagnostics.
- Interruption first requests orderly segment finalization when a Scenario is
  active, then requests helper shutdown, waits with a bounded timeout, and uses
  forced termination only as a final fallback.
- Disposal is idempotent. Completion is not reported until the helper process
  has exited, preventing a stale capture session and the persistent `9:41`
  device status indicator.

Raw helper stderr and protocol violations remain backend diagnostics and are
normalized into the existing recording failure boundary exposed by Flutter
Pilot.

## Testing

Implementation follows red-green-refactor and covers public behavior at each
ownership boundary.

`screen_recorder` tests verify that physical iOS preparation waits for `READY`,
segment start and stop reuse one helper process, consecutive segments produce
separate MOV paths, stop does not exit the helper, dispose waits for exit, and
protocol errors or timeouts become structured failures. Existing Android and
iOS Simulator tests verify that preparation does not start their recording
commands early.

Flutter Pilot executor tests verify that prepare precedes Target App launch,
logical start remains after Runtime Adapter initialization, stop precedes app
shutdown, and dispose runs on success, launch failure, Scenario failure, and
interruption. Project Run tests verify one physical iOS preparation with one
segment per enabled Scenario and no segment for disabled Scenarios.

A physical-device smoke test verifies that Flutter remains connected when a
segment starts, the final MOV begins after Target App launch, the helper exits
at run completion, and the device status indicator returns from `9:41`.

## Documentation Changes

The test command PRD must replace the current rule that all Scenario Recording
starts only after the Runtime Target URI. The revised rule distinguishes
physical iOS capture preparation before Target App launch from logical
Recording Session start after Runtime initialization. The Scenario Recording
contract continues to promise a final video covering the Scenario rather than
Flutter build and cold-start time.
