# Flutter Pilot Smoke App

This is the minimal Flutter app used by the real `pilot_runtime` smoke path.

Run it in debug mode:

```bash
cd examples/smoke_app
/Users/drown/development/flutter/bin/flutter run -d macos --debug
```

From `examples/smoke_app`, run the smoke Scenario. Flutter Pilot will launch
the app itself:

```bash
dart run ../../bin/flutter_pilot.dart test smoke_scenario.yaml --device macos
```

The run prints the generated `run_report.json` and `timeline.html` paths.

## PilotRuntimeAdapter Tap Acceptance

This app also includes a dedicated target for checking tap replay through the
real `pilot_runtime` binding.

From the repo root, install dependencies for the smoke app:

```bash
cd examples/smoke_app
/Users/drown/development/flutter/bin/flutter pub get
```

To inspect the UI manually, run the tap demo target on a debug device:

```bash
/Users/drown/development/flutter/bin/flutter run -d macos --debug -t lib/pilot_runtime_tap_demo.dart
```

Stop that manual run before executing Flutter Pilot. From `examples/smoke_app`,
run the passing Scenario; Flutter Pilot will launch the app itself:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/pilot_runtime_tap.yaml \
  --target lib/pilot_runtime_tap_demo.dart \
  --device macos
```

Expected result:

- the Scenario passes
- the semantic button increments `Semantic taps: 1`
- the pointer fallback target increments `Pointer taps: 1`
- the run writes `run_report.json` and `timeline.html`

To verify the failure path, run:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/pilot_runtime_non_tappable.yaml \
  --target lib/pilot_runtime_tap_demo.dart \
  --device macos
```

Expected result:

- the Scenario fails at `tap_read_only_text`
- the failure reason contains `cannot be tapped`
- failure diagnostics are still written under the run directory

## PilotRuntimeAdapter Scroll Acceptance

The smoke app includes a dedicated target for checking scroll replay through the
real `pilot_runtime` binding.

To inspect the UI manually, run the scroll demo target on a debug device:

```bash
/Users/drown/development/flutter/bin/flutter run -d macos --debug -t lib/pilot_runtime_scroll_demo.dart
```

Stop that manual run before executing Flutter Pilot. From `examples/smoke_app`,
run the passing Scenario; Flutter Pilot will launch the app itself:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/pilot_runtime_scroll.yaml \
  --target lib/pilot_runtime_scroll_demo.dart \
  --device macos
```

Expected result:

- the Scenario passes
- the list scrolls until `Scroll demo row 18` is visible
- the run writes `run_report.json` and `timeline.html`

To verify the failure path, run:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/pilot_runtime_scroll_non_scrollable.yaml \
  --target lib/pilot_runtime_scroll_demo.dart \
  --device macos
```

Expected result:

- the Scenario fails at `scroll_read_only_text`
- the failure reason contains `does not identify a scrollable`
- failure diagnostics are still written under the run directory

## PilotRuntime Replacement Calibration

The `pilot/calibration` Project Scenarios are the live replacement checks for
the `pilot_runtime` path. They run against one debug Target App Package target
and cover `byText`, semantic `byType`, `byKey`, `byWidget`, tap, type, targeted
scroll, untargeted scroll, Screenshot, Widget Tree, Logs, and Project Run hot
restart between Scenarios.

The calibration app routes `package:logging` records through `debugPrint`, so a
capture step should write a non-empty `.log` artifact.

Run the macOS desktop debug calibration from `examples/smoke_app`:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/calibration \
  --target lib/pilot_runtime_calibration_app.dart \
  --device macos
```

Run the Android debug calibration by replacing the device id with a connected
debug device:

```bash
dart run ../../bin/flutter_pilot.dart test pilot/calibration \
  --target lib/pilot_runtime_calibration_app.dart \
  --device <android-device-id>
```

Expected Project Run result:

- `01_interact.yaml` passes and writes Screenshot, Widget Tree, and Logs
  artifacts.
- Flutter Pilot hot restarts the Target App Package before
  `02_after_restart.yaml`.
- `02_after_restart.yaml` sees `Calibration taps: 0`, proving the restart reset
  app state while `PilotRuntimeBinding` and capture still work.
- The Project Run writes `project_run_report.json`; each Scenario Run writes
  `run_report.json` and `timeline.html`.

Calibration output should record:

- platform: macOS desktop debug or Android debug
- Flutter SDK version
- selected Target Device id
- exact command
- observed Project Run result and artifact paths
- any unsupported capability or platform-specific difference

Web, profile, release, and iOS are not claimed by v1. These examples do not
change Flutter Pilot runtime selection behavior; they only provide a focused
Project Run for live `pilot_runtime` calibration.
