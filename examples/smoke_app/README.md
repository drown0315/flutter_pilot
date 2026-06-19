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
