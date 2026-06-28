# Screen Recorder PRD

## Problem Statement

Developers and automation tools need a small, dependable way to record the
screen of a selected device without tying that capability to a Flutter Runtime
Target, Scenario execution, or `mcp_flutter` VM service connection. Flutter
Pilot may later consume Device Video Recording artifacts, but the recording
capability is device-level: it records what is visible on the device display,
not Flutter UI semantics.

The current discovery path discussed for Flutter Pilot is not enough for this
job. A physical iPhone can be connected and available to native screen capture
without appearing in `flutter devices`, and a VM service URI cannot identify a
recordable device screen. Users need `screen_recorder` to discover Recording
Devices through recording backends and expose a programmatic API that starts and
stops Recording Sessions explicitly.

## Solution

Build `screen_recorder` as an independent Dart package with a programmatic core
API and an optional thin CLI. The package discovers Recording Devices through
recording backends, starts a Recording Session for one selected device, and
returns the final saved video path only after `stopRecord` completes.

The default resolver searches recording backends in fixed order and stops at the
first match:

1. Android devices through Android Debug Bridge
2. iOS simulators through `xcrun simctl`
3. physical iOS devices through native AVFoundation/CoreMediaIO screen capture
   discovery

Device selectors support exact id/name matching and case-insensitive name prefix
matching. A platform filter can narrow discovery to one backend family when a
caller wants to avoid default priority.

The core API exposes:

- `listDevices`
- `startRecord`
- `stopRecord`
- discard behavior for an active Recording Session

Android recordings use the platform-native `.mp4` output. iOS simulator and
physical iOS recordings use the platform-native `.mov` output. Callers provide
an output directory and an output name without an extension; the backend chooses
the final extension.

## User Stories

1. As a developer, I want to record a selected device screen, so that I can capture visual behavior without setting up a Flutter Runtime Target.
2. As a developer, I want `screen_recorder` to be independent from Flutter Pilot Scenario execution, so that I can use it in scripts and tools outside Flutter Pilot.
3. As a developer, I want a programmatic API, so that other tools can start and stop recordings without driving an interactive CLI.
4. As a developer, I want `startRecord` to return a Recording Session, so that I can hold a handle to an active recording.
5. As a developer, I want `stopRecord` to return the final saved video path, so that I know exactly which file to attach or inspect.
6. As a developer, I want discard behavior for an active Recording Session, so that canceled recordings do not leave local or device-side artifacts behind.
7. As a developer, I want `listDevices` to return Recording Devices, so that I can show users only devices relevant to screen recording.
8. As a developer, I want Recording Devices to be distinct from Flutter Runtime Targets, so that device screen capture is not confused with Flutter app runtime communication.
9. As a developer, I want Android devices discovered through Android Debug Bridge, so that Android screen recording works even without Flutter tooling.
10. As a developer, I want iOS simulators discovered through simulator tooling, so that simulator recording does not depend on Flutter tooling.
11. As a developer, I want physical iOS devices discovered through native iOS screen capture discovery, so that connected iPhones can be recorded even when they do not appear in `flutter devices`.
12. As a developer, I want discovery to search Android, then iOS simulators, then physical iOS devices, so that device selection is deterministic.
13. As a developer, I want discovery to stop at the first backend match, so that backend priority is simple and predictable.
14. As a developer, I want exact id matching, so that scripts can select a specific device reliably.
15. As a developer, I want exact name matching, so that common device names work without copying opaque identifiers.
16. As a developer, I want case-insensitive name prefix matching, so that short selectors such as `iph` can select `iPhone`.
17. As a developer, I want prefix matching to respect backend priority, so that the first matching backend wins consistently.
18. As a developer, I want an optional platform filter, so that I can force selection to Android, iOS simulator, or physical iOS when names overlap.
19. As a developer, I want output names without file extensions, so that the backend can choose the correct native video format.
20. As a developer, I want an output directory separate from output name, so that paths and file naming rules stay clear.
21. As a developer, I want output name to be optional, so that quick recordings can use generated names.
22. As a developer, I want generated output names to include useful time and device context, so that recordings are easy to identify.
23. As a developer, I want existing output files to fail by default, so that a recording does not accidentally overwrite useful evidence.
24. As a developer, I want explicit overwrite support, so that repeatable scripts can intentionally replace prior output.
25. As a developer, I want Android recordings to use native `.mp4`, so that they are immediately playable without transcoding.
26. As a developer, I want iOS recordings to use native `.mov`, so that the first version avoids unnecessary transcoding failures.
27. As a developer, I want `stopRecord` to validate that the final output file exists and is non-empty, so that success means a usable artifact was produced.
28. As a developer, I want `RecordingResult` to include duration and file size, so that callers can display basic recording metadata.
29. As a developer, I want `RecordingResult` to include MIME type, so that downstream tools can handle `.mp4` and `.mov` outputs correctly.
30. As a developer, I want one stable exception type with error codes, so that callers can handle failures without matching message text.
31. As a developer, I want device-not-found and ambiguous-device failures to be distinguishable by code, so that UI or CLI callers can render better guidance.
32. As a developer, I want dependency-missing failures to be distinguishable by code, so that setup issues are clear.
33. As a developer, I want permission-denied failures to be distinguishable by code, so that macOS camera permission problems are not mistaken for missing devices.
34. As a developer, I want start and stop failures to preserve raw backend output, so that debugging external tool failures is practical.
35. As a developer, I want the same process to support multiple simultaneous recordings on different devices, so that multi-device workflows are possible.
36. As a developer, I want the same device to reject duplicate active recordings, so that two sessions do not fight over the same screen source.
37. As a developer, I want Recording Sessions to be scoped to the current process, so that the first version does not need persistent daemon state.
38. As a developer, I want Recording Session ids to be unique within one recorder instance, so that logs and errors can reference active sessions.
39. As a developer, I want public Recording Sessions to hide backend process ids and temporary paths, so that callers do not depend on implementation details.
40. As a developer, I want Android recordings to write to a device-side temporary file first, so that native Android MP4 recording stays simple.
41. As a developer, I want Android `stopRecord` to pull the device-side file locally, so that the result path points to a local artifact.
42. As a developer, I want Android cleanup to remove device-side temporary files, so that repeated recordings do not fill device storage.
43. As a developer, I want Android discard behavior to stop recording and remove the device-side temporary file, so that canceled sessions are cleaned up.
44. As a developer, I want iOS simulator recording to run as a managed long process, so that start and stop match the simulator tool behavior.
45. As a developer, I want physical iOS recording to run as a managed native helper process, so that the helper can finalize the `.mov` file on stop.
46. As a developer, I want the physical iOS helper source to live inside the package, so that the package does not depend on a local prototype directory.
47. As a developer, I want physical iOS discovery to expose enough native identity data to select a capture device, so that multiple attached devices can be handled deliberately.
48. As a developer, I want a thin CLI for smoke testing, so that I can manually verify backends without writing a script.
49. As a CLI user, I want the CLI to start recording in the foreground, so that the terminal interaction is obvious.
50. As a CLI user, I want pressing `s` to stop and save, so that the command returns the saved file path.
51. As a CLI user, I want pressing `q` to stop and discard, so that I can cancel a recording without keeping a file.
52. As a CLI user, I want CLI behavior to use the core API, so that CLI and library behavior do not diverge.
53. As a maintainer, I want backends isolated behind a small interface, so that Android, iOS simulator, and physical iOS behavior can be tested independently.
54. As a maintainer, I want process execution isolated behind a fakeable boundary, so that tests do not require real devices.
55. As a maintainer, I want output naming isolated from backend process management, so that file naming rules are tested once.
56. As a maintainer, I want device resolution isolated from recording lifecycle, so that selector matching can be tested without starting recordings.
57. As a future Flutter Pilot contributor, I want `screen_recorder` to remain a device-level package, so that Flutter Pilot can later consume it without changing Runtime Adapter semantics.
58. As a future Flutter Pilot contributor, I want Device Video Recording to remain separate from Scenario actions, so that video capture does not become a YAML action accidentally.

## Implementation Decisions

- Build `screen_recorder` as an independent Dart package.
- Keep `screen_recorder` separate from the Flutter Pilot Runtime Adapter.
- The package domain uses Recording Device, Recording Session, and Device Video Recording vocabulary.
- The primary contract is a programmatic API, not a CLI-first command surface.
- Add a thin CLI for manual smoke testing and interactive foreground recording.
- The CLI must call the same core library API that programmatic callers use.
- Core API includes `listDevices`, `startRecord`, `stopRecord`, and discard behavior.
- `startRecord` returns a Recording Session.
- `stopRecord` accepts a Recording Session and returns a Recording Result.
- Discard behavior accepts a Recording Session and cleans up backend artifacts without returning a saved recording.
- Recording Sessions are scoped to the current process and do not support cross-process recovery in the first version.
- Recording Session ids are generated by the package and unique within the current recorder instance.
- Public Recording Session data includes stable caller-facing information such as id, Recording Device, backend kind, start time, and expected output path.
- Public Recording Session data does not expose backend process ids, Android device-side temporary paths, or native helper internals.
- Recording Result includes the Recording Session, final output path, start time, stop time, duration, file size, and MIME type.
- Use one `ScreenRecorderException` type with a stable `ScreenRecorderErrorCode`.
- Error codes include device not found, ambiguous device, unsupported platform, output already exists, already recording, start failed, stop failed, discard failed, session not found, missing dependency, and permission denied.
- Exceptions may carry backend kind, device selector, raw backend output, and cause for diagnostics.
- The default device resolver searches Android, iOS simulator, then physical iOS backends.
- Device discovery stops at the first backend that matches the selector.
- Device selectors support exact id, exact name, and case-insensitive name prefix matching.
- Prefix matching is limited to prefixes; contains or fuzzy substring matching is not part of the first version.
- Within a backend, if multiple devices match the selector, the backend returns its first match according to backend discovery order.
- A platform filter can narrow discovery to one backend family.
- The first version does not expose configurable backend priority.
- Android Recording Devices are discovered through Android Debug Bridge.
- iOS simulator Recording Devices are discovered through `xcrun simctl`.
- Physical iOS Recording Devices are discovered through native AVFoundation/CoreMediaIO screen capture discovery.
- Physical iOS USB diagnostics may use system USB information for doctor-style guidance, but USB diagnostics are not the primary recording device identity.
- `flutter devices` is not the primary discovery source because Recording Devices are not Flutter devices.
- Output configuration uses output directory plus output name.
- Output name must not contain a path separator or file extension.
- Output name may be omitted, in which case the package generates one.
- Generated output names include timestamp and device context.
- Backends choose the final file extension.
- Android output uses `.mp4`.
- iOS simulator output uses `.mov`.
- Physical iOS output uses `.mov`.
- Existing final output files fail by default.
- Explicit overwrite allows replacing an existing final output file.
- Android recording uses a device-side temporary MP4 file, stops the process, pulls the file to the local output path, and removes the device-side temporary file.
- Android discard stops the process and removes the device-side temporary file without creating a local final output.
- iOS simulator recording starts the simulator record-video process and stops it by signaling the process.
- iOS simulator discard stops the process and removes the local output file.
- Physical iOS recording uses an in-package Swift helper based on the native AVFoundation/CoreMediaIO capture approach validated in the local prototype.
- Physical iOS recording does not shell out to or depend on the local prototype directory.
- The Swift helper lists physical iOS capture devices and records one selected device to `.mov`.
- Physical iOS recording starts the helper as a long-running process and stops it by signaling the process so the helper can finalize the movie file.
- Physical iOS discard stops the helper and removes the local output file.
- Support simultaneous active recordings on different Recording Devices.
- Reject starting a second active Recording Session for the same Recording Device.
- Build deep modules for device resolution, output naming, backend lifecycle, process execution, and CLI interaction.
- Keep backend command construction and process lifecycle behind fakeable boundaries.
- Keep CLI rendering and keyboard interaction separate from core recording behavior.
- Respect the ADR that records `screen_recorder` as an independent device recording package.

## Testing Decisions

- Tests should verify public behavior and stable contracts, not private implementation details.
- Most automated tests should use fake process runners and fake backend discovery data.
- Real Android, iOS simulator, and physical iOS device checks are manual smoke tests rather than required unit test dependencies.
- Device resolver tests should cover backend search order.
- Device resolver tests should cover exact id matching.
- Device resolver tests should cover exact name matching.
- Device resolver tests should cover case-insensitive prefix matching.
- Device resolver tests should verify that discovery stops after the first backend match.
- Device resolver tests should cover platform filtering.
- Device resolver tests should cover device-not-found errors.
- Device resolver tests should cover ambiguous or duplicate active-device conditions where applicable.
- Output naming tests should cover explicit output name without extension.
- Output naming tests should reject output names with file extensions.
- Output naming tests should reject output names with path separators.
- Output naming tests should cover generated output names.
- Output naming tests should cover backend-native extensions.
- Output naming tests should cover existing output files with overwrite disabled.
- Output naming tests should cover explicit overwrite.
- Session lifecycle tests should cover `startRecord` returning a Recording Session.
- Session lifecycle tests should cover `stopRecord` returning a Recording Result with final path, duration, size, and MIME type.
- Session lifecycle tests should cover discard cleanup.
- Session lifecycle tests should cover same-device already-recording rejection.
- Session lifecycle tests should cover parallel sessions on different devices.
- Session lifecycle tests should cover stopping or discarding a session that does not belong to the recorder.
- Android backend tests should verify command mapping for device-side `screenrecord`.
- Android backend tests should verify stop behavior: signal process, pull local file, remove device-side file.
- Android backend tests should verify discard behavior: signal process and remove device-side file without returning a final local file.
- iOS simulator backend tests should verify `simctl` command mapping.
- iOS simulator backend tests should verify stop and discard process handling.
- Physical iOS backend tests should verify helper build and invocation boundaries with fake process execution.
- Physical iOS backend tests should verify native device list parsing from representative helper output.
- Exception tests should verify stable `ScreenRecorderErrorCode` values rather than message text.
- CLI tests should run a real Dart subprocess only for argument handling and interactive rendering that can be safely simulated.
- CLI tests should not require real devices.
- Manual smoke tests should verify one Android recording, one iOS simulator recording, and one physical iOS recording on a properly configured macOS host.

## Out of Scope

- Integrating `screen_recorder` into `flutter_pilot run`.
- Adding video recording to Scenario YAML.
- Treating Device Video Recording as a Runtime Adapter operation.
- Discovering or connecting to Flutter VM service URIs.
- Capturing Snapshot, Widget Tree, Flutter logs, or Finder Matches.
- Mapping recordings to Scenario Steps.
- Building a persistent recording daemon.
- Recovering Recording Sessions after process restart.
- Configurable backend priority in the first version.
- Using `flutter devices` as the primary discovery source.
- Transcoding `.mov` to `.mp4` or forcing one universal output format.
- Capturing audio.
- Supporting desktop or web screen recording.
- Supporting fuzzy contains matching beyond name prefix matching.
- Depending on the local `ios_screen` prototype at runtime.

## Further Notes

- `screen_recorder` uses Recording Device terminology because it selects devices
  that can be recorded, not Flutter Runtime Targets.
- Physical iOS support depends on macOS, a trusted unlocked iPhone, available
  camera permission for the current terminal process, and no competing app
  owning the iOS capture device.
- The local `ios_screen` prototype is calibration evidence for the physical iOS
  backend, not a runtime dependency.
- This PRD is paired with the ADR that records the decision to build
  `screen_recorder` as an independent device recording package.
