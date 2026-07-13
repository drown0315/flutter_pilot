# Scenario DSL

Scenario YAML is Flutter Pilot's portable format for describing a reproducible
Flutter UI path. It records actions and diagnostic checkpoints. Runtime Target
connection details stay in CLI options.

## Minimal Scenario

```yaml scenario
steps:
  - tap:
      byText: Continue
```

`steps` is required. `scenario` metadata is optional.

## Complete Example

```yaml scenario
scenario:
  name: login_error
  description: Reproduce the invalid login message.
steps:
  - label: enter_email
    type:
      byType: textField
      text: bad@example.com
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
      widgetTree: true
      logs: true
```

## Scenario Metadata

`scenario.name` is optional. When present, it must start with a letter or digit
and may contain letters, digits, `_`, or `-`.

`scenario.description` is optional and must be a string.

Scenario Recording is optional run-level metadata under `scenario.recording`.
It is not a Step action. When enabled, Flutter Pilot may prepare device capture
before app launch, then starts the saved video segment before the first Step and
stores the result as a run-level Device Video Recording artifact.

```yaml scenario
scenario:
  name: recorded_login
  recording:
    enabled: true
steps:
  - label: capture_start
    capture: {}
```

## Steps

Each item in `steps` is either a Step or a Step Include. A Step may have a
`label` and must have exactly one action.

```yaml scenario
steps:
  - label: submit_login
    tap:
      byText: Continue
```

The label belongs beside the action, not inside it. Labels must be unique within
the expanded Scenario.

`capture` is one of the possible Step actions. If you want to interact with the
UI and then capture diagnostics, write two ordered Steps: one for the
interaction and one for `capture`.

## Step Includes

A Step Include pulls Steps from a Step Library file into the current Scenario at
the include position.

```yaml
steps:
  - include: flows/login.yaml
```

Step Libraries contain `steps` and do not define `scenario` metadata. Includes
are expanded before execution, so the runner receives a flat Step list.

## Finders

A Finder identifies the widget that an action should interact with or wait for.

| Field | Meaning |
| --- | --- |
| `byText` | Exact visible text. |
| `byType` | Semantic node type exposed by the runtime, such as `button` or `textField`. |

```yaml scenario
steps:
  - label: tap_primary_button
    tap:
      byText: Continue
      byType: button
```

When several Finder fields are present, all constraints must match. Finder
fields are single strings.

Finder-backed actions first wait up to 500ms for the current or next Flutter
frame, then poll every 50ms until exactly one match is available. The frame wait
and polling share one total budget. `tap`, `type`, and targeted `scroll` use a
3000ms budget; `waitFor.timeoutMs` sets the budget for that `waitFor` Step.
Multiple matches fail immediately.

## Actions

Flutter Pilot supports these Scenario actions:

| Action | Purpose |
| --- | --- |
| `tap` | Tap exactly one Finder Match. |
| `type` | Replace text in exactly one Finder Match. |
| `scroll` | Drag a scrollable area by logical-pixel deltas. |
| `waitFor` | Wait until a Finder resolves to exactly one match. |
| `capture` | Record diagnostic artifacts at that Step. |

### tap

```yaml scenario
steps:
  - label: open_details
    tap:
      byText: Details
```

### type

```yaml scenario
steps:
  - label: enter_email
    type:
      byType: textField
      text: user@example.com
```

### scroll

```yaml scenario
steps:
  - label: reveal_footer
    scroll:
      deltaY: -500
```

The dominant drag axis is vertical when `abs(deltaY) >= abs(deltaX)` and
horizontal otherwise. Without a Finder, Flutter Pilot selects the unique
outermost visible scrollable on that axis and avoids starting the gesture over
a nested scrollable on the same axis. Multiple peer scrollables are ambiguous;
add a Finder to choose one explicitly.

### waitFor

```yaml scenario
steps:
  - label: wait_for_success
    waitFor:
      byText: Saved
      timeoutMs: 3000
```

### capture

`capture` records diagnostic artifacts at that exact point in the Step list. It
must be written as a Step action under `steps`.

```yaml scenario
steps:
  - label: submit
    tap:
      byText: Submit
  - label: capture_state
    capture: {}
```

`capture: {}` records the default bundle: screenshot, Widget Tree, and logs.
