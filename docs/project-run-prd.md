# Flutter Pilot Project Run PRD

## Problem Statement

Flutter Pilot can run one Entry Scenario at a time, but project-level
verification still requires users or CI scripts to enumerate Scenario files
manually. That makes full-project Scenario execution repetitive, inconsistent
across machines, and hard to package as one debuggable artifact.

Users need `flutter_pilot test` to run the Target App Package's Project
Scenarios without requiring a Scenario file argument. They also need directory
inputs for focused Project Runs, deterministic discovery, clear Step Library
exclusion, app reuse for performance, and one batch-level artifact directory
that contains every Scenario Run produced by the batch.

## Solution

Extend `flutter_pilot test` with Project Run behavior. With no positional
argument, `test` discovers Project Scenarios from the default Pilot Directory,
`pilot/`. With one directory argument, `test` discovers Project Scenarios from
that directory. With one file argument, `test` keeps the existing single Entry
Scenario behavior.

Directory discovery recursively scans `.yaml` and `.yml` files, but runs only
files that declare top-level `scenario:` metadata. Metadata-free YAML files
remain valid Step Library candidates and are not run directly. Discovered
Project Scenarios run in deterministic lexicographic order by POSIX-style path
relative to the discovery directory.

A Project Run launches the Target App Package once with the existing
`flutter run --machine` flow. The first Scenario runs after launch. Before each
later Scenario, Flutter Pilot hot restarts the launched app, then runs the next
Scenario. Scenario execution failures produce that Scenario's artifacts and do
not block later Scenarios. Environment-level failures such as launch failure,
Target Device resolution failure, validation failure, discovery failure, or hot
restart failure stop the Project Run.

Project Run artifacts are grouped under one batch-level run directory beneath
`.runs/`. The batch directory contains `project_run_report.json` plus one child
run directory per Scenario Run. Each child run directory keeps the familiar
single-Scenario artifacts, including `run_report.json`, `timeline.html`,
`step.json`, and `artifacts/`. The first version does not generate a
batch-level HTML report.

## User Stories

1. As a Flutter developer, I want `flutter_pilot test` to run Project Scenarios, so that I can verify the Target App Package without listing every Scenario file.
1. As a Flutter developer, I want the default Pilot Directory to be `pilot/`, so that Flutter Pilot-authored Scenario assets have a short conventional location.
1. As a Flutter developer, I want `flutter_pilot test <directory>` to run Project Scenarios from that directory, so that I can run a focused subset.
1. As a Flutter developer, I want `flutter_pilot test <scenario.yaml>` to keep running one Entry Scenario, so that existing single-Scenario workflows remain intact.
1. As a Flutter developer, I want directory discovery to recurse into nested directories, so that I can organize Project Scenarios by feature area.
1. As a Flutter developer, I want `.yaml` and `.yml` files to be discoverable, so that common YAML extensions both work.
1. As a Flutter developer, I want directory discovery to run only files with top-level `scenario:` metadata, so that Step Libraries are not run by themselves.
1. As a Flutter developer, I want single-file `test` to keep allowing omitted Scenario metadata, so that existing Entry Scenario files stay valid.
1. As a Flutter developer, I want discovered Project Scenarios to run in stable path order, so that local and CI runs are predictable.
1. As a Flutter developer, I want to control Project Scenario order with file names, so that I do not need a separate ordering configuration.
1. As a Flutter developer, I want an empty discovery directory to fail before app launch, so that a misconfigured Project Run does not create misleading artifacts.
1. As a Flutter developer, I want all selected Entry Scenario files validated before app launch, so that schema errors do not leave a partially executed Project Run.
1. As a Flutter developer, I want validation failures to prevent launch, so that invalid Project Scenarios fail quickly and clearly.
1. As a Flutter developer, I want one Target App Package launch per Project Run, so that running all Project Scenarios is faster than cold-launching for every Scenario.
1. As a Flutter developer, I want the first Project Scenario to run immediately after launch, so that no unnecessary hot restart happens before work begins.
1. As a Flutter developer, I want Flutter Pilot to hot restart before each later Scenario, so that app state is reset while the launched process is reused.
1. As a Flutter developer, I want Flutter Pilot to hot restart after a failed Scenario before continuing, so that later Scenarios are not run in the failed UI state.
1. As a Flutter developer, I want hot restart failure to stop the Project Run, so that later Scenario results are not produced from an unrecoverable app state.
1. As a Flutter developer, I want a failed Scenario to not block later Scenarios, so that I can see the full Project Scenario result set.
1. As a Flutter developer, I want the final Project Run exit code to be `0` only when every Scenario passes, so that CI can gate on the batch result.
1. As a Flutter developer, I want the final Project Run exit code to be `1` when one or more Scenario Runs fail, so that CI reports Project Scenario failures as failures.
1. As a Flutter developer, I want usage errors such as invalid inputs or empty discovery to return `64`, so that scripts can distinguish command misuse from Scenario failure.
1. As a Flutter developer, I want environment-level failures to stop the Project Run, so that launch, device, validation, or restart problems are not confused with Scenario outcomes.
1. As a Flutter developer, I want Project Run artifacts grouped under one `.runs/` directory, so that I can upload one artifact folder from CI.
1. As a Flutter developer, I want `project_run_report.json` at the batch root, so that tools can read the Project Run summary without walking every child directory first.
1. As a Flutter developer, I want each Scenario Run to keep its own child run directory, so that existing Scenario Run artifacts remain easy to inspect.
1. As a Flutter developer, I want each child run directory to keep `run_report.json`, `timeline.html`, `step.json`, and `artifacts/`, so that single-Scenario report tooling remains useful.
1. As a Flutter developer, I want Project Run stdout to print the batch report path, so that scripts can locate the Project Run artifact.
1. As a Flutter developer, I want Project Run stdout to print each Scenario's report paths, so that terminal output still points directly to useful debugging artifacts.
1. As a Flutter developer, I want no batch-level HTML report in the first version, so that the feature can ship without delaying on report design.
1. As a Flutter developer, I want `--device`, `--flavor`, and `--target` to apply to a Project Run, so that full-project verification uses the same app launch choices as single-Scenario runs.
1. As a Flutter developer, I want Target Device resolution to happen once before launch, so that every Project Scenario uses the same selected device.
1. As a Flutter developer, I want Scenario Recording requirements to be checked before Project Run launch, so that recording-enabled Project Scenarios do not silently degrade.
1. As a Flutter developer, I want Project Run recording behavior to remain Scenario-driven, so that no extra CLI flag is needed to enable or disable recording.
1. As a Flutter developer, I want `--until` rejected in Project Run mode, so that stop points do not have ambiguous meaning across multiple Scenarios.
1. As a Flutter developer, I want `--print` rejected in Project Run mode, so that diagnostic printing remains tied to single-Scenario debugging.
1. As a Flutter developer, I want `--json` to keep its existing diagnostic-print meaning, so that Project Run progress does not create a new JSON stdout contract in this slice.
1. As a Flutter developer, I want Target App Launch Progress to appear once before the batch starts, so that the launch phase is not repeated for every Scenario.
1. As a Flutter developer, I want Step progress to remain per Scenario, so that each Scenario's execution remains understandable.
1. As a Flutter developer, I want Project Run progress output to be deterministic in non-interactive terminals, so that CI logs are stable.
1. As an AI coding agent, I want one command to reproduce the project's Scenario set, so that I can validate broad UI behavior after a code change.
1. As an AI coding agent, I want each failed Scenario to keep its own artifacts, so that I can inspect failures independently.
1. As an AI coding agent, I want Project Run summaries to include Scenario file paths and report paths, so that I can locate relevant artifacts programmatically.
1. As a QA engineer, I want a Project Run to continue after Scenario failures, so that one failure does not hide later failures.
1. As a QA engineer, I want launch and hot restart failures to stop the batch, so that infrastructure problems do not produce noisy downstream failures.
1. As a QA engineer, I want a single batch directory for CI artifacts, so that artifact retention is simple.
1. As a maintainer, I want Project Scenario discovery isolated behind a deep module, so that discovery rules can be tested without launching Flutter.
1. As a maintainer, I want Project Run orchestration isolated behind a deep module, so that launch reuse, hot restart, continuation, and final status can be tested without real devices.
1. As a maintainer, I want Target App Launcher to own hot restart communication with Flutter, so that process control remains separate from Scenario semantics.
1. As a maintainer, I want Artifact Store changes to preserve single-Scenario report layout, so that `report` and `diff` keep working on Scenario Run directories.
1. As a maintainer, I want Project Run summary rendering separate from execution, so that stdout and JSON report shapes can evolve independently.

## Implementation Decisions

- `test` remains the only CLI command that executes Scenarios.
- `test` with one file argument runs one Entry Scenario.
- `test` with no positional argument runs a Project Run discovered from the default Pilot Directory, `pilot/`.
- `test` with one directory argument runs a Project Run discovered from that directory.
- Multiple explicit file or directory inputs are not supported in the first version.
- Glob inputs are not supported in the first version.
- Project Scenario discovery recursively scans `.yaml` and `.yml` files.
- Directory discovery includes only files with top-level `scenario:` metadata.
- Directory discovery treats metadata-free YAML files as Step Library candidates and does not run them directly.
- Single-file `test` preserves the existing rule that Scenario metadata is optional.
- Discovery order is lexicographic by POSIX-style path relative to the discovery directory.
- Empty discovery exits `64` before launch.
- All discovered Entry Scenario files are parsed and validated before launch.
- A Scenario validation failure prevents app launch and returns a non-zero exit.
- Single-file `test` continues to support `--until`, repeated `--print`, and `--json`.
- Project Run mode rejects `--until` and `--print` as usage errors.
- `--device`, `--flavor`, and `--target` remain valid for Project Run mode and apply to the single launched Target App Package.
- The Target Device module continues to own Flutter Device parsing and Recording Device matching.
- The Project Run launch flow resolves Target Device requirements once before app launch.
- The Project Run launch flow uses the existing `flutter run --machine` Target App Package launch path.
- A Project Run launches the Target App Package once.
- The first Scenario in a Project Run runs without a preliminary hot restart.
- Flutter Pilot performs a hot restart before every later Scenario.
- Flutter Pilot performs a hot restart before continuing after a failed Scenario.
- Hot restart is an operation on the launched Target App process, owned by the Target App Launcher boundary.
- Hot restart failure is an environment-level failure and stops the Project Run.
- Scenario execution failure records that Scenario's artifacts and does not stop later Scenarios.
- Launch failure, Target Device resolution failure, Project Scenario validation failure, discovery failure, and hot restart failure stop the Project Run.
- Project Run status is passed only when every selected Scenario passes.
- Project Run status is failed when one or more Scenario Runs fail.
- Project Run exits `0` when passed and `1` when one or more Scenario Runs fail.
- Project Run writes one batch-level run directory under `.runs/`.
- Each Scenario Run inside a Project Run writes a child run directory under the batch directory.
- Each child run directory keeps the existing Scenario Run layout.
- The Project Run writes `project_run_report.json` at the batch root.
- `project_run_report.json` records the discovery root, discovered Scenario file paths, execution order, Scenario statuses, Scenario report paths, Project Run status, duration, command inputs, and environment-level failure details when present.
- The first version does not generate a batch-level HTML report.
- `report <run-directory>` continues to target Scenario Run directories in the first Project Run slice.
- `diff <before-run> <after-run>` continues to compare Scenario Run directories, not Project Run directories, in this slice.
- Target App Launch Progress remains CLI presentation behavior and is shown once before the Project Run begins.
- Step progress remains per Scenario and continues to be driven by runner progress events.
- Project Run stdout prints the Project Run report path and each Scenario's existing `Run report:` and `HTML report:` paths.
- Project Run JSON stdout is not introduced in this slice; `--json` remains scoped to single-Scenario diagnostic printing.
- Project Scenario discovery should be a deep module with a small interface that accepts a discovery root and returns ordered Entry Scenario descriptors or structured discovery errors.
- Project Run orchestration should be a deep module that accepts validated Project Scenarios and launch options, then returns a structured Project Run result.
- Target App Launcher should expose a hot restart operation on the launched app handle.
- Artifact Store should support creating a Project Run directory and scoped child Scenario Run directories without changing single-Scenario artifact semantics.
- A Project Run report renderer should own the `project_run_report.json` shape separately from CLI text output.

## Testing Decisions

- Tests should verify public behavior and stable contracts rather than private helper implementation details.
- Project Scenario discovery tests should cover the default Pilot Directory, explicit directory roots, recursive discovery, `.yaml` and `.yml` extensions, ignored Step Libraries, lexicographic ordering, invalid YAML, validation errors, and empty discovery.
- CLI tests should cover positional argument mode selection: no argument, one file, one directory, multiple inputs, missing default Pilot Directory, empty discovery, and illegal `--until` / `--print` in Project Run mode.
- Project Run executor tests should use fake launch, fake hot restart, and fake runner boundaries instead of launching a real Flutter app.
- Project Run executor tests should verify launch reuse, no hot restart before the first Scenario, hot restart before later Scenarios, hot restart after failed Scenarios, continuation after Scenario failure, stop on hot restart failure, and final Project Run status.
- Target App Launcher tests should use fake process streams to verify the hot restart command path and failure reporting.
- Artifact Store tests should verify Project Run directory creation, child Scenario Run directory creation, relative report paths, and stable `project_run_report.json` references.
- Project Run report tests should verify the JSON shape for all-passed, partially failed, validation failure, empty discovery, and hot restart failure outcomes.
- CLI output tests should verify deterministic non-interactive output for Project Run summary lines and per-Scenario report path lines.
- Existing ScenarioRunner tests remain the primary coverage for Step execution, captures, failure artifacts, `--until`, `--print`, and Scenario Recording lifecycle.
- Existing Target Device resolver tests remain the primary coverage for explicit and recording-required device selection.
- Existing Target App Launcher tests provide prior art for fake process stream testing.
- Existing Artifact Store and Run Diff fixture tests provide prior art for report path and run directory assertions.
- Existing CLI subprocess tests provide prior art for command help, usage errors, and external CLI behavior.
- Before finishing implementation changes, run `dart format .`, `dart analyze`, and `dart test` unless explicitly directed otherwise.

## Out of Scope

- Glob Scenario inputs.
- Multiple explicit files or directories in one `test` invocation.
- Running metadata-free YAML files discovered from directories as Entry Scenarios.
- Configurable Project Scenario ordering.
- A Project Run configuration file.
- Batch-level HTML reports.
- Batch-level Run Diff.
- `report` support for Project Run directories.
- `diff` support for Project Run directories.
- Parallel Project Scenario execution.
- Parallel device orchestration.
- Separate device selection per Project Scenario.
- Interactive device selection.
- `--until` and `--print` in Project Run mode.
- New Project Run JSON stdout mode.
- A new command separate from `test`.
- Reintroducing `run` as an alias.
- User-supplied VM service URI execution.
- Arbitrary Flutter argument passthrough.
- `--keep-running` for leaving the launched app open after a Project Run.

## Further Notes

- ADR 0004 records the decision to run Project Scenarios through `test`, use
  `pilot/` as the default Pilot Directory, exclude metadata-free YAML from
  directory execution, reuse the launched app, hot restart between Scenarios,
  and group Scenario Run artifacts under one Project Run directory.
- Published to GitHub with the `ready-for-agent` label:
  https://github.com/drown0315/flutter_pilot/issues/98
