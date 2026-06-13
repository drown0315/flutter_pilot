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

`steps` is required. `scenario` metadata is optional.

## Complete Example

```yaml
scenario:
  name: login_error
  description: |
    Reproduce the invalid login message and capture the UI context.

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

## Steps

Each item in `steps` is one ordered Step. A Step may have a `label` and must
have exactly one action.

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
Zero matches fail the Step. Multiple matches fail the Step.

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

A Finder is optional. When omitted, Flutter Pilot targets the primary
scrollable. When provided, the Finder must resolve to exactly one scrollable
target.

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

`waitFor` waits until the Finder produces exactly one match. Zero matches keep
waiting until timeout. Multiple matches fail the Step.

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

Do not put connection details in a Scenario file. Runtime Target details are CLI
options so Scenarios remain portable across machines, devices, and CI.

```bash
flutter_pilot run examples/smoke_scenario.yaml --target <vm-service-uri>
```

## Validation Rules

Flutter Pilot validates Scenario YAML strictly:

- Top-level `steps` is required.
- Top-level `scenario` metadata is optional.
- Unknown fields are validation errors.
- Each Step must have exactly one action.
- A Step containing only `label` is invalid.
- `tap`, `type`, and `waitFor` require a Finder.
- `scroll` may omit a Finder.
- `capture` does not use a Finder.
- `byText` and `byType` must be single strings.
- Step labels must be unique.
- `scroll` must have a non-zero `deltaX` or `deltaY`.
- `waitFor.timeoutMs` defaults to `3000`.

Run validation without connecting to a Flutter app:

```bash
flutter_pilot validate examples/smoke_scenario.yaml
```

Use JSON output for tools:

```bash
flutter_pilot validate examples/smoke_scenario.yaml --json
```
