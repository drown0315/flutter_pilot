# Flutter Pilot PRD

## Problem Statement

Flutter teams and AI coding agents need a reliable way to reproduce UI bugs, capture the runtime context around failures, and verify fixes without manually driving the app each time. Today, a bug report often contains a screenshot, a vague reproduction path, and scattered logs. That is not enough for an AI agent to locate the relevant widget, understand the visible UI state, or prove that a fix changed the right behavior.

The project should provide a deterministic UI replay and diagnostics harness for Flutter apps. It should use `mcp_flutter` as the runtime bridge, then add a scenario DSL, artifact collection, reporting, and diffing layer above it.

## Solution

Flutter Pilot will be a CLI tool that executes YAML scenarios against a Flutter app through `mcp_flutter`. A scenario describes user actions such as tapping, typing, scrolling, waiting for UI state, and capture checkpoints. Runtime connection details are not embedded in the scenario. The `test` command launches the current Target App Package with `flutter run --machine`, shows Target App Launch Progress while waiting for the Runtime Target URI from Flutter's machine output, runs the Scenario with Step progress, and cleans up the launched app process. During a run, Flutter Pilot records step-level artifacts including screenshots, semantic snapshots, widget summaries, logs that include runtime errors when available, timing, and command results.

The user-facing execution command is `flutter_pilot test <scenario.yaml>`. The previous `run` command and user-supplied VM service URI mode are removed. `test --target` follows Flutter CLI vocabulary and selects the Flutter app entrypoint file, while `--device` selects the Target Device and `--flavor` selects the Flutter flavor.

The first product milestone focuses on six capabilities:

1. YAML replay
2. Step screenshots and semantic snapshots
3. Failure artifact bundle
4. `--until` and `--print` debugging controls
5. HTML timeline report
6. Before/after diff

The result is a reproducible bug report package that can be consumed by humans, CI, or AI agents.

## User Stories

1. As a Flutter developer, I want to describe a UI reproduction path in YAML, so that I can replay the same bug consistently.
2. As a Flutter developer, I want to tap widgets by visible text, so that simple scenarios are easy to write.
3. As a Flutter developer, I want future key-based Finders to remain possible if `mcp_flutter` exposes stable key data, so that scenarios can become more resilient when text changes.
4. As a Flutter developer, I want to tap widgets by semantic node type, so that I can interact with UI elements by the role exposed through `mcp_flutter`.
5. As a Flutter developer, I want to combine text and semantic node type Finders in one step, so that I can disambiguate similar widgets.
6. As a Flutter developer, I want combined Finders to always use all constraints without a configurable `match` field, so that Scenario behavior is predictable and the YAML stays compact.
7. As a Flutter developer, I want to type text into fields by text Finder or semantic node type, so that form-based bugs can be reproduced.
8. As a Flutter developer, I want to scroll a view from a scenario step, so that off-screen UI can be reached.
9. As a Flutter developer, I want to wait for visible text or UI state, so that replay does not depend on fixed sleeps.
10. As a Flutter developer, I want each scenario step to have a label, so that I can reference meaningful checkpoints from CLI commands.
11. As a Flutter developer, I want to stop a run at a named step, so that I can inspect the app at the exact point where a bug begins.
12. As a Flutter developer, I want to stop a run at a numeric step, so that quick ad hoc debugging does not require editing YAML.
13. As a Flutter developer, I want to print the current widget information after a chosen step, so that I can diagnose layout and state issues from the terminal.
14. As a Flutter developer, I want to print the current semantic snapshot after a chosen step, so that I can give an AI agent compact UI context.
15. As a Flutter developer, I want to capture a screenshot after any step, so that visual state is recorded alongside the action that produced it.
16. As a Flutter developer, I want screenshots to be stored with step numbers and labels, so that artifacts are easy to navigate.
17. As a Flutter developer, I want semantic snapshots to be stored with step numbers and labels, so that AI agents can reason about the visible UI.
18. As a Flutter developer, I want widget summaries instead of only raw widget tree dumps, so that diagnostic output is readable and focused.
19. As a Flutter developer, I want logs collected during the run, including runtime errors when available, so that assertions, debug output, and failures can be correlated with UI steps.
20. As a Flutter developer, I want runtime failures represented in the same diagnostic stream as logs, so that I do not need to reason about overlapping artifact types in the first version.
21. As a Flutter developer, I want the tool to automatically collect diagnostics when a step fails, so that I do not need to predict where to add captures.
22. As a Flutter developer, I want a failure artifact bundle, so that I can attach a complete reproduction package to an issue.
23. As a Flutter developer, I want the artifact bundle to include the scenario, screenshots, snapshots, logs, device metadata, and run report, so that debugging context is portable.
24. As a Flutter developer, I want a structured run report, so that other tools and AI agents can parse the result.
25. As a Flutter developer, I want an HTML timeline report, so that I can review a run visually without reading JSON.
26. As a Flutter developer, I want each timeline entry to show the action, status, duration, screenshot, and diagnostics, so that failures are easy to inspect.
27. As a Flutter developer, I want failed steps to be highlighted in the timeline report, so that I can quickly find the relevant state.
28. As a Flutter developer, I want to run the same scenario before and after a code change, so that I can verify a bug fix.
29. As a Flutter developer, I want to diff before and after runs, so that I can see whether screenshots, visible text, logs, or widget summaries changed.
30. As a Flutter developer, I want the diff report to identify resolved runtime failures from logs, so that I can prove a runtime failure disappeared.
31. As a Flutter developer, I want the diff report to identify unexpected UI changes, so that I can catch regressions introduced by a fix.
32. As an AI coding agent, I want a compact summary of the visible UI, interactive widgets, logs, and recent actions, so that I can locate likely source files more effectively.
33. As an AI coding agent, I want a deterministic command to reproduce the current failure, so that I can iterate on a fix without manual interaction.
34. As an AI coding agent, I want to run until a failing checkpoint and print the current UI context, so that I can inspect the state before editing code.
35. As an AI coding agent, I want artifacts to be stable file paths with machine-readable metadata, so that I can consume them programmatically.
36. As a QA engineer, I want scenario runs to fail with clear exit codes, so that Flutter Pilot can be used in automation.
37. As a QA engineer, I want artifacts produced even on failed runs, so that CI failures are debuggable.
38. As a QA engineer, I want a human-readable report generated from CI artifacts, so that failures can be reviewed without rerunning locally.
39. As a tech lead, I want Flutter Pilot to build on `mcp_flutter`, so that the project benefits from existing Flutter runtime inspection, screenshots, interactions, logs, and lifecycle tools.
40. As a tech lead, I want Flutter Pilot to avoid reimplementing Flutter driver internals, so that the project stays focused on replay, reporting, and agent-ready diagnostics.
41. As a contributor, I want the scenario parser and runner to be testable without a live Flutter app, so that the core behavior can be developed quickly.
42. As a contributor, I want the `mcp_flutter` integration hidden behind a narrow interface, so that command mapping can evolve without changing the scenario model.
43. As a contributor, I want artifact writing to be isolated in one module, so that report generation and bundle layout remain consistent.

## Implementation Decisions

- Build Flutter Pilot as a CLI-first tool. The primary user interface is `flutter_pilot`.
- Implement the first version as a Dart CLI package, not a Flutter app. The expected project shape includes `bin/`, `lib/`, `test/`, and `pubspec.yaml`.
- The package and executable name is `flutter_pilot`.
- Third-party Dart dependencies must be added with `dart pub add`, not by manually editing dependency entries in `pubspec.yaml`.
- First-slice runtime dependencies are `args`, `yaml`, and `path`. First-slice dev dependencies are `test` and `lints`.
- The first implementation slice has been scaffolded as a Dart CLI package with command entrypoint, Scenario model, Scenario parser, validation exception shape, parser tests, and CLI subprocess tests.
- Code should follow the local Dart code conventions captured during review: important local variables use explicit types, stateless utility classes expose static methods with a private constructor, parser APIs return typed domain objects on success and throw domain validation exceptions on failure, boolean CLI flags avoid meaningless negative forms, and every code file contains useful doc comments.
- Use `mcp_flutter` as the runtime bridge for Flutter interaction and inspection. Flutter Pilot does not reimplement low-level app driving, widget inspection, screenshot capture, log collection, or lifecycle controls.
- The MVP command set includes:
  - `flutter_pilot validate <scenario.yaml>`
  - `flutter_pilot test <scenario.yaml>`
  - `flutter_pilot test <scenario.yaml> --device <device-id-or-name>`
  - `flutter_pilot test <scenario.yaml> --flavor <flavor> --target <entrypoint.dart>`
  - `flutter_pilot test <scenario.yaml> --until <step-or-label>`
  - `flutter_pilot test <scenario.yaml> --until <step-or-label> --print <snapshot|widget-tree|errors>`
  - `flutter_pilot test <scenario.yaml> --until <step-or-label> --print <snapshot|widget-tree|errors> --json`
  - `flutter_pilot report <run-directory>`
  - `flutter_pilot diff <before-run> <after-run>`
- The `validate` command checks Scenario YAML and schema rules without connecting to a Runtime Target.
- The `validate` command supports human-readable output by default and machine-readable JSON output with `--json`. Validation failures exit non-zero and include field paths such as `steps[2].tap.byText`.
- First-version `validate` and `test` read Scenario YAML from file paths only. Reading from stdin is out of scope for the first version.
- The first version includes an example Scenario file that exercises the core schema, including `type`, combined Finders, `waitFor`, and `capture`.
- First-version validation diagnostics include field paths but not YAML line or column numbers. The typed Scenario model does not carry source location metadata.
- Validation should collect and report all schema-level errors when safe to continue. YAML parse errors may return a single parse error because the document cannot be traversed reliably.
- Scenario parsing succeeds by returning a typed Scenario model. Validation failures are represented by a domain validation exception that carries structured validation errors. Callers such as the CLI decide whether to render those errors as human-readable lines or JSON.
- Unknown fields are validation errors. The Scenario DSL uses a strict schema so typos and unsupported options fail clearly instead of being ignored.
- `scenario.description` is optional metadata. When present, it must be a string and may use YAML multiline string syntax.
- `scenario.name`, when present, must match `^[a-zA-Z0-9][a-zA-Z0-9_-]*$`. This keeps run directory names portable and prevents path-like values. Names derived from file names must be sanitized to the same safe form.
- The YAML scenario format is the product contract. It should support scenario metadata, ordered steps, optional labels, capture directives, and Finders by text and semantic node type. Multiple `by*` Finder constraints may be used in one step, and all constraints must match. Each `byText` and `byType` value is a single string, not an array. The YAML does not expose a `match` option. Runtime target configuration is produced by the `test` launch flow, while Target Device, flavor, and entrypoint choices are CLI options so scenarios remain portable across machines, devices, and CI.
- Each Step is one item in the `steps` array. A Step may include a `label` field and must include exactly one action field. Items in `steps` may also be Step Includes (`include:` key) that reference Step Library YAML files; includes are expanded at parse time into a flat Step list. The `label` field is a sibling of the action field, not a nested action parameter.
- The typed action model uses a sealed class hierarchy so each Step has exactly one strongly typed action and runner/report code can handle actions exhaustively.
- Finder is a typed value object shared by actions. `tap`, `type`, and `waitFor` require at least one Finder field; `scroll` may omit Finder; `capture` does not use Finder.
- The Scenario parser is stateless and should be exposed as static parsing functions rather than requiring callers to instantiate a parser object.
- Step labels, when present, must use the same slug-like format as `scenario.name`: `^[a-zA-Z0-9][a-zA-Z0-9_-]*$`.
- Step labels must be unique within a Scenario (checked after include expansion). Unlabeled Steps are allowed.
- `--until <step-or-label>` executes through the target Step and stops after that Step completes.
- Numeric `--until` values are 1-based Step numbers.
- `--print` must be used with `--until` in the first version. It prints the requested diagnostics after the target Step completes.
- First-version `--print` values are `snapshot`, `widget-tree`, and `errors`. The option may be repeated to print several diagnostics after the same stopped Step. When multiple diagnostics are requested, output order is fixed as `snapshot`, `widget-tree`, then `errors`. By default, `--print` renders human-readable diagnostic text. With `--json`, it prints the raw diagnostic payload as indented JSON. Screenshots are file artifacts and are not printed to stdout.
- `test` prints Target App Launch Progress before Step progress for human-readable executions. Launch progress includes launch choices when known, elapsed launch time, heartbeat output for non-interactive runs, a final launch success summary, and a concise failure summary with the buffered Flutter stderr tail when launch fails.
- `test` prints concise Step progress after the Runtime Target is available for human-readable executions. Progress includes Scenario name, Step count, optional `--until` target, Step number, action, Step label or `-` when unlabeled, status, duration, concise failure reason when a Step fails, and include source file path (e.g. `[flows/login.yaml]`) for Steps expanded from Step Libraries.
- Target App Launch Progress and Step progress are presentation behavior owned by the CLI, not Scenario semantics, artifact format, or Runtime Adapter contract. The launcher and runner should expose progress events or callbacks so CLI rendering stays separate from execution.
- Human-readable Target App Launch Progress and Step progress are written to stderr. Final artifact locations such as `Run report:` and `HTML report:` stay on stdout so scripts can continue to consume result paths.
- `test --json` suppresses Target App Launch Progress and Step progress because JSON output is intended for machine consumption.
- Interactive terminals may render Step progress with color, emoji, bold text, and in-place line refresh from `running` to the final status. Non-interactive output must degrade to deterministic plain text lines suitable for CI logs and CLI subprocess tests.
- Step progress displays elapsed Step duration on completion, such as `ok 118ms` or `failed after 3004ms`.
- Step progress uses only Step started and Step finished events from the runner. The CLI already knows Scenario name, target, total Step count, and `--until` before execution, and it receives artifact paths from the final run report after execution.
- Step progress lines should align known action names in a fixed action column and align labels in a per-Scenario label column capped at a small maximum width. Unlabeled Steps render as `-`; labels or failure summaries that would make output noisy are truncated in progress output only.
- Failure progress shows a concise single-line summary. Newlines are collapsed and long messages are truncated for terminal readability, while the full failure reason remains unchanged in `run_report.json` and diagnostic artifacts.
- When `--until` stops a successful run after the requested Step, human-readable output should clearly state that the run stopped because of `--until`, and not present skipped later Steps as failures.
- ANSI styling and emoji capability should start as an internal Flutter Pilot CLI presentation module rather than a separate package. Keep it isolated and Flutter Pilot agnostic where practical, so it can later be extracted if another package such as `screen_recorder` needs the same terminal styling primitives.
- Flutter Pilot's Step progress renderer owns the progress event wording, Step layout, artifact summary lines, and JSON suppression rules.
- Flutter Pilot's Target App Launch Progress renderer owns launch wording, launch choices, heartbeat wording, elapsed-time display, interactive refresh, success summaries, failure summaries, and JSON suppression rules.
- Human-readable stderr summary should state `Run passed.`, `Run failed at ...`, or `Stopped after ... due to --until.` as appropriate. Stdout keeps the stable existing `Run report:` and `HTML report:` lines for scripts and smoke verification.
- CLI subprocess tests may select an in-process fake Runtime Adapter through a test-only environment variable such as `FLUTTER_PILOT_TEST_RUNTIME`. This hook must not appear in `--help` output or become part of the public CLI contract.
- `byKey` is not part of the current Scenario DSL because the calibrated `mcp_flutter` semantic Snapshot path does not expose Flutter key values reliably. Key-based Finders may be added later if the Runtime Adapter can obtain stable key data.
- `byType` accepts the `mcp_flutter` semantic Snapshot node type, such as `textField`, `button`, `text`, `scrollable`, or `header`. It does not accept Dart widget class names such as `TextField`, `FilledButton`, or app-defined wrapper widget classes.
- `byText` matches exact visible text. It does not perform contains, fuzzy, or regular expression matching in the first version.
- A Finder must resolve to exactly one widget before an action can execute. Zero matches fail the step as "Finder matched no widgets"; multiple matches fail the step as "Finder matched multiple widgets." Flutter Pilot does not automatically choose the first match.
- The initial action set includes `tap`, `type`, `scroll`, `waitFor`, and `capture`.
- The `type` action means replacing text in a widget: clear existing text, then enter the configured text. It is distinct from the `byType` Finder constraint.
- The `waitFor` action waits for a Finder to produce exactly one match before its timeout. Zero matches keep waiting until timeout, one match succeeds, and multiple matches fail the step. The first version does not support waiting for disappearance, enabled state, or disabled state.
- `waitFor.timeoutMs` defaults to `3000` when omitted. The first version supports per-step timeout overrides but no global timeout defaults in the Scenario.
- The `scroll` action accepts `deltaX` and `deltaY` as gesture drag deltas in logical pixels. Omitted deltas default to `0`. For example, `deltaY: -500` means dragging upward by 500 logical pixels, which usually reveals lower content. A Finder is optional for `scroll`; when omitted, Flutter Pilot scrolls the primary scrollable. When provided, the Finder must resolve to exactly one scrollable target. At least one of `deltaX` or `deltaY` must be non-zero, so `scroll: {}` and zero-delta scrolls are invalid.
- Capture directives support screenshots, semantic snapshots, widget summaries, logs, and labels. Runtime errors are collected as part of logs in the first version.
- Failed steps automatically trigger diagnostic capture even if the YAML did not request a capture at that point.
- Scenario execution produces a run directory containing a structured run report, an HTML timeline report, aggregated Step metadata, and capture artifacts.
- `scenario.name` is metadata and does not need to be globally unique. Run directories use minute-level timestamp plus scenario name, such as `.runs/2026-06-06_12-30_login_error/`, to avoid overwrites and preserve chronological sorting.
- When `scenario.name` is omitted, Flutter Pilot derives the run name from the Scenario file name. If no file name is available, it falls back to `scenario`.
- Artifact bundle layout is stable and intended for both humans and AI agents.
- The run report is JSON and records scenario metadata, runtime target metadata, Target Device metadata when available, steps, command inputs, command outputs, status, duration, artifact paths, failure diagnostics, and compact diagnostic summaries when printable diagnostics are collected.
- `test` generates `run_report.json` and `timeline.html` by default. There is no separate `--html` flag.
- Step metadata is written as one aggregated `step.json` file containing all Step report records, rather than one JSON file per Step. The same Step results remain embedded in `run_report.json`.
- The first runner slice writes artifacts under stable `.runs/<timestamp>_<scenario>/` directories and records artifact paths relative to the run directory.
- The HTML timeline report is generated from the run report and artifacts, not by rerunning the scenario. `flutter_pilot report <run-directory>` regenerates `timeline.html` from an existing run directory.
- The diff command compares two run directories. It reports changes in step status, screenshots, visible text, semantic snapshots, widget summaries, and logs.
- A Screenshot is a visual image artifact for human review. A Snapshot is a structured UI state artifact for programmatic and agent consumption. A Widget Tree is a raw or near-raw Flutter hierarchy artifact for deeper debugging.
- Snapshot capture is enabled by default for capture checkpoints. Widget Tree capture is available but disabled by default because it can be large and noisy.
- The `capture` action records diagnostic artifacts at a Step. `capture: {}` uses the default bundle: `screenshot: true`, `snapshot: true`, `widgetTree: false`, and `logs: true`. Each option can be explicitly overridden.
- Failed Steps automatically capture the same default bundle as `capture: {}`.
- Raw Widget Tree dumps may be available, but agent-facing output should default to compact summaries of visible text, interactive widgets, routes, logs, runtime failures, and likely suspects. The Diagnostic Reducer writes this summary as `diagnosticSummary` in the run report when `--print` captures raw Snapshot, Widget Tree, or error diagnostics.
- Scenario-level device video recording is supported as an optional run-level artifact. When recording is enabled, `test` requires the selected Target Device to also be available as a Recording Device with the same device id. The Device Video Recording is stored under the run directory as `artifacts/device-video-recording.<ext>` and recorded in reports with a run-directory-relative path. Richer recording parameters remain out of scope. Step screenshots and timeline reports remain the primary step-level visual artifacts.
- The implementation should be organized around deep modules:
  - Scenario model and parser: validates YAML and produces a typed scenario.
  - Finder and action model: represents user intent independently from `mcp_flutter` command details.
  - Runner engine: executes steps, handles `--until`, applies waits, records status, and triggers captures.
  - `mcp_flutter` adapter: maps high-level actions and capture requests to `mcp_flutter`. Prefer an available API/SDK call path; use CLI subprocess execution only as a fallback when the API path is unavailable or insufficient.
  - Artifact store: owns run directory layout and artifact metadata.
  - Diagnostic reducer: turns large widget and semantic data into agent-friendly summaries.
  - Report generator: builds JSON and HTML reports from run results.
  - Diff engine: compares two run directories and produces structured and human-readable diffs.
  - CLI surface: parses commands, options, exit codes, and output formatting.

## Development Priority

1. CLI skeleton and scenario parser
   - Establish the executable entry point, command structure, YAML schema, validation errors, typed scenario model, and minimal test suite.
   - The first slice included working `validate` behavior and an execution command shell that parsed arguments, validated the Scenario, checked CLI rules, and reported that UI execution was not implemented yet.
   - The current execution command is `test`; the earlier `run` shell has been removed from the public CLI.
   - This comes first because every later feature depends on a stable scenario contract and command surface.
2. `mcp_flutter` adapter contract
   - Define the narrow interface for tap, type, scroll, wait, screenshot, semantic snapshot, widget data, and logs.
   - Add a fake adapter for tests before wiring real commands, so runner behavior can be developed without a live Flutter app.
   - Manually calibrate `mcp_flutter` before locking the implementation path. Check whether API calls are available and whether they expose richer structured data than CLI output; use API shape as the primary reference while keeping runner-facing types inside Flutter Pilot's own model. The same calibration should verify discovery, screenshot, semantic snapshot, Logs, Finder by text/key/type, multiple Finder Match descriptions, WidgetBounds availability, and scroll without Finder.
3. Runner engine with YAML replay
   - Execute ordered steps through the adapter, record step status, durations, command results, and exit codes.
   - Support the initial action set: `tap`, `type`, `scroll`, and `waitFor`.
4. Artifact store and structured run report
   - Create stable run directories, persist scenario copies, aggregated Step metadata, command outputs, and `run_report.json`.
   - This should land before richer captures so every feature has a consistent place to write artifacts.
5. Capture checkpoints: screenshots and semantic snapshots
   - Implement explicit `capture` steps and optional per-step capture configuration.
   - Store screenshots and semantic snapshots with step numbers and labels, referenced from the run report.
6. Failure artifact bundle
   - On failed steps, automatically collect screenshot, semantic snapshot, widget summary, logs, and device or target metadata.
   - This is the first major user-facing debugging win and should be complete before report polish.
7. `--until` and `--print`
   - Support stopping at numeric or labeled steps and printing `snapshot`, `widget-tree`, `errors`, or any repeated combination of those values in fixed output order.
   - This builds on the runner, capture, and diagnostic plumbing and makes the tool useful for iterative human and agent debugging.
8. Diagnostic reducer
   - Convert raw widget, semantic, and log data into compact agent-friendly summaries of visible text, interactive widgets, routes, logs, runtime failures, and likely suspects.
   - This should follow raw capture support because reducer tests need realistic captured fixtures.
9. HTML timeline report
   - Generate `timeline.html` by default from existing run artifacts, with step status, action descriptions, screenshots, diagnostics, and failure highlights.
   - Provide `report <run-directory>` to regenerate the HTML report from existing artifacts without rerunning the Scenario.
   - This is high-value for sharing but should not block the core replay and artifact model.
10. Before/after diff
   - Compare two run directories for status changes, visible text changes, semantic/widget summary changes, screenshot differences, resolved runtime failures from logs, and regressions.
   - This comes after reports and reducers because it depends on stable artifact formats and summary data.
11. Real integration smoke test with a sample Flutter app
   - Add a minimal sample app and one end-to-end scenario to validate the real `mcp_flutter` path.
   - Keep most coverage in unit and contract tests; use this as a final confidence check for the MVP.

## Testing Decisions

- Tests should focus on external behavior and stable contracts, not private implementation details.
- First-slice tests already establish the baseline testing style: parser tests call the public parser API and assert on typed Scenario output or structured validation exceptions; CLI tests execute the command through a real Dart subprocess and assert on exit codes and terminal output.
- The scenario model and parser should have unit tests for valid YAML, invalid YAML, labels, capture directives, Finders, unsupported actions, combined Finder constraints, rejection of array-valued Finder fields, rejection of unlabeled Step items that only contain a label, and rejection of Steps with multiple action fields.
- First-slice tests should be split between parser/model unit tests and a small number of CLI subprocess tests. Parser/model tests cover detailed schema behavior. CLI subprocess tests cover external command behavior such as `validate`, `validate --json`, `test` command-shell behavior, and CLI argument errors.
- The runner engine should have tests using a fake `mcp_flutter` adapter. These tests should verify step ordering, failure handling, automatic capture, `--until`, `--print`, zero Finder matches, one Finder match, multiple Finder matches, `waitFor` success, `waitFor` timeout, `waitFor` multiple-match failure, `scroll` with a Finder, `scroll` without a Finder, and `scroll` delta validation.
- The artifact store should have tests verifying stable run directory layout, artifact naming, metadata references, and report paths.
- The diagnostic reducer should have tests using representative widget and semantic data fixtures. Tests should verify that visible text, interactive widgets, logs, runtime failures, and route-like context are preserved while noisy details are removed.
- The report generator should have tests verifying JSON report shape and HTML timeline content from fixed run fixtures.
- The diff engine should have tests comparing fixed before/after fixtures for resolved runtime failures from logs, changed visible text, missing steps, changed screenshots, and unchanged runs.
- The `mcp_flutter` adapter should be covered by contract tests where practical. Most behavior should be tested through mocked command responses to avoid requiring a live Flutter app in unit tests.
- End-to-end tests with a sample Flutter app are valuable after the core CLI exists, but they are not required for the first parser and runner slices.
- There is no prior test suite in the current repository, so test conventions should be established as part of the initial implementation.

## Out of Scope

- Rich video recording configuration is not part of the MVP beyond the first-slice Scenario-level recording toggle.
- Natural language scenario generation is not part of the MVP.
- Interactive recording of manual app usage into YAML is not part of the MVP.
- Automatic source-code patching is not part of this PRD.
- Full visual regression testing infrastructure is not part of the MVP beyond before/after run diffing.
- Replacing `mcp_flutter` or building a custom Flutter VM service integration is out of scope.
- Supporting every possible Flutter widget Finder in the first release is out of scope.
- Cloud artifact hosting and team dashboard features are out of scope.

## Further Notes

- The project now has the first Dart CLI slice in place. The next product risk is no longer YAML parsing; it is defining the narrow `mcp_flutter` adapter contract and keeping runner behavior testable without a live Flutter app.
- The strongest product positioning is not "YAML UI automation"; it is "reproducible Flutter UI debugging artifacts for humans, CI, and AI agents."
- Step screenshots are more useful than video for the initial AI-agent use case because they can be directly associated with step metadata, widget summaries, logs, and runtime failures. Scenario-level video recording is complementary run context rather than a replacement for step-owned captures.
- The tool should keep raw data available for advanced debugging, but default CLI and agent output should be compact and high signal.
- The `ready-for-agent` label should be applied when this PRD is published to the issue tracker.
- The issue tracker integration and triage label configuration are not present in the local workspace, so this PRD is maintained as a local document until publishing credentials and tracker conventions are available.
