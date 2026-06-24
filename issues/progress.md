# Flutter Pilot Issue Progress

Last reviewed: 2026-06-20

This file tracks implementation progress against the local issue breakdown and
the GitHub issue list. Use code reality as the source of truth when GitHub issue
state diverges from the repository.

## GitHub Issue State

GitHub currently contains two duplicated issue sets:

- `#1` through `#14` are open.
- `#15` through `#28` mirror the same work. `#15` through `#27` are closed, and
  `#28` is open.

When cleaning up GitHub, prefer closing or reconciling the duplicate open issues
only after checking the code completion status below.

## Completion By Code Reality

| Local issue | GitHub duplicates | Status | Notes |
| --- | --- | --- | --- |
| 1. Define Runtime Adapter Contract | `#1`, `#15` | Complete | Runtime Adapter contract, Runtime Target, Finder Match, capture models, fake adapter, contract tests, and calibration notes exist. |
| 2. Replay Successful Scenario And Write Basic Run Report | `#2`, `#16` | Complete | `ScenarioRunner` executes successful steps through the adapter and writes `run_report.json`. CLI still uses an unimplemented default adapter until the real `mcp_flutter` adapter lands. |
| 3. Enforce Finder Match Cardinality | `#3`, `#17` | Complete | Zero matches fail, one match executes, multiple matches fail, and failure reasons are recorded in the run report. |
| 4. Implement WaitFor Timing Behavior | `#4`, `#18` | Complete | `waitFor` polls until exactly one Finder Match appears, fails when the timeout expires with zero matches, and fails immediately when multiple matches appear. |
| 5. Create Stable Run Directories And Artifact Metadata | `#5`, `#19` | Complete | Artifact Store creates stable `.runs/<timestamp>_<scenario>/` directories, avoids overwriting repeated runs, writes `scenario.json`, writes aggregated Step metadata to `step.json`, writes `run_report.json`, records artifact paths in the report, and keeps runner execution flow split into initialization, Step execution, cleanup, and report finalization. |
| 6. Capture Screenshots And Snapshots | `#6`, `#20` | Complete | Capture Steps write screenshot PNG files and Snapshot JSON files under `captures/`, attach those artifact paths to the producing Step, and include them in the run report artifact index. |
| 7. Capture Errors And Logs | `#7`, `#21` | Complete | Capture Steps write Logs JSON files under `captures/`, attach those artifact paths to the producing Step, include them in the run report artifact index, and respect explicit `logs: false` overrides. Runtime errors remain part of Logs when the adapter exposes them. |
| 8. Produce Failure Artifact Bundles | `#8`, `#22` | Complete | Failed Steps automatically collect screenshot, Snapshot, and Logs artifacts, mark those artifact records with `purpose: failure`, keep Widget Tree disabled by default, and failed runs exit non-zero through the CLI. |
| 9. Implement Real `--until` Stop Points | `#9`, `#23` | Complete | CLI validates `--until`, runner executes through the selected Step number or label, and later Steps are represented as skipped in the run report. |
| 10. Implement `--print` Diagnostics After `--until` | `#10`, `#24` | Complete | `--print` requires `--until`, supports repeated `snapshot`, `widget-tree`, and `errors` diagnostics after the stopped Step, prints a single JSON object in fixed Snapshot, Widget Tree, Errors order, records printed diagnostics in the run report, and still rejects screenshot stdout output. |
| 11. Add Diagnostic Reducer | `#11`, `#25` | Complete | Added a public Diagnostic Reducer that turns raw Snapshot, Widget Tree, and Logs payloads into compact summaries of visible text, interactive widgets, routes, useful logs, runtime failures, and likely suspects. `--print` runs now also store the reduced `diagnosticSummary` in `run_report.json`. |
| 12. Generate HTML Timeline Report | `#12`, `#26` | Complete | `run` now generates `timeline.html` by default, records an `htmlReport` artifact in `run_report.json`, renders Step action/status/duration/failure details with screenshot previews and JSON artifact links, and `report <run-directory>` regenerates HTML from existing run artifacts without replaying the Scenario. Implemented in commit `79009df`. |
| 13. Compare Before/After Run Directories | `#13`, `#27` | Complete | `diff <before-run> <after-run>` now compares Step outcomes, run-level visible text, runtime failures, and Screenshot artifact presence/hash changes from `run_report.json`, diagnostic summaries, Snapshot artifacts, Logs artifacts, and Step Screenshot artifacts. It prints human-readable output or `--json`, reports warnings, Regressions, resolved Steps, missing Steps, added Steps, action changes, visible text changes, resolved runtime failures, new runtime failure Regressions, Screenshot changes, detailed Step identities, and overall outcomes, preserves exit code `0` for successful diff generation even with Regressions, and includes user documentation plus fixed acceptance fixtures. |
| 14. Add Real Flutter Smoke Scenario Through `mcp_flutter` | `#14`, `#28` | Complete | Added `examples/smoke_app`, `examples/smoke_scenario.yaml`, a real `McpFlutterRuntimeAdapter`, and `tool/run_mcp_flutter_smoke.dart`. A local macOS smoke run passed and wrote snapshot/log artifacts plus `run_report.json`. |

## Recommended GitHub Cleanup

- Close duplicate open issues `#1`, `#2`, and `#3` if they correspond to the
  completed work already represented by closed issues `#15`, `#16`, and `#17`.
- Keep `#4` through `#14` open unless their duplicated closed issues were closed
  intentionally for a non-code reason.

## Screen Recorder 0.0.4 Progress

Source: `issues/0.0.4-screen-recorder.md`

| Local issue | GitHub issue | Status | Notes |
| --- | --- | --- | --- |
| 1. Scaffold `screen_recorder` Core API With Fake Backend | `#58` | Complete | Independent `packages/screen_recorder` Dart package exists with public library API, fake backend, Recording Device/Session/Result models, output naming rules, stable `ScreenRecorderException` codes, same-device active recording rejection, discard behavior, and package tests. Implemented in commit `6186234`. |
| 2. Add Android Recording Device Support Through ADB | `#59` | Complete | Android backend discovers online ADB devices, resolves selectors by id/name/case-insensitive name prefix, starts `adb shell screenrecord` to a device-side temporary MP4, stops by killing the managed process, pulls the final local `.mp4`, cleans device-side temp files, discards without pulling, and reports missing ADB or pull failures through stable `ScreenRecorderException` codes with raw output. |
| 3. Add iOS Simulator Recording Device Support Through `simctl` | `#60` | Complete | iOS Simulator backend discovers available simulators from `xcrun simctl list devices`, resolves selectors by UDID/name/case-insensitive name prefix, starts `xcrun simctl io <device> recordVideo <output.mov>`, stops by signaling the managed process and verifying a non-empty local `.mov`, discards by stopping and deleting local output, and reports simctl or stop failures through stable `ScreenRecorderException` codes. |
| 4. Add Physical iOS Recording Device Support With Native Helper | `#61` | Complete | Physical iOS backend builds an in-package Swift helper, lists AVFoundation/CoreMediaIO iOS capture devices from helper TSV output, resolves selectors by native id/name/case-insensitive name prefix, starts the helper as a managed process with `record --device-id --output`, stops and verifies a non-empty local `.mov`, discards by stopping and deleting local output, and reports Swift toolchain, permission/helper, and stop failures through stable `ScreenRecorderException` codes. |
| 5. Wire Default Multi-Backend Recording Device Resolution Priority | `#62` | Complete | Default recorder wires Android, iOS Simulator, and physical iOS backends in fixed priority order, lists devices in that order, resolves selectors by exact id/name or case-insensitive name prefix, stops resolution at the first matching backend, supports platform filtering to narrow discovery, and surfaces device-not-found through stable `ScreenRecorderException` codes. |
| 6. Add Thin Interactive CLI For Recording Sessions | `#63` | Complete | Package exposes a `screen_recorder` executable and thin `ScreenRecorderCli` wrapper around the core API. The CLI starts a foreground recording from `--device`, optional `--output-directory`, and optional `--output-name`, maps `s` to `stopRecord` and prints `Saved recording: <path>`, maps `q` to discard without reporting a saved file, and renders `ScreenRecorderException` codes in errors. |
| 7. Add `screen_recorder` Documentation And Manual Smoke Checklist | `#64` | Complete | README documents the core API, CLI `s` save and `q` discard interaction, discovery priority, selector matching, platform filter, output naming and native formats, Android/iOS Simulator/physical iOS prerequisites, manual smoke checklists, and out-of-scope Flutter Pilot integration, Scenario YAML video actions, and VM service discovery. Documentation coverage is verified by package tests. |
