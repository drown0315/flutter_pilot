# Flutter Pilot Test Command PRD

## Problem Statement

Flutter Pilot can replay Scenario YAML and collect debugging artifacts, but the
current execution workflow exposes too much runtime plumbing to users. A user
has to start the Flutter app separately, find a VM service URI, and, when
Scenario Recording is enabled, reason about a separate Recording Device
selector. That makes local e2e debugging slow, fragile, and hard to repeat.

Users need one Scenario execution command that launches the current Target App
Package, selects the Target Device, obtains the Runtime Target URI, runs the
Scenario, records the same device when requested, and cleans up the launched app
process.

## Solution

Make `flutter_pilot test <scenario.yaml>` the only CLI command that executes a
Scenario. The command launches the current Flutter app with
`flutter run --machine`, extracts `app.debugPort.wsUri`, creates the internal
Runtime Target, and then runs the Scenario through the existing runner.

The command supports common Flutter app launch options:

- `--device` / `-d` selects the Target Device by Flutter Device id, name, or
  name prefix.
- `--flavor` is passed to `flutter run --flavor`.
- `--target` / `-t` selects the Flutter app entrypoint file.

When Scenario Recording is enabled, Flutter Pilot requires the Target Device to
also be available as a Recording Device with the same device id. If the user
does not pass `--device`, Flutter Pilot automatically selects a Target Device
only when exactly one supported Flutter Device id is also present in the
Recording Device list. Zero or multiple recordable Target Devices fail before
launch and ask the user to pass `--device`.

The existing `run` command and user-supplied VM service URI mode are removed
from the CLI. Runtime Target remains an internal model produced by the `test`
launch flow, not a user-provided command option.

## User Stories

1. As a Flutter developer, I want one command to launch my app and run a Scenario, so that I do not need to manually copy a VM service URI.
2. As a Flutter developer, I want `flutter_pilot test scenario.yaml`, so that the normal e2e path is short and memorable.
3. As a Flutter developer, I want Flutter Pilot to launch the current Target App Package, so that the command behaves like a local app test.
4. As a Flutter developer, I want `--device` to select the Target Device, so that I can choose where the app runs.
5. As a Flutter developer, I want `-d` as a short form for `--device`, so that the command feels familiar from `flutter run`.
6. As a Flutter developer, I want `--device` to accept a Flutter Device id, name, or name prefix, so that I do not need to copy long device identifiers.
7. As a Flutter developer, I want a device selector to resolve to exactly one Flutter Device, so that Flutter Pilot never guesses the Target Device.
8. As a Flutter developer, I want Flutter Pilot to pass the resolved Target Device id to Flutter, so that app launch uses stable device identity.
9. As a Flutter developer, I want `--flavor` to be passed to Flutter, so that production-style flavored apps can be tested.
10. As a Flutter developer, I want `--target` to mean Flutter app entrypoint file, so that Flutter Pilot matches Flutter CLI vocabulary.
11. As a Flutter developer, I want `-t` as a short form for `--target`, so that entrypoint selection matches `flutter run`.
12. As a Flutter developer, I want `--target lib/main_staging.dart`, so that I can test apps with non-default entrypoints.
13. As a Flutter developer, I want `test --device PHK110 --flavor staging --target lib/main_staging.dart`, so that common production launch configuration is supported.
14. As a Flutter developer, I want Scenario YAML parsing to happen before app launch, so that invalid Scenarios fail without starting Flutter.
15. As a Flutter developer, I want `test` to support `--until`, so that I can stop at a known Step while using the easy app-launching entrypoint.
16. As a Flutter developer, I want `test` to support `--print`, so that I can inspect Snapshot, Widget Tree, or errors after a stopped Step.
17. As a Flutter developer, I want `--print` to keep requiring `--until`, so that diagnostic output remains tied to a precise checkpoint.
18. As a Flutter developer, I want `--json` to keep its existing diagnostic-print meaning, so that startup events do not change the JSON contract.
19. As a Flutter developer, I want Scenario Recording to record the same device that runs the app, so that the Device Video Recording reflects the actual Scenario Run.
20. As a Flutter developer, I want recording-enabled Scenarios to fail when no recordable Target Device exists, so that requested video artifacts are never silently skipped.
21. As a Flutter developer, I want recording-enabled Scenarios to fail when multiple recordable Target Devices exist and I did not pass `--device`, so that Flutter Pilot does not choose the wrong device.
22. As a Flutter developer, I want recording-enabled Scenarios to auto-select the Target Device when exactly one supported Flutter Device id is also a Recording Device id, so that single-device setups stay convenient.
23. As a Flutter developer, I want `scenario.recording.enabled: false` to behave like no recording, so that templates can disable recording without triggering device discovery.
24. As a Flutter developer, I want recording-disabled Scenarios to run on macOS or Chrome when Flutter supports them, so that ordinary Scenario execution is not limited by screen recording.
25. As a Flutter developer, I want recording-enabled Scenarios to reject macOS and Chrome Target Devices, so that unsupported recording platforms fail clearly.
26. As a Flutter developer, I want Flutter Pilot to print the resolved Target Device when one is selected, so that I know what app launch and recording will use.
27. As a Flutter developer, I want Flutter Pilot to print the connected Runtime Target URI, so that I can see that app launch produced a runtime connection.
28. As a Flutter developer, I want `test` to stop the launched Flutter app when the Scenario finishes, so that repeated runs do not leave stray app processes.
29. As a Flutter developer, I want Ctrl-C cleanup to stop recording before stopping the Flutter app, so that interrupted recordings can still finalize when possible.
30. As a Flutter developer, I want `flutter run` startup failure to show useful stderr context, so that I can diagnose build or launch failures.
31. As a Flutter developer, I want Flutter Pilot to avoid printing raw `flutter run --machine` JSON during normal startup, so that command output stays readable.
32. As a Flutter developer, I want `flutter run` stderr context only when startup fails or the launched process exits unexpectedly, so that ordinary Scenario failures stay focused on Scenario diagnostics.
33. As a Flutter developer, I want no Flutter Pilot launch timeout, so that long Flutter builds follow Flutter CLI behavior and can be interrupted manually.
34. As a Flutter developer, I want `test` to run from the current Target App Package directory, so that Flutter app launch matches manual `flutter run`.
35. As a Flutter developer, I want Scenario files to live outside the Target App Package if needed, so that Scenario repositories can be shared.
36. As a Flutter developer, I want run artifacts to be written under the current Target App Package `.runs/` directory, so that app test results are easy to find.
37. As a Flutter developer, I want Flutter Pilot not to run setup checks before `test`, so that `test` has no doctor/init side effects.
38. As a Flutter developer, I want `doctor` and `init` to remain separate commands, so that app setup remains explicit.
39. As a Flutter developer, I want no automatic `flutter pub get` wrapper beyond Flutter's own `flutter run` behavior, so that `test` does not duplicate Flutter CLI responsibilities.
40. As a Flutter developer, I want no arbitrary Flutter argument passthrough in the first version, so that the supported command surface stays predictable.
41. As a Flutter developer, I want no CLI flag to enable or disable Scenario Recording, so that the Scenario YAML remains the source of recording intent.
42. As a Flutter developer, I want Device Video Recording files to stay inside the run artifact bundle, so that generated run directories are portable.
43. As a Flutter developer, I want Target Device metadata in the run report, so that artifacts explain which device produced them.
44. As a Flutter developer, I want run directories not to include device ids in their names, so that artifact paths remain stable and readable.
45. As a Flutter developer, I want `validate` to remain schema-only, so that I can lint Scenario YAML without devices or Flutter app launch.
46. As a Flutter developer, I want `report` and `diff` to continue working on run directories, so that post-run workflows are preserved.
47. As a CI user, I want `test` to fail non-interactively when Target Device selection is ambiguous, so that pipelines do not hang waiting for input.
48. As a CI user, I want to pass an explicit Target Device id, so that the same device is used for Flutter launch and recording.
49. As an AI coding agent, I want `test` to be the deterministic reproduction command, so that I can run one command to launch the app and collect artifacts.
50. As an AI coding agent, I want Target Device resolution errors before app launch, so that I can fix command inputs without producing partial run directories.
51. As a maintainer, I want the existing ScenarioRunner reused by `test`, so that `test` and prior Scenario execution behavior do not diverge.
52. As a maintainer, I want app launch orchestration isolated behind a deep module, so that `flutter run --machine` parsing and cleanup can be tested independently.
53. As a maintainer, I want Target Device resolution isolated behind a deep module, so that device matching rules can be tested independently.
54. As a maintainer, I want the Runtime Adapter to continue depending only on Runtime Target, so that device selection does not leak into Flutter UI operation mapping.
55. As a maintainer, I want Target Device to remain separate from Recording Device, so that screen recording backend details do not become the app launch model.
56. As a maintainer, I want the `run` command removed rather than kept as an alias, so that the CLI surface has one Scenario execution path.
57. As a maintainer, I want old `run` invocations to fail as unknown commands, so that the code does not preserve deprecated behavior.
58. As a maintainer, I want physical iOS Recording Device discovery to include devices visible through `xcrun xctrace list devices`, so that Flutter-visible physical iPhones can participate in Target Device matching.
59. As a maintainer, I want Device Video Recording path metadata to be run-directory-relative, so that reports and HTML timeline links remain portable.
60. As a maintainer, I want future full-suite testing left out of this slice, so that single-Scenario `test` can be implemented without suite discovery and aggregation complexity.

## Implementation Decisions

- Remove the `run` command from the CLI instead of renaming it or keeping it as an alias.
- `test` is the only CLI command that executes a Scenario.
- `validate`, `doctor`, `init`, `report`, and `diff` remain separate commands.
- `validate` remains pure Scenario YAML/schema validation and does not launch Flutter, discover devices, or validate recording backends.
- `doctor` and `init` remain explicit setup commands and are not automatically run by `test`.
- `report` and `diff` continue to operate on existing run directories.
- `test` requires exactly one Scenario file in the first version.
- `test` does not support no-argument full-suite discovery in the first version.
- `test` does not support directory inputs or glob inputs in the first version.
- `test` reads the Scenario file before launching Flutter.
- Scenario validation failures prevent Flutter app launch.
- `test` launches the Target App Package from the current working directory.
- `test` does not search upward for a Flutter package root.
- `test` allows the Scenario file to be outside the Target App Package directory.
- `test` writes run artifacts under the current working directory's `.runs/` directory.
- `test` invokes `flutter run --machine`.
- `test` does not explicitly pass `--debug`, `--host-vmservice-port`, `--device-vmservice-port`, `--pub`, or `--no-pub`.
- `test` inherits the current process environment when launching Flutter.
- `test` does not support arbitrary Flutter argument passthrough in the first version.
- `test --device` and `test -d` select the Target Device by Flutter Device id, name, or name prefix.
- `test --device` rejects empty or whitespace-only values as usage errors.
- `test --flavor` passes a Flutter flavor to `flutter run --flavor`.
- `test --flavor` has no short option.
- `test --flavor` rejects empty or whitespace-only values as usage errors.
- `test --target` and `test -t` select the Flutter app entrypoint file passed to `flutter run --target`.
- `test --target` rejects empty or whitespace-only values as usage errors.
- `test --target` does not check whether the entrypoint file exists; Flutter CLI owns that validation.
- `test` supports existing Scenario debugging options: `--until`, repeated `--print`, and `--json`.
- `--print` remains valid only with `--until`.
- `--json` remains scoped to printed diagnostics and does not turn startup events into JSON.
- Target Device is a Flutter Pilot domain model distinct from Runtime Target and Recording Device.
- Target Device metadata contains Flutter Device id, name, target platform, emulator flag, and sdk string.
- Target Device metadata does not include Flutter device capabilities or `isSupported`.
- `test` records Target Device metadata in the run report when a Target Device was resolved.
- If the user does not pass `--device` and Scenario Recording is disabled or omitted, `test` does not discover devices and lets Flutter choose its default device.
- If the user passes `--device`, `test` discovers Flutter Devices and resolves the selector to exactly one supported Flutter Device.
- Unsupported Flutter Devices are excluded from Target Device resolution.
- If Scenario Recording is enabled, Target Device resolution also requires a Recording Device with the same device id.
- Recording Device matching is id-only. Recording Device name is not used as a fallback for Target Device consistency.
- If the user does not pass `--device` and Scenario Recording is enabled, `test` builds the id intersection of supported Flutter Devices and Recording Devices.
- If the recording-required device id intersection has exactly one device, `test` auto-selects that Target Device.
- If the recording-required device id intersection has zero or multiple devices, `test` fails with exit code `64` before launching Flutter.
- Device resolution failures do not create run directories.
- Scenario Recording startup failure after a Runtime Target URI is available is a Scenario Run failure and creates a run report.
- `test` prints the resolved Target Device when one is selected.
- `test` prints the connected Runtime Target URI after extracting it from `flutter run --machine`.
- `test` does not directly print raw `flutter run --machine` stdout during normal startup.
- `test` reads stdout to find `app.debugPort.wsUri`.
- `test` stores the last 40 stderr lines from `flutter run` for startup failure and unexpected process-exit diagnostics.
- `test` does not expose a launch timeout option and does not impose its own startup timeout.
- If `flutter run` exits before producing a VM service URI, `test` fails without starting recording or creating a run directory.
- If `flutter run` exits unexpectedly while the Scenario is still running, `test` reports the unexpected process exit and includes the last 40 stderr lines.
- Runtime Adapter failures do not automatically print `flutter run` stderr unless the Flutter process exited unexpectedly.
- `test` starts Scenario Recording only after `app.debugPort.wsUri` has been received and before the first Scenario Step executes.
- `test` does not record Flutter build, install, or app cold-start time before the Runtime Target URI is available.
- `test` stops Scenario Recording before stopping the launched Flutter app during normal cleanup and Ctrl-C cleanup.
- `test` stops the launched Flutter app process when the Scenario completes or fails.
- App cleanup first attempts the normal Flutter CLI quit path by sending `q` to `flutter run`; if that fails, cleanup may kill the process.
- `test` does not provide `--keep-running` in the first version.
- `test` does not support interactive device selection.
- `test` does not support CLI overrides for Scenario Recording, such as `--recording` or `--no-recording`.
- Scenario Recording never silently degrades to a non-recording run.
- Device Video Recording files should be written under the run directory's `artifacts/` directory.
- Device Video Recording file names should use a stable base name such as `device-video-recording`, with the backend-native extension.
- Device Video Recording artifact paths in reports must be relative to the run directory.
- The existing ScenarioRunner remains responsible for Scenario execution, Step behavior, capture behavior, Scenario Recording lifecycle, and run report generation.
- The Runtime Adapter remains responsible only for operations against the Runtime Target.
- A Target App Launcher module should encapsulate `flutter run --machine` process management, VM URI extraction, stderr buffering, and cleanup.
- A Target Device module should encapsulate Flutter Device parsing, Target Device modeling, Recording Device id matching, and device resolution errors.
- The Target Device module may directly depend on the `screen_recorder` public API, but it outputs Flutter Pilot's Target Device model rather than exposing `screen_recorder` types as the app launch model.
- Physical iOS Recording Device discovery should merge physical iOS devices from `xcrun xctrace list devices` with helper-discovered devices, excluding simulators and offline devices.
- The ADR for this CLI decision is maintained in `docs/adr/0003-split-runtime-uri-run-from-target-device-test.md`.

## Testing Decisions

- Tests should verify public behavior and stable contracts, not private helper implementation details.
- Target Device resolution should be tested as an isolated module because it owns the recording-required device rules.
- Target App Launcher should be tested with fake process streams so `flutter run --machine` parsing and cleanup behavior do not require a live Flutter app.
- CLI subprocess tests should remain for help output, usage errors, `validate`, and other command-shell behavior that does not require fake Flutter processes.
- Complex `test` success paths should be covered through injectable modules or command-level tests rather than subprocess tests that would start a real Flutter app.
- Existing ScenarioRunner tests should remain the primary coverage for Scenario execution, Step lifecycle, capture, failure handling, `--until`, `--print`, and Scenario Recording lifecycle.
- Screen recorder package tests should cover physical iOS discovery through `xcrun xctrace list devices`.
- Artifact/report tests should cover Device Video Recording as a run-level artifact with run-directory-relative paths.
- Prior art for parser and CLI behavior is the existing Scenario parser tests and CLI subprocess tests.
- Prior art for runner behavior is the fake Runtime Adapter-based ScenarioRunner test style.
- Prior art for recording behavior is the existing fake recording boundary and `screen_recorder` backend tests.
- The full `screen_recorder` package test suite should pass after physical iOS discovery changes.
- Before finishing implementation changes, run `dart format .`, `dart analyze`, and `dart test` unless explicitly directed otherwise.

## Out of Scope

- Full-suite or all-Scenario discovery.
- Directory or glob Scenario inputs.
- Running multiple Scenario files in one `test` invocation.
- Suite-level reports.
- Parallel device orchestration.
- Interactive device selection.
- A `devices` command.
- A dry-run mode for Target Device resolution.
- User-supplied VM service URI execution.
- Reintroducing a `run` command as an alias or advanced command.
- Connecting to an already-running app launched by an IDE or external script.
- Arbitrary Flutter argument passthrough.
- `--dart-define`, `--dart-define-from-file`, `--profile`, `--release`, or custom launch modes in the first version.
- Launch timeout configuration.
- Automatic `doctor` or `init` checks before `test`.
- Automatic `flutter pub get` beyond Flutter CLI's own `flutter run` behavior.
- CLI flags to enable, disable, or override Scenario Recording.
- Custom recording output directories.
- Desktop or web screen recording support.
- macOS, Windows, Linux, or Chrome Recording Device backends.
- Device id/name cross-table ambiguity handling beyond id-only Recording Device matching.
- Recording Flutter build or app launch before `app.debugPort.wsUri` is available.
- Saving full `flutter run --machine` logs as run artifacts in the first version.
- Printing Flutter or Flutter Pilot version information at command start.
- Adding Target Device id or name to run directory names.
- Publishing this PRD to an issue tracker until tracker credentials and label conventions are available.

## Further Notes

- The `run` command removal is a deliberate product simplification. Runtime
  Target remains an internal architecture term because Flutter Pilot still runs
  Scenarios against a running Flutter app instance obtained from `flutter run`.
- `test` is intentionally a convenience orchestration layer over the existing
  ScenarioRunner. It should not fork Scenario execution semantics.
- The Target Device and Recording Device id alignment was calibrated locally
  after updating physical iOS discovery: Android, iOS Simulator, and physical
  iOS devices all matched by device id in the observed environment.
- Physical iOS discovery through `xcrun xctrace list devices` makes the device
  visible for Target Device matching. Actual physical iOS recording still
  depends on the `screen_recorder` backend being able to start a Recording
  Session for that device; startup failure remains a Scenario Recording failure.
- The issue tracker integration and triage label configuration are not present
  in the local workspace, so this PRD is currently maintained as a local
  document rather than published with a `ready-for-agent` label.
