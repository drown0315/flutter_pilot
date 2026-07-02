# Run Diff

Run Diff compares two Flutter Pilot Scenario Run directories and reports what
changed between them.

```bash
flutter_pilot diff <before-run> <after-run>
```

The command reads `<run-directory>/run_report.json` from both directories. When
needed, it also reads referenced Screenshot, Snapshot, and Logs artifacts from
the same run directories.

Use `--json` when another tool needs the machine-readable contract:

```bash
flutter_pilot diff <before-run> <after-run> --json
```

## Human-Readable Output

Default output is intended for terminal review:

```text
Run Diff
Before: .runs/before_login
After: .runs/after_login

Step Regressions:
- Step 1 "submit": passed -> failed (tap)
  Reason: Button stayed disabled.
New Runtime Failure Regressions:
- setState() called after dispose()
Visible Text Added:
- Continue
Visible Text Removed:
- Retry
Screenshot Changes:
- Step 4 "capture_login": screenshot changed
```

When there are no warnings or findings, the output says:

```text
Run Diff
Before: .runs/before_login
After: .runs/after_login

No Run Diff changes.
```

Warnings are non-fatal. For example, different Scenario names or missing
referenced artifacts are printed under `Warnings:` while the rest of the Run
Diff is still generated.

## JSON Output

`--json` prints one stable JSON object:

```json
{
  "beforeRunDirectory": ".runs/before_login",
  "afterRunDirectory": ".runs/after_login",
  "outcome": "regressed",
  "warnings": [],
  "regressions": [
    {
      "kind": "statusChanged",
      "description": "Step 1 \"submit\": passed -> failed (tap)",
      "stepName": "Step 1 \"submit\"",
      "before": {
        "index": 1,
        "label": "submit",
        "action": "tap",
        "status": "passed"
      },
      "after": {
        "index": 1,
        "label": "submit",
        "action": "tap",
        "status": "failed",
        "failureReason": "Button stayed disabled."
      },
      "failureReason": "Button stayed disabled."
    }
  ],
  "resolvedSteps": [],
  "missingSteps": [],
  "addedSteps": [],
  "actionChanges": [],
  "screenshotChanges": [
    {
      "kind": "changed",
      "stepKey": "label:capture_login",
      "description": "Step 4 \"capture_login\": screenshot changed",
      "before": {
        "index": 4,
        "label": "capture_login",
        "action": "capture",
        "status": "passed"
      },
      "after": {
        "index": 4,
        "label": "capture_login",
        "action": "capture",
        "status": "passed"
      },
      "beforePath": "captures/login.png",
      "afterPath": "captures/login.png",
      "beforeHash": "before-sha256",
      "afterHash": "after-sha256"
    }
  ],
  "visibleTextAdded": [
    "Continue"
  ],
  "visibleTextRemoved": [
    "Retry"
  ],
  "resolvedRuntimeFailures": [],
  "newRuntimeFailures": [
    "setState() called after dispose()"
  ]
}
```

The hash values above are shortened placeholders. Real output contains full
SHA-256 hashes.

## Exit Codes

A successful Run Diff generation exits `0`, even when the output contains
Regressions. Regressions are report data, not CLI execution failures.

The command exits non-zero when it cannot generate a trustworthy Run Diff, such
as:

- invalid CLI arguments
- missing run directories
- missing `run_report.json`
- malformed JSON
- unsupported `run_report.json` shapes

## Outcomes

JSON output includes a top-level `outcome`:

- `unchanged`: no warnings or findings were reported.
- `improved`: resolved Steps or resolved runtime failures exist, with no
  Regressions.
- `regressed`: at least one Step Regression or new runtime failure exists.
- `changed`: only neutral changes or warnings exist.

Outcome priority is `regressed`, then `improved`, then `changed`, then
`unchanged`.

## Step Rules

Step alignment prefers Step Label. This keeps labeled Steps stable when a
Scenario gains or removes neighboring Steps.

When the before Step has no label, Run Diff falls back to Step index. That index
fallback can still match an after Step that has gained a label.

Regression Step rules:

- `passed -> failed` is a Regression.
- A labeled Step missing from the after run is a Regression.
- A failed Step that becomes passed is a resolved Step.
- An unlabeled Step missing from the after run is reported as a missing Step,
  but is not automatically a Regression.
- An added Step is reported as added, but is not automatically a Regression.
- A matched Step with a different action is reported as an action change.

## Runtime Failures

Runtime failures are app-level diagnostic failures from `diagnosticSummary` or
Logs artifacts. They are separate from Step `failureReason`.

Step `failureReason` explains why a Scenario Step failed, such as a Finder
matching no widgets. It contributes to Step findings only and is not copied into
resolved or new runtime failure lists.

New runtime failures are Regressions. Resolved runtime failures are improvement
signals.

## Screenshot Comparison

Screenshot comparison is artifact/hash-only in the first version. Run Diff
reports:

- screenshots added in the after run
- screenshots missing from the after run
- screenshots whose SHA-256 file hash changed

Screenshot changes are visual-review signals. They do not automatically create
Regressions.

Missing referenced Screenshot, Snapshot, or Logs artifacts produce warnings
rather than failing the whole Run Diff.

## Acceptance Fixtures

Checked-in Run Diff acceptance fixtures live under:

```text
test/fixtures/run_diff/
```

They cover:

- `unchanged`
- `improved`
- `regressed`
- `changed`
- `malformed`
- `partial_artifact`

These fixtures are intentionally small run directories, so maintainers and
agents can verify Run Diff behavior without a live Flutter app.

## Out Of Scope

The first version does not do:

- pixel-level visual diffing
- screenshot heatmaps
- Widget Tree diffing
- interactive widget summary diffing
- automatic output files such as `run_diff.json`
- CI gating or `--fail-on-regression`
