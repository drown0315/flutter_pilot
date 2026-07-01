# Target App Launch Progress PRD

## Problem Statement

`flutter_pilot test` can spend a long time before Scenario Steps begin because
it launches the Target App Package with `flutter run --machine`, waits for
Flutter build and install work, and only starts the Scenario after the Runtime
Target is available. During that launch window, users currently see little or no
foreground feedback from Flutter Pilot. A long Flutter build can therefore look
like the command is stuck, even though useful work is happening.

Users need immediate, quiet, and trustworthy Target App Launch Progress before
Step progress begins. They should know what Flutter Pilot is preparing, which
Target Device is being used when known, how long launch has been running, and
whether the command is still alive, without default output being flooded by raw
Flutter logs.

## Solution

Add Target App Launch Progress to `flutter_pilot test` for human-readable runs.
The launch progress appears before Step progress and covers the period from
preparing app launch through waiting for the Runtime Target URI. It is a
separate CLI presentation surface from Step progress because no Scenario Step
can execute until the Target App Package is running.

Interactive terminals show a compact loading panel with elapsed time and the
reliable launch stage. Non-interactive output degrades to deterministic plain
text with periodic heartbeat lines. `test --json` suppresses Target App Launch
Progress, matching Step progress behavior.

Default output should stay quiet and high signal. Flutter Pilot should show
launch choices such as Target Device, selection reason, flavor, and entrypoint,
but it should not print the full `flutter run --machine` command or raw Flutter
build logs by default. On successful launch, Flutter Pilot should leave one
summary line such as `Target App launched in 38s`, then begin Step progress. On
launch failure, Flutter Pilot should show a concise failure summary and the last
buffered Flutter stderr lines.

## User Stories

1. As a Flutter developer, I want feedback within one second of starting `flutter_pilot test`, so that the command does not look stuck.
2. As a Flutter developer, I want to see that Flutter Pilot is launching the Target App Package, so that I know the wait is before Scenario execution.
3. As a Flutter developer, I want launch progress to appear before Step progress, so that app startup and Scenario execution are not confused.
4. As a Flutter developer, I want a loading animation in interactive terminals, so that I can see the process is alive during long builds.
5. As a Flutter developer, I want elapsed launch time shown, so that I can judge how long the Target App Package has been starting.
6. As a Flutter developer, I want no fake percentage progress, so that Flutter Pilot does not imply precision it does not have.
7. As a Flutter developer, I want high-level launch stages, so that I can tell whether Flutter Pilot is resolving a device, building, installing, or waiting for the Runtime Target.
8. As a Flutter developer, I want launch stages to be honest, so that Flutter Pilot does not guess a stage when it lacks reliable evidence.
9. As a Flutter developer, I want quiet default output, so that raw Flutter logs do not drown out Flutter Pilot status.
10. As a Flutter developer, I want raw Flutter build logs hidden by default, so that normal successful runs stay readable.
11. As a Flutter developer, I want useful Flutter stderr shown when launch fails, so that I can diagnose build or startup failures.
12. As a Flutter developer, I want the last Flutter stderr lines on failure, so that I see the likely root cause without opening another log.
13. As a Flutter developer, I want successful launch to leave a summary line, so that I can see how long app startup took.
14. As a Flutter developer, I want Step progress to start after the launch summary, so that the terminal clearly separates launch from Scenario execution.
15. As a Flutter developer, I want Target Device information in the launch panel, so that I can verify where the app will run.
16. As a Flutter developer, I want `--device` selections to show the resolved Target Device, so that id, name, or prefix inputs become concrete.
17. As a Flutter developer, I want Scenario Recording auto-selected Target Devices to be visible, so that I know which recordable device was chosen.
18. As a Flutter developer, I want automatic recording selection to say `auto-selected for recording`, so that the device choice is transparent.
19. As a Flutter developer, I want explicit device selection to show the original `--device` value, so that I can connect output back to my command.
20. As a Flutter developer, I want Flutter default device selection to be labeled as `Flutter default`, so that Flutter Pilot does not pretend to know a device it did not resolve.
21. As a Flutter developer, I want Flutter Pilot to update unknown device information if it later becomes reliable, so that the launch panel becomes more informative when possible.
22. As a Flutter developer, I want flavor shown when provided, so that I can confirm the intended app variant is launching.
23. As a Flutter developer, I want entrypoint shown when provided, so that I can confirm the intended Target App Package entrypoint is launching.
24. As a Flutter developer, I do not want the full `flutter run --machine` command shown by default, so that normal launch output stays focused on user choices.
25. As a Flutter developer, I want launch progress to use a compact panel, so that it gives context without turning into a verbose log.
26. As a Flutter developer, I want the launch panel to use two or three useful lines when possible, so that the output remains scannable.
27. As a Flutter developer, I want non-interactive runs to print heartbeat lines, so that CI logs show the command is still active.
28. As a CI user, I want non-interactive launch progress to be deterministic, so that logs and tests are stable.
29. As a CI user, I want heartbeat output no more often than necessary, so that long builds do not flood CI logs.
30. As a CI user, I want launch progress on stderr, so that stdout remains stable for scripts.
31. As a CI user, I want `Run report:` and `HTML report:` to remain on stdout, so that existing automation keeps working.
32. As a CI user, I want `test --json` to suppress launch progress, so that machine-readable output is not polluted.
33. As an AI coding agent, I want launch status in stderr, so that I can distinguish app startup delay from Step execution delay.
34. As an AI coding agent, I want launch failures summarized before report paths, so that failed startup is visible without artifact inspection.
35. As an AI coding agent, I want Target Device selection reason visible, so that I can understand whether a run used user input, recording auto-selection, or Flutter default selection.
36. As a maintainer, I want Target App Launch Progress to be CLI presentation behavior, so that Scenario semantics and artifact formats do not change.
37. As a maintainer, I want Target App Launch Progress separate from Step progress, so that app launch and Scenario execution remain distinct phases.
38. As a maintainer, I want a launch progress renderer that can be tested without real Flutter builds, so that UX behavior is covered deterministically.
39. As a maintainer, I want launch process orchestration to keep owning Runtime Target discovery, so that progress rendering does not parse Scenarios or run Steps.
40. As a maintainer, I want Target Device resolution to remain the source of known device metadata, so that launch output uses the same model as reports.
41. As a maintainer, I want Flutter stderr buffering to remain bounded, so that failure output is useful without unbounded memory or terminal spam.
42. As a maintainer, I want future verbose output to remain possible, so that full Flutter logs can be exposed later without changing the default UX.

## Implementation Decisions

- Target App Launch Progress is a new CLI presentation surface for `flutter_pilot test`.
- Target App Launch Progress covers the period before Scenario Step execution, from launch preparation through Runtime Target availability.
- Target App Launch Progress is separate from Step progress and must not render as Step `0/N`.
- Target App Launch Progress should use the glossary term Target App Launch Progress in documentation and code comments where appropriate.
- Human-readable Target App Launch Progress should be written to stderr.
- Existing stdout lines for `Run report:` and `HTML report:` remain unchanged.
- `test --json` suppresses Target App Launch Progress.
- Interactive terminals should render a compact in-place panel with current stage and elapsed time.
- Non-interactive output should render deterministic plain-text launch status.
- Non-interactive output should print periodic heartbeat status while launch is still waiting.
- A ten-second heartbeat interval is the initial default for non-interactive output.
- Target App Launch Progress should not use percentage progress because Flutter build, install, and launch do not expose a reliable total.
- Launch progress should preserve a final success summary after the interactive loading panel finishes.
- The success summary should include elapsed launch time.
- Step progress should begin after the launch success summary as a separate block.
- Launch failure output should include a concise Flutter Pilot failure summary.
- Launch failure output should include the buffered Flutter stderr tail.
- The existing last-forty-lines stderr buffering behavior remains a good default for launch failures.
- Default launch progress should not print raw `flutter run --machine` stdout.
- Default launch progress should not print full Flutter build logs.
- Default launch progress should not print the full `flutter run --machine` command.
- A future verbose mode may expose fuller Flutter logs or command detail, but verbose output is not required for this PRD.
- The launch panel should show Target Device metadata when Flutter Pilot has resolved a Target Device.
- When `--device` is passed, launch progress should show the resolved Target Device and indicate the selection came from the user-provided `--device` value.
- When Scenario Recording auto-selects the only recordable Target Device, launch progress should show the resolved Target Device and indicate `auto-selected for recording`.
- When no Target Device is resolved because Flutter is allowed to choose its default device, launch progress should show `Target Device: Flutter default`.
- If Flutter Pilot can later obtain reliable actual device information from Flutter launch output or another stable source, the launch panel may update `Flutter default` to the concrete Target Device.
- Flutter Pilot should not fail or force explicit device selection solely to display a concrete device when recording is not required.
- Flavor should be shown when the user passes `--flavor`.
- Entrypoint should be shown when the user passes `--target`.
- Omitted flavor and entrypoint should not produce placeholder lines.
- High-level stages should be limited to reliable, user-meaningful states such as resolving Target Device, launching the Target App Package, building app, installing app, and waiting for Runtime Target.
- Flutter Pilot should not guess a build or install stage when the available Flutter output does not reliably support that stage.
- The first implementation can fall back to `Waiting for Runtime Target` when finer stage detection is not available.
- Target Device resolution remains responsible for determining explicit and Scenario Recording auto-selected Target Devices.
- Target App launch orchestration remains responsible for starting Flutter, buffering stderr, reading machine stdout, extracting the Runtime Target URI, and cleaning up the launched process.
- A deep launch progress renderer module should own terminal wording, interactive refresh, elapsed-time formatting, success summary, failure summary, and non-interactive heartbeat wording.
- A small launch progress event or callback interface should connect command orchestration to the renderer without making the launcher write directly to stdout or stderr.
- The launch progress renderer should be injectable or otherwise testable with fake clocks and fake sinks.
- The launch progress renderer should share terminal styling primitives with Step progress where practical, but it should own its own launch wording and layout.
- No Scenario YAML fields are added or changed.
- No run report schema changes are required for Target App Launch Progress.
- No Runtime Adapter contract changes are required for Target App Launch Progress.
- No ADR is required because this is CLI presentation behavior rather than a hard-to-reverse architecture decision.

## Testing Decisions

- Tests should verify public behavior and stable presentation contracts, not private implementation details.
- Launch progress renderer tests should cover interactive output with refresh behavior.
- Launch progress renderer tests should cover non-interactive plain-text output without ANSI codes or emoji.
- Launch progress renderer tests should cover elapsed-time formatting.
- Launch progress renderer tests should cover Target Device display for explicit `--device` selection.
- Launch progress renderer tests should cover Target Device display for Scenario Recording auto-selection.
- Launch progress renderer tests should cover `Flutter default` display when no Target Device is resolved.
- Launch progress renderer tests should cover flavor and entrypoint display when present.
- Launch progress renderer tests should verify omitted optional fields do not render placeholder noise.
- Launch progress renderer tests should verify success summary output.
- Launch progress renderer tests should verify failure summary output with stderr tail context.
- Launch progress renderer tests should verify non-interactive heartbeat wording and cadence with a fake clock or injected ticker.
- Command orchestration tests should verify launch progress is enabled for non-JSON `test` runs.
- Command orchestration tests should verify launch progress is suppressed for `test --json`.
- Command orchestration tests should verify launch progress is written to stderr while final report paths remain on stdout.
- Target App Launcher tests should continue to use fake process streams for `flutter run --machine` output and stderr buffering.
- Target Device resolver tests should continue to verify explicit device selection and Scenario Recording auto-selection.
- CLI tests should avoid launching a real Flutter app; fake launch and runner boundaries are the preferred coverage for progress behavior.
- Existing Step progress tests are prior art for separating renderer tests from runner and command tests.
- Existing Target App Launcher tests are prior art for exercising launch behavior with fake process streams.
- Existing Target Device resolver tests are prior art for testing device selection rules without invoking Flutter tooling.
- Before finishing implementation changes, run `dart format .`, `dart analyze`, and `dart test` unless explicitly directed otherwise.

## Out of Scope

- Showing a percentage progress bar for Flutter build or launch.
- Default raw Flutter build log streaming.
- Default raw `flutter run --machine` JSON output.
- Default full `flutter run --machine` command output.
- Adding public `--verbose`, `--quiet`, `--color`, or `--no-color` flags.
- Changing Scenario YAML syntax.
- Changing Scenario Recording syntax.
- Changing Runtime Adapter behavior.
- Changing Step progress wording or layout beyond handoff from launch progress.
- Changing run report or artifact schemas.
- Recording Flutter build logs as run artifacts.
- Forcing explicit Target Device selection when Scenario Recording is not required.
- Interactive device selection.
- Replacing Flutter's default device selection behavior for non-recording runs.
- Adding a launch timeout or timeout configuration.
- Showing launch progress for `validate`, `report`, `diff`, `doctor`, or `init`.

## Further Notes

- This PRD complements `docs/cli-step-progress-prd.md`; it does not replace it.
- Step progress starts only after the Runtime Target is available. Target App
  Launch Progress fills the UX gap before that point.
- The glossary now defines Target App Launch Progress and clarifies that Target
  Device may be selected explicitly or automatically for Scenario Recording.
- Published to GitHub with the `ready-for-agent` label:
  https://github.com/drown0315/flutter_pilot/issues/90
