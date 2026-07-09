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
FLUTTER_PILOT_RUNTIME=pilot_runtime \
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
FLUTTER_PILOT_RUNTIME=pilot_runtime \
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
FLUTTER_PILOT_RUNTIME=pilot_runtime \
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
FLUTTER_PILOT_RUNTIME=pilot_runtime \
  dart run ../../bin/flutter_pilot.dart test pilot/pilot_runtime_scroll_non_scrollable.yaml \
  --target lib/pilot_runtime_scroll_demo.dart \
  --device macos
```

Expected result:

- the Scenario fails at `scroll_read_only_text`
- the failure reason contains `does not identify a scrollable`
- failure diagnostics are still written under the run directory
