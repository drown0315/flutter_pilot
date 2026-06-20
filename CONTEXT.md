# Flutter Pilot

Flutter Pilot is a reproducible UI debugging context for Flutter apps. It defines the language for describing UI paths, diagnostic capture, and agent-ready debugging artifacts.

## Language

**Scenario**:
A YAML-defined, reproducible UI path that Flutter Pilot can run against a Flutter app. It includes ordered actions, waits, and diagnostic capture points.
_Avoid_: Flow, script, test case

**Runtime Target**:
The running Flutter app instance that a Scenario is executed against. Connection details for the Runtime Target are provided outside the Scenario.
_Avoid_: Target configuration, environment block

**Runtime Adapter**:
The narrow interface between the Flutter Pilot runner and a concrete Flutter runtime bridge. It maps Scenario Finders, actions, and capture requests to executable runtime operations, then converts runtime results back into Flutter Pilot types.
_Avoid_: Runtime Target, driver, bridge

**Finder**:
A rule for finding the widget that a Scenario step should interact with or wait for. A Finder may combine text and semantic node type constraints in the same step; every configured constraint must match, each constraint has one string value, and there is no separate match option.
_Avoid_: Selector, locator, query

**Finder Match**:
The widget result produced by applying a Finder during a Scenario run. A valid action requires exactly one Finder Match; zero matches or multiple matches fail the step. Its runtime identifier is an opaque Runtime Adapter reference that may be recorded and passed back to the Runtime Adapter, but must not be parsed by the runner. A Finder Match is valid only for the action immediately following the Finder resolution that produced it; the runner must not cache it for later Steps.
_Avoid_: First match, best match

**Semantic Node Type**:
The `mcp_flutter` semantic Snapshot node type used by `byType`. It names the role exposed by the runtime Snapshot, such as `textField`, `button`, `text`, `scrollable`, or `header`; it is not a Dart widget class name.
_Avoid_: Widget class name, runtime type expression, qualified type name

**Text Finder**:
A Finder constraint that matches a widget by exact visible text.
_Avoid_: Contains text, fuzzy text match

**Step**:
One ordered item in a Scenario. A Step may have a label and must have exactly one action.
_Avoid_: Command, instruction

**Step Label**:
A human-readable identifier for a Step that can be referenced by CLI debugging controls and reports. The label belongs to the Step, not to the action.
_Avoid_: Action label, marker

**Type Action**:
An action that replaces text in a widget found by a Finder. It clears existing text before entering the configured text, and is distinct from the `byType` Finder constraint.
_Avoid_: Enter text, input action

**WaitFor Action**:
An action that waits until a Finder produces exactly one match. It does not wait for disappearance, enabled state, or disabled state in the first version.
_Avoid_: Wait assertion, sleep

**Scroll Action**:
An action that moves a scrollable area by configured gesture drag deltas. It may target a specific scrollable with a Finder, or use the primary scrollable when no Finder is provided.
_Avoid_: Swipe

**Screenshot**:
A visual image artifact captured during a Scenario run. It represents what a human user would see on screen.
_Avoid_: Snapshot

**Snapshot**:
A structured UI state artifact captured during a Scenario run for programmatic and agent consumption. It summarizes what the app exposes through semantic or UI inspection, such as visible text, interactive elements, labels, roles, states, and useful identifiers.
_Avoid_: Screenshot, raw widget tree, full dump

**Widget Tree**:
A raw or near-raw Flutter widget hierarchy artifact used for deeper debugging. It is separate from a Snapshot and is not the default agent-facing artifact.
_Avoid_: Snapshot

**Capture Action**:
An action that records diagnostic artifacts at a specific Step in a Scenario. Its default bundle includes Screenshot, Snapshot, and Logs, but not Widget Tree. Runtime errors are collected as part of Logs rather than as a separate first-version artifact.
_Avoid_: Screenshot step, dump step

**Run Diff**:
A comparison between two Scenario Runs that explains how Step outcomes, visible UI state, diagnostic failures, and visual artifacts changed.
_Avoid_: Directory diff, visual diff

**Regression**:
A Run Diff finding where a Scenario Run has become worse than the run it is compared against, such as a previously passing path failing or a new diagnostic failure appearing.
_Avoid_: Change, difference
