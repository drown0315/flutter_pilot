# Flutter Pilot Issue Progress

Last reviewed: 2026-06-11

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
| 5. Create Stable Run Directories And Artifact Metadata | `#5`, `#19` | Not complete | Current runner writes `run_report.json` directly to the output directory. Stable `.runs/<timestamp>_<scenario>/` directories and artifact metadata do not exist yet. |
| 6. Capture Screenshots And Snapshots | `#6`, `#20` | Not complete | Runner calls adapter capture methods, but screenshots and snapshots are not persisted as artifacts or referenced by report paths. |
| 7. Capture Errors And Logs | `#7`, `#21` | Not complete | Runner calls `collectLogs`, but Logs are not persisted as artifacts or referenced by report paths. |
| 8. Produce Failure Artifact Bundles | `#8`, `#22` | Not complete | Failed steps do not automatically collect screenshot, Snapshot, and Logs bundles yet. |
| 9. Implement Real `--until` Stop Points | `#9`, `#23` | Partial | CLI validates `--until` and slices the Scenario before execution. Unexecuted steps are not represented as skipped in the run report. |
| 10. Implement `--print` Diagnostics After `--until` | `#10`, `#24` | Not complete | CLI validates `--print` requires `--until`, but does not print Snapshot, Widget Tree, or Logs diagnostics. |
| 11. Add Diagnostic Reducer | `#11`, `#25` | Not complete | No reducer exists yet. |
| 12. Generate HTML Timeline Report | `#12`, `#26` | Not complete | `--html` is accepted as a flag, but no HTML report is generated. |
| 13. Compare Before/After Run Directories | `#13`, `#27` | Not complete | No diff command or run-directory comparison exists yet. |
| 14. Add Real Flutter Smoke Scenario Through `mcp_flutter` | `#14`, `#28` | Not complete | No real Flutter smoke scenario through `mcp_flutter` exists yet. |

## Recommended GitHub Cleanup

- Close duplicate open issues `#1`, `#2`, and `#3` if they correspond to the
  completed work already represented by closed issues `#15`, `#16`, and `#17`.
- Keep `#4` through `#14` open unless their duplicated closed issues were closed
  intentionally for a non-code reason.
- Keep `#9` open unless the team explicitly accepts Scenario slicing without
  skipped-step report entries as complete.
