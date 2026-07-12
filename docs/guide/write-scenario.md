# Write a Scenario

A Scenario is an ordered list of Steps. Each Step may have a label and must have
exactly one action.

```yaml scenario
scenario:
  name: checkout_path
steps:
  - label: enter_email
    type:
      byType: textField
      text: user@example.com
  - label: reveal_submit
    scroll:
      deltaY: -500
  - label: submit
    tap:
      byText: Submit
      byType: button
```

## Use labels for checkpoints

Labels make CLI debugging and reports easier to read:

```yaml scenario
steps:
  - label: open_settings
    tap:
      byText: Settings
```

Labels must be unique inside a Scenario.

## Find widgets by visible UI

Use `byText` for exact visible text and `byType` for semantic node types
exposed by the runtime.

```yaml scenario
steps:
  - label: tap_primary_button
    tap:
      byText: Continue
      byType: button
```

When a Finder has multiple fields, every configured field must match.

Finder-backed actions tolerate UI that appears asynchronously: Flutter Pilot
waits for a Flutter frame and polls for one unique match within the action's
timeout budget. Multiple matches fail immediately instead of selecting the
first match.

## Capture diagnostics

`capture` is a Step action. Use it as its own Step when you want the default
diagnostic bundle at a specific point in the run.

```yaml scenario
steps:
  - label: submit
    tap:
      byText: Submit
      byType: button
  - label: capture_current_state
    capture: {}
```

A Step may have only one action, so a tap and a capture are written as two
ordered Steps.
