# Flutter Pilot Smoke App

This is the minimal Flutter app used by the real `mcp_flutter` smoke path.

Run it in debug mode:

```bash
cd examples/smoke_app
/Users/drown/development/flutter/bin/flutter run -d macos --debug
```

Copy the VM service websocket URI from Flutter output, then run from the repo
root:

```bash
dart run tool/run_mcp_flutter_smoke.dart ws://127.0.0.1:<port>/<token>/ws
```

The smoke script validates the Runtime Target with `flutter-mcp-toolkit`, then
runs `examples/smoke_scenario.yaml` through Flutter Pilot and prints the
generated `run_report.json` path.

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

## Optional CI

The real `mcp_flutter` smoke path is available as an opt-in GitHub Actions
workflow:

```text
Real mcp_flutter Smoke
```

It is triggered manually with `workflow_dispatch`; it is not part of the default
unit-test CI. The workflow starts this smoke app on a macOS runner, extracts the
VM service websocket URI from `flutter run --machine`, runs
`tool/run_mcp_flutter_smoke.dart`, and uploads `.runs` as workflow artifacts for
inspection.
