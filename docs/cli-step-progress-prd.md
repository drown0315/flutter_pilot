# CLI Step Progress PRD

## Problem Statement

When `flutter_pilot test` executes a Scenario, users do not get enough immediate
foreground feedback about Scenario execution. Long runs and failing runs are
harder to follow because users often need to wait for the final report or open a
run directory before they can see which Step ran, which Step succeeded, and
where execution failed.

Flutter Pilot needs live, readable CLI Step progress that helps humans and AI
agents understand Scenario execution as it happens without changing Scenario
YAML, run artifacts, or the Runtime Adapter contract.

## Solution

Add human-readable Step progress output to `flutter_pilot test`.

For non-JSON runs, Flutter Pilot should print a concise execution header,
per-Step progress, and a final human summary. Each Step should show Step number,
total Step count, action, Step Label or `-` when unlabeled, status, duration,
and concise failure reason when applicable.

Interactive terminals may use color, emoji, bold text, and in-place status
refresh from `running` to the final status. Non-interactive output must degrade
to deterministic plain text suitable for CI logs and subprocess tests.

Step progress is status output and should be written to stderr. Existing final
artifact path lines such as `Run report:` and `HTML report:` remain on stdout so
scripts and smoke verifiers can continue to consume them. `test --json` suppresses
Step progress because JSON output is for machine consumption.

## User Stories

1. As a Flutter developer, I want `flutter_pilot test` to show when a Scenario starts, so that I know the command is actively executing the selected Scenario.
2. As a Flutter developer, I want the Scenario name shown before Step execution, so that I can confirm I am running the intended Scenario.
3. As a Flutter developer, I want the total Step count shown before execution, so that I can estimate run progress.
4. As a Flutter developer, I want each Step to show its 1-based Step number and total Step count, so that I can locate progress in the Scenario.
5. As a Flutter developer, I want each Step to show its action, so that I can understand what Flutter Pilot is currently doing.
6. As a Flutter developer, I want each Step to show its Step Label when present, so that progress output matches the meaningful checkpoints in my Scenario.
7. As a Flutter developer, I want unlabeled Steps to render with a clear placeholder, so that progress output stays readable for lightweight Scenarios.
8. As a Flutter developer, I want to see a `running` status when a Step starts, so that long actions do not look like the command is stuck.
9. As a Flutter developer, I want to see `ok` when a Step succeeds, so that I can distinguish completed work from in-flight work.
10. As a Flutter developer, I want to see `failed` when a Step fails, so that I can immediately identify the failing Step.
11. As a Flutter developer, I want failed Step output to include a concise reason, so that I can understand the failure without opening the run directory first.
12. As a Flutter developer, I want full failure details to remain in `run_report.json` and artifacts, so that progress output can stay compact.
13. As a Flutter developer, I want Step duration displayed after completion, so that slow waits, captures, and interactions are visible.
14. As a Flutter developer, I want aligned progress columns, so that I can scan action, label, and status quickly.
15. As a Flutter developer, I want very long labels to be truncated in progress output, so that one Step cannot destroy the readability of the whole run.
16. As a Flutter developer, I want very long failure summaries to be truncated in progress output, so that logs and stack traces do not flood the terminal.
17. As a Flutter developer, I want interactive terminal output to use color and emoji, so that important statuses are visually distinct.
18. As a Flutter developer, I want terminal output to update an active Step in place when possible, so that the display stays clean while a run is active.
19. As a Flutter developer, I want CI and redirected output to use deterministic plain text, so that logs are stable and easy to assert on.
20. As a Flutter developer, I want `--until` runs to show only executed Steps, so that progress reflects the actual execution path.
21. As a Flutter developer, I want a successful `--until` run to state that Flutter Pilot stopped because of `--until`, so that skipped later Steps are not mistaken for failures.
22. As a Flutter developer, I want complete successful runs to show `Run passed.`, so that the terminal summary is unambiguous.
23. As a Flutter developer, I want failed runs to show the failing Step identity in the final summary, so that I can jump to the right Scenario checkpoint.
24. As a Flutter developer, I want final artifact paths to stay visible after progress output, so that I can open the run report or HTML timeline.
25. As a QA engineer, I want progress written to stderr, so that stdout can remain stable for scripts that parse final artifact paths.
26. As a QA engineer, I want `Run report:` and `HTML report:` stdout lines to remain unchanged, so that existing automation keeps working.
27. As a QA engineer, I want `test --json` not to print progress, so that stdout remains valid machine-readable JSON when diagnostics are printed.
28. As a QA engineer, I want CLI subprocess tests for progress output, so that the real command-line contract is covered.
29. As a contributor, I want the runner to expose Step progress events instead of printing directly, so that execution logic stays separate from CLI presentation.
30. As a contributor, I want terminal styling isolated from progress wording, so that ANSI and emoji behavior can be tested independently.
31. As a contributor, I want the fake Runtime Adapter path available to CLI subprocess tests, so that progress behavior can be verified without a live Flutter app.
32. As an AI coding agent, I want stable non-JSON progress text in subprocess output, so that I can inspect failures without opening artifacts.
33. As an AI coding agent, I want JSON output to remain free of progress text, so that I can parse diagnostics programmatically.
34. As an AI coding agent, I want the final report paths to stay on stdout, so that I can reliably locate generated artifacts.

## Implementation Decisions

- This feature is CLI presentation behavior. It must not change Scenario YAML semantics, artifact formats, run report schema, or Runtime Adapter contracts unless a minimal progress callback type is needed in runner-facing code.
- The runner should expose Step progress through a small event or callback interface.
- The progress interface should use two Step event types: Step started and Step finished.
- Step started events should provide enough Step identity for the CLI to render Step number, action, and label.
- Step finished events should include final status, duration, and optional failure reason.
- The runner should not write to stdout or stderr directly.
- The CLI should decide whether progress is enabled.
- The CLI should suppress progress for `test --json`.
- Human-readable Step progress should be written to stderr.
- Existing stdout lines for final artifact paths should remain stable, including `Run report:` and `HTML report:`.
- The CLI should print a human-readable header before Step execution that includes Scenario name and total Step count.
- When `--until` is present, the human-readable header should include the requested stop point in a readable form.
- Progress lines should include Step number, total Step count, action, label placeholder, status, duration on completion, and include source file path (e.g. `[flows/login.yaml]`) for Steps expanded from Step Libraries.
- The label placeholder for unlabeled Steps should be `-`.
- Known action names should align in a fixed action column.
- Labels should align in a per-Scenario label column capped at a small maximum width.
- Long labels should be truncated only in progress output.
- Failure summaries should collapse newlines to spaces.
- Failure summaries should be truncated only in progress output.
- Full failure reasons should remain unchanged in run reports and diagnostic artifacts.
- Interactive terminals may use ANSI color, bold text, dim text, emoji, and in-place line refresh.
- Non-interactive output must use deterministic plain text without ANSI codes or emoji.
- Terminal styling and emoji support should start as an internal CLI presentation module, not as a separate package.
- The internal styling module should remain small and mostly Flutter Pilot agnostic so it can be extracted later if another package needs the same primitives.
- The Step progress renderer should stay in the main Flutter Pilot package and own the Step wording, layout, summary text, and JSON suppression behavior.
- Complete successful runs should print a human-readable `Run passed.` summary on stderr.
- Failed runs should print a human-readable `Run failed at ...` summary on stderr.
- Successful `--until` runs should print a human-readable `Stopped after ... due to --until.` summary on stderr.
- CLI subprocess tests may use a test-only environment variable such as `FLUTTER_PILOT_TEST_RUNTIME` to select a fake Runtime Adapter path.
- The test-only fake runtime hook must not appear in help output and must not become part of the public CLI contract.
- No new public CLI flags are needed for color, emoji, or fake runtime selection in the first version.
- No ADR is required for this feature because the decisions are CLI presentation and testability choices rather than hard-to-reverse architecture decisions.

## Testing Decisions

- Tests should verify public behavior and stable contracts, not private implementation details.
- CLI subprocess tests should exercise `flutter_pilot test` end to end with a fake Runtime Adapter selected through the test-only environment variable.
- CLI subprocess tests should verify successful Step progress.
- CLI subprocess tests should verify failed Step progress with Step identity and concise failure reason.
- CLI subprocess tests should verify unlabeled Step rendering.
- CLI subprocess tests should verify `--until` progress and stopped summary.
- CLI subprocess tests should verify that progress is written to stderr while final artifact paths remain on stdout.
- CLI subprocess tests should verify that `test --json` suppresses progress output.
- Renderer tests should verify deterministic plain-text output independent of terminal capabilities.
- Renderer tests should verify action and label alignment.
- Renderer tests should verify label truncation.
- Renderer tests should verify failure summary newline collapsing and truncation.
- Terminal styling tests should verify ANSI wrapping, disabled plain-text behavior, ANSI stripping, and emoji/capability behavior.
- Runner tests should verify that Step started and Step finished events are emitted in execution order.
- Runner tests should verify that failed Steps emit a finished event with failure status and reason.
- Runner tests should verify that `--until` emits events only for executed Steps.
- Existing CLI subprocess test style is the model: run the real Dart executable and assert exit codes, stdout, and stderr.
- Existing fake Runtime Adapter runner tests are the model for avoiding live Flutter app dependencies in core behavior tests.

## Out of Scope

- Changing Scenario YAML syntax.
- Changing Step Label validation or semantics.
- Changing Runtime Target configuration.
- Changing Runtime Adapter action contracts.
- Changing run report or artifact schemas.
- Adding public `--color`, `--no-color`, `--emoji`, `--no-emoji`, or `--quiet` flags.
- Printing progress during `test --json`.
- Adding screenshot output to stdout.
- Adding progress output to `validate`, `report`, `diff`, `doctor`, or `init`.
- Making terminal styling a standalone package in this slice.
- Replacing existing HTML timeline reports or artifact paths.

## Further Notes

- This PRD refines issue `#66 Improve CLI step progress output`.
- The feature should preserve the current machine-consumption path: stdout remains the place for final report paths and JSON diagnostics.
- The terminal display can be pleasant for humans without making CI and tests fragile, as long as TTY output and non-TTY output are separated.
- The internal terminal styling module should be kept narrow so extraction remains possible if the same styling primitives become useful to `screen_recorder` or another package.
