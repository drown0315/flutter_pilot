# Run Diff PRD

## Problem Statement

Flutter developers and AI coding agents can already produce Scenario Run
directories with structured reports and diagnostic artifacts, but they still
need to manually inspect before and after runs to understand whether a change
fixed the original problem or introduced a new one. Reading two timelines,
screenshots, logs, and reports by hand is slow and error-prone.

Flutter Pilot needs a Run Diff that compares two Scenario Runs and reports the
meaningful changes: resolved Steps, new Regressions, visible text changes,
runtime failures that disappeared or appeared, missing Steps, and screenshot
artifact changes.

## Solution

Add `flutter_pilot diff <before-run> <after-run>` to compare two run
directories. The command reads each run directory's `run_report.json`, follows
the referenced Screenshot, Snapshot, and Logs artifacts when needed, and prints
a human-readable Run Diff to stdout.

The command also supports `--json` for machine-readable output. JSON output is
more complete than the human-readable summary and includes stable fields for
Step identity, before and after status, artifact paths, screenshot hashes,
resolved runtime failures, new runtime failures, warnings, and overall outcome.

The first version intentionally treats screenshot differences as artifact/hash
changes, not pixel-level visual diffs. Widget Tree and interactive widget
summary diffs are out of scope for this slice.

## User Stories

1. As a Flutter developer, I want to compare a before Scenario Run and an after Scenario Run, so that I can see whether my fix changed the right behavior.
2. As a Flutter developer, I want the Run Diff to identify resolved Steps, so that I can tell when a previously failing path now passes.
3. As a Flutter developer, I want the Run Diff to identify Regressions, so that I can catch behavior that became worse after a change.
4. As a Flutter developer, I want Regressions to include newly failed Steps, so that Step status changes are not buried in raw report data.
5. As a Flutter developer, I want Regressions to include new runtime failures, so that Flutter errors introduced by a change are visible.
6. As a Flutter developer, I want missing labeled Steps to be treated as Regressions, so that important named checkpoints cannot disappear silently.
7. As a Flutter developer, I want added Steps to be reported without being treated as Regressions, so that expanded Scenarios are not automatically marked worse.
8. As a Flutter developer, I want unlabeled missing Steps to be reported without automatically treating them as Regressions, so that fragile index-only comparisons do not overstate risk.
9. As a Flutter developer, I want Step matching to prefer Step Labels, so that inserting a Step in the middle of a Scenario does not make every later Step look unrelated.
10. As a Flutter developer, I want unlabeled Steps to fall back to index matching, so that older or lightweight Scenarios can still be compared.
11. As a Flutter developer, I want the output to show before and after Step indexes, so that I can locate changed Steps in each timeline report.
12. As a Flutter developer, I want action changes to be reported, so that I can see when a named Step kept its label but changed behavior.
13. As a Flutter developer, I want visible text added and removed across runs, so that I can understand user-visible UI changes without opening every screenshot.
14. As a Flutter developer, I want visible text changes to be summarized at run level in the first version, so that the output stays compact and reliable.
15. As a Flutter developer, I want resolved runtime failures to be reported separately from resolved Steps, so that app failures and Scenario execution failures are not confused.
16. As a Flutter developer, I want new runtime failures to be reported separately from Step failures, so that app-level errors remain clear.
17. As a Flutter developer, I want Step `failureReason` to contribute to Step diff only, so that Finder or action failures are not mislabeled as app runtime failures.
18. As a Flutter developer, I want runtime failures to come from diagnostic summaries or Logs artifacts, so that the Run Diff reflects the app's diagnostic stream.
19. As a Flutter developer, I want screenshot artifact changes to be reported, so that I know when visual review is needed.
20. As a Flutter developer, I want screenshot differences to include added, missing, and changed screenshots, so that artifact coverage changes are visible.
21. As a Flutter developer, I want screenshot JSON output to include paths and hashes, so that other tools can inspect or fetch the changed artifacts.
22. As a Flutter developer, I want screenshot hash changes not to automatically count as Regressions, so that expected visual changes do not create false failures.
23. As a Flutter developer, I want the command to warn when Scenario names differ, so that accidental mismatches are visible without blocking intentional comparisons.
24. As a Flutter developer, I want different Scenario names not to fail the diff, so that renamed or copied Scenarios can still be compared.
25. As a Flutter developer, I want missing artifact files to become warnings, so that partial run directories can still produce useful Run Diffs.
26. As a Flutter developer, I want malformed reports to fail clearly, so that corrupt inputs do not produce misleading comparisons.
27. As a QA engineer, I want `diff` to return exit code `0` when it successfully generates a Run Diff, so that Regression findings are report data rather than CLI execution failures.
28. As a QA engineer, I want invalid arguments and unreadable inputs to return non-zero exit codes, so that automation can distinguish tool failures from reported Regressions.
29. As a QA engineer, I want machine-readable output, so that CI or downstream scripts can consume Run Diff results.
30. As a QA engineer, I want a top-level outcome, so that automation can quickly classify a Run Diff.
31. As a QA engineer, I want the outcome to be `unchanged` when there are no reported changes, so that no-op comparisons are explicit.
32. As a QA engineer, I want the outcome to be `improved` when there are resolved Steps or resolved runtime failures and no Regressions, so that successful fixes are easy to detect.
33. As a QA engineer, I want the outcome to be `regressed` when any Regression exists, so that harmful changes are easy to detect.
34. As a QA engineer, I want the outcome to be `changed` when changes are present but are not clearly improvements or Regressions, so that neutral differences are not overstated.
35. As an AI coding agent, I want a compact human-readable Run Diff, so that I can decide what source area to inspect next.
36. As an AI coding agent, I want detailed JSON output, so that I can programmatically reason about Step changes, runtime failures, and changed screenshots.
37. As an AI coding agent, I want stable Step keys in JSON output, so that I can correlate changes with Scenario labels and timeline entries.
38. As an AI coding agent, I want warnings in JSON output, so that I can account for missing artifacts or Scenario name mismatches.
39. As a contributor, I want the Run Diff engine to be testable without a live Flutter app, so that the feature can be developed with fixed report fixtures.
40. As a contributor, I want report loading to be isolated from CLI rendering, so that future commands can reuse the same run report parsing behavior.

## Implementation Decisions

- Add a `diff <before-run> <after-run>` CLI command.
- The default `diff` output is human-readable text written to stdout.
- `diff --json` writes a stable machine-readable object to stdout.
- The command does not automatically write `run_diff.json`, `run_diff.txt`, HTML, or any other file in the first version.
- A successful Run Diff returns exit code `0` even when Regressions are found.
- Argument usage errors return the CLI usage error code.
- Missing run directories, missing `run_report.json`, malformed JSON, or unsupported report shapes return a non-zero execution error.
- Different Scenario names do not fail the command. They produce a warning in both human-readable and JSON output.
- Run Diff compares Scenario Runs, not arbitrary directories. Run directories are only the artifact container used to load each Scenario Run.
- Step alignment prefers Step Label. If a Step has no label, alignment falls back to Step index.
- JSON output includes before and after Step identity data: index, label, action, status, and failure reason when present.
- A Step that changes from `failed` to `passed` is a resolved Step.
- A Step that changes from `passed` to `failed` is a Regression.
- A labeled Step present before and missing after is a Regression.
- An unlabeled Step missing after is reported as missing but is not automatically a Regression.
- A Step present after and missing before is reported as added but is not automatically a Regression.
- A Step with the same alignment key but different action is reported as an action change.
- Resolved errors mean runtime failures that were present before and absent after.
- New errors mean runtime failures that were absent before and present after. New errors are Regressions.
- Step `failureReason` is used for Step diff only. It is not treated as a runtime failure.
- Runtime failures come from top-level diagnostic summaries when present, or from Logs artifacts reduced through the diagnostic reducer when summaries are absent.
- Visible text changes are run-level in the first version. They report visible text added and removed between before and after.
- Visible text comes from top-level diagnostic summaries when present, or from Snapshot artifacts reduced through the diagnostic reducer when summaries are absent.
- The first version reads only the artifact types needed for the agreed diff: Screenshot, Snapshot, and Logs.
- Missing referenced artifacts do not fail the entire Run Diff. They produce warnings and artifact-specific missing findings where relevant.
- Screenshot differences are Screenshot artifact differences, not pixel-level visual diffs.
- Screenshot differences include added screenshots, missing screenshots, and changed screenshots based on file hashes.
- Screenshot JSON output includes Step key, before and after Step identity, artifact paths, hashes, and a change type.
- Screenshot changes do not automatically count as Regressions.
- Widget Tree diff is out of scope for the first version.
- Interactive widget summary diff is out of scope for the first version.
- The Run Diff has an overall outcome with these values: `unchanged`, `improved`, `regressed`, and `changed`.
- Outcome priority is `regressed`, then `improved`, then `changed`, then `unchanged`.
- Build a deep Run Diff module with a small interface that accepts before and after run directories or loaded report data and returns a structured Run Diff object.
- Build or extract a run report reader module so report parsing, validation, and artifact lookup are not duplicated between commands.
- Keep CLI rendering separate from the Run Diff engine so human-readable and JSON output can be tested independently from diff calculation.
- Reuse the existing diagnostic reducer for visible text and runtime failure extraction instead of adding ad hoc JSON traversal rules in the diff engine.
- No ADR is needed for this slice. The decisions are feature scope and output-contract decisions rather than hard-to-reverse architecture choices.

## Testing Decisions

- Tests should verify external behavior and stable contracts rather than private implementation details.
- Run Diff engine tests should use fixed run directory fixtures and assert on structured Run Diff output.
- CLI tests should execute the real Dart subprocess and assert exit codes, stdout, and stderr.
- Report reader tests should cover missing `run_report.json`, malformed JSON, non-object report roots, missing required fields, and referenced artifact lookup.
- Human-readable renderer tests should cover summaries with resolved Steps, Regressions, visible text changes, resolved runtime failures, new runtime failures, screenshot changes, warnings, and unchanged runs.
- JSON output tests should verify the stable top-level schema, detailed Step identity fields, screenshot paths and hashes, warnings, and outcome values.
- Tests should cover unchanged runs.
- Tests should cover failed-to-passed resolved Steps.
- Tests should cover passed-to-failed Step Regressions.
- Tests should cover missing labeled Steps as Regressions.
- Tests should cover missing unlabeled Steps as non-Regression missing Step findings.
- Tests should cover added Steps.
- Tests should cover action changes for aligned Steps.
- Tests should cover resolved runtime failures from diagnostic summaries.
- Tests should cover new runtime failures from Logs artifacts when summaries are absent.
- Tests should verify that Step `failureReason` does not appear in resolved errors or new errors.
- Tests should cover visible text added and removed from diagnostic summaries.
- Tests should cover visible text extracted from Snapshot artifacts when summaries are absent.
- Tests should cover screenshot added, missing, and changed cases.
- Tests should verify screenshot hash changes do not create Regressions by themselves.
- Tests should cover warnings for missing referenced artifacts.
- Tests should cover warnings for Scenario name changes.
- Tests should verify that successful Run Diff generation returns exit code `0` even when Regressions are present.
- Tests should follow the existing project pattern: core behavior in unit tests, CLI behavior through subprocess tests.

## Out of Scope

- Pixel-level screenshot diffing.
- Screenshot heatmap generation.
- Visual thresholding, anti-aliasing tolerance, or perceptual image comparison.
- HTML Run Diff reports.
- Writing `run_diff.json` or any other output file automatically.
- `--fail-on-regression` or CI gate behavior.
- Widget Tree diffing.
- Interactive widget summary diffing.
- Treating screenshot changes as Regressions by themselves.
- Treating Step `failureReason` as a runtime failure.
- Requiring before and after runs to have the same Scenario name.
- Comparing arbitrary folders that are not Scenario Run directories.

## Further Notes

- The project glossary now uses Run Diff for this feature and Regression for findings where an after Scenario Run became worse than the before Scenario Run.
- The first version should stay focused on high-signal debugging questions: what got fixed, what got worse, what visible text changed, what runtime failures appeared or disappeared, and what screenshots need review.
- Future work can add shareable diff reports, pixel-level image comparison, or CI gating once the structured Run Diff contract is stable.
