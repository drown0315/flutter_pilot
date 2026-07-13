# Scenario YAML

Scenario YAML is Flutter Pilot's portable format for describing a reproducible
Flutter UI journey. It records user-facing actions and diagnostic checkpoints,
while Runtime Target connection details stay in CLI options.

## Minimal Scenario

```yaml
steps:
  - tap:
      byText: Continue
```

`steps` is required. `scenario` metadata is optional for direct single-file
validation and execution. Directory discovery for Project Runs only executes
YAML files that include top-level `scenario:` metadata; metadata-free YAML files
are treated as Step Library candidates.

## Complete Example

```yaml
scenario:
  name: login_error
  description: |
    Reproduce the invalid login message and capture the UI context.
  recording: {}

steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com

  - label: enter_password
    type:
      byText: Password
      text: wrong-password

  - label: submit_login
    tap:
      byText: Continue
      byType: button

  - label: error_visible
    waitFor:
      byText: Invalid email or password
      timeoutMs: 5000

  - label: review_lower_content
    scroll:
      deltaY: -500

  - label: capture_failure
    capture:
      screenshot: true
      snapshot: true
      widgetTree: false
      logs: true
```

## Scenario Metadata

```yaml
scenario:
  name: login_error
  description: Reproduce the invalid login message.
```

`scenario.name` is optional. When present, it must start with a letter or digit
and may contain letters, digits, `_`, or `-`.

`scenario.description` is optional and must be a string. Multiline YAML strings
are supported.

Project Run directory discovery uses the presence of top-level `scenario:`
metadata to distinguish runnable Project Scenarios from Step Libraries. Direct
single-file `validate` and `test` invocations continue to allow omitted
Scenario metadata.

### Scenario Recording

Scenario Recording is optional run-level metadata under `scenario.recording`.
It is not a Step Action and does not change `capture` behavior.

These forms are valid:

```yaml
scenario:
  recording: {}
```

```yaml
scenario:
  recording:
    enabled: true
```

```yaml
scenario:
  recording:
    enabled: false
```

Omitting `scenario.recording` means the Scenario does not request recording.
`recording: {}` normalizes to enabled recording. `enabled: false` preserves an
explicit disabled state for shared Scenario files.

Boolean shorthand is invalid:

```yaml
scenario:
  recording: true
```

When recording is enabled, `flutter_pilot test` may prepare device capture
before Target App launch, starts the saved Recording Session before executing
the first Step, and stops it during run shutdown. If recording preparation or
startup fails, the run fails before any Step executes. The final Device Video
Recording is reported as a run-level artifact in `run_report.json`; it is not
attached to an individual Step.

`test` records the same Target Device that runs the app. The selected Target
Device must pair with a Recording Device by exact id or by a unique exact name
match. Without `--device`, Flutter Pilot auto-selects only when exactly one
supported Flutter Device has a paired Recording Device.

## Steps

Each item in `steps` is either a Step or a Step Include. A Step may have a
`label` and must have exactly one action.

```yaml
steps:
  - label: submit_login
    tap:
      byText: Continue
```

Step labels are optional, but useful for `--until` and reports. Labels must use
the same slug-like format as `scenario.name`, and labels must be unique within a
Scenario.

The label belongs beside the action, not inside it.

## Step Includes

A Step Include pulls Steps from a Step Library file into the current Scenario
at the include position. After expansion, the Step list is flat and includes
Steps from all referenced libraries.

```yaml
steps:
  - include: flows/login.yaml
```

Step Includes use the `include` key with a file path. The referenced file must
be a valid Step Library: it must contain only `steps` and must not define
`scenario` metadata.

```yaml
# library.yaml — valid Step Library
steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com
  - label: submit_login
    tap:
      byText: Log in
```

Include paths can be relative or absolute. Relative paths resolve against the
directory of the file that contains the include. Absolute paths are used as-is.

Step Includes support nesting: a Step Library can include another Step Library.
Include cycles are detected and produce a validation error instead of recursion
overflow.

Include entries cannot carry extra fields beyond `include`. A `label` or action
key on an include entry is a validation error. Duplicate Step Labels are
checked after include expansion across the entire Entry Scenario.

In-memory parsing (without file context) does not resolve includes — they
produce a validation error instead of falling back to the working directory.

## Finders

A Finder identifies the widget that a Step should interact with or wait for.
Supported Finder fields are `byText` and `byType`.

```yaml
tap:
  byText: Continue
```

```yaml
tap:
  byType: button
```

```yaml
tap:
  byText: Continue
  byType: button
```

When several Finder fields are present, all constraints must match. There is no
`match` field and no fallback order.

`byText` matches exact visible text. It does not perform contains, fuzzy, or
regular expression matching.

`byType` is the `mcp_flutter` semantic Snapshot node type, such as `textField`,
`button`, `text`, `scrollable`, or `header`. It is not a Dart widget class name
like `TextField` or `FilledButton`.

Finder fields are single strings. Arrays are validation errors.

## Actions

Flutter Pilot supports five Scenario actions: `tap`, `type`, `scroll`,
`waitFor`, and `capture`.

### tap

`tap` requires a Finder.

```yaml
- label: submit_login
  tap:
    byText: Continue
    byType: button
```

The Finder must resolve to exactly one Finder Match before the tap can execute.
Zero matches keep polling within the default `3000ms` budget. Multiple matches
fail the Step immediately.

### type

`type` requires a Finder and a `text` value.

```yaml
- label: enter_email
  type:
    byType: textField
    text: bad@example.com
```

The action clears existing text and enters the configured text.

### scroll

`scroll` uses gesture drag deltas in logical pixels.

```yaml
- label: scroll_down
  scroll:
    deltaY: -500
```

`deltaX` and `deltaY` default to `0`, but at least one must be non-zero.

A Finder is optional. When omitted, Flutter Pilot selects the unique outermost
visible scrollable on the dominant drag axis and ignores nested scrollables on
that axis. Multiple peer candidates are ambiguous. When provided, the Finder
must resolve to exactly one scrollable target.

```yaml
- label: scroll_results
  scroll:
    byType: scrollable
    deltaY: -500
```

### waitFor

`waitFor` requires a Finder.

```yaml
- label: error_visible
  waitFor:
    byText: Invalid email or password
    timeoutMs: 5000
```

`timeoutMs` is optional and defaults to `3000`.

`waitFor` first waits up to `500ms` for the current or next Flutter frame, then
polls every `50ms` until the Finder produces exactly one match. Frame
synchronization and polling share the `timeoutMs` budget. Zero matches keep
waiting until timeout. Multiple matches fail the Step immediately.

Finder-backed `tap`, `type`, and targeted `scroll` use the same synchronization
and polling behavior with a default `3000ms` budget.

### capture

`capture` records diagnostic artifacts at that point in the Scenario.

```yaml
- label: capture_failure
  capture: {}
```

`capture: {}` uses the default bundle:

```yaml
screenshot: true
snapshot: true
widgetTree: false
logs: true
```

Each option can be overridden:

```yaml
- label: capture_deep_context
  capture:
    screenshot: true
    snapshot: true
    widgetTree: true
    logs: true
```

Runtime errors are collected as part of logs in the first version.

## Runtime Target Is Not YAML

Do not put connection or device details in a Scenario file. Runtime Target
details are produced by `flutter_pilot test` after it launches the current
Target App Package with `flutter run --machine`. Target Device, Flutter flavor,
and app entrypoint choices stay in CLI options so Scenarios remain portable
across machines, devices, and CI.

```bash
flutter_pilot test examples/smoke_scenario.yaml --device pixel-8
```

`test --target` selects the Flutter app entrypoint file, such as
`lib/main_staging.dart`; it is not a VM service URI option.

## Validation Rules

Flutter Pilot validates Scenario YAML strictly:

- Top-level `steps` is required.
- Top-level `scenario` metadata is optional.
- Unknown fields are validation errors.
- `scenario.recording` must be a map when present.
- `scenario.recording` accepts only `enabled`.
- Each Step must have exactly one action.
- A Step containing only `label` is invalid.
- `tap`, `type`, and `waitFor` require a Finder.
- `scroll` may omit a Finder.
- `capture` does not use a Finder.
- `byText` and `byType` must be single strings.
- Step labels must be unique (checked after include expansion).
- `scroll` must have a non-zero `deltaX` or `deltaY`.
- `waitFor.timeoutMs` defaults to `3000`.
- Step Includes use `include:` with a file path.
- Step Include entries reject extra fields beyond `include`.
- Step Library files cannot define `scenario` metadata.
- Step Includes require file context; in-memory parsing rejects them.
- Missing included files produce a validation error with the include path.
- Include cycles produce a validation error instead of recursion overflow.
- Relative include paths resolve against the source file, not the process
  working directory.

Run validation without connecting to a Flutter app:

```bash
flutter_pilot validate examples/smoke_scenario.yaml
```

Use JSON output for tools:

```bash
flutter_pilot validate examples/smoke_scenario.yaml --json
```
