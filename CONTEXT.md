# Flutter Pilot

Flutter Pilot is a reproducible UI debugging context for Flutter apps. It defines the language for describing UI paths, diagnostic capture, and agent-ready debugging artifacts.

## Language

**Scenario**:
A YAML-defined, reproducible UI path that Flutter Pilot can run against a Flutter app. It includes ordered actions, waits, and diagnostic capture points.
_Avoid_: Flow, script, test case

**Entry Scenario**:
The Scenario YAML file passed directly to Flutter Pilot CLI validation or execution. Its Scenario metadata is optional and, when present, belongs to the Scenario being validated or run.
_Avoid_: Root scenario, main scenario, scenario file

**Runtime Target**:
The running Flutter app instance that a Scenario is executed against. Connection details for the Runtime Target are provided outside the Scenario.
_Avoid_: Target configuration, environment block

**Target App Package**:
The Flutter app package in the current working directory that is expected to expose the runtime capabilities Flutter Pilot needs before it can be used as a Runtime Target.
_Avoid_: Scenario workspace, CLI workspace, project root

**Target App Launch Progress**:
User-facing feedback shown while Flutter Pilot prepares the Target App Package for a Scenario Run and waits until a Runtime Target is available. It happens before Step progress because no Scenario Step can execute until the app is running.
_Avoid_: Step progress, Scenario progress, Flutter build progress

**Target Device**:
The device selected for a high-level Flutter Pilot test run. It may be selected explicitly by the user or automatically when Scenario Recording requires one recordable device. The Target App Package runs on this device, and any Scenario Recording for that run must record the same device.
_Avoid_: Runtime Target, Recording Device

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

**Step Library**:
A YAML-defined reusable collection of Steps when a file is referenced by a Step Include. In that role, it contributes Steps to the including Scenario or Step Library and does not define Scenario metadata.
_Avoid_: Shared scenario, partial Scenario, test fragment

**Step Include**:
A Scenario or Step Library entry that expands a referenced Step Library at that position. It is not a Step, does not have a Step Label, and does not execute an action by itself.
_Avoid_: Include step, import action, reusable Step

**Include Chain**:
The ordered path of Step Includes from an Entry Scenario to an expanded Step. It identifies how a Step Library contributed a Step without making those includes executable Steps.
_Avoid_: Scenario path, execution chain, call stack

**Step Source**:
The origin metadata for an expanded Step, such as the file path and include chain that produced it. It describes where a Step came from without changing how the Step executes.
_Avoid_: Execution target, runtime source

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

**Scenario Recording**:
A Scenario-level option that controls whether a Scenario Run creates a device screen Recording Session for the full run duration. It is part of Scenario metadata rather than a Step or Capture Action.
_Avoid_: Video step, capture video

**Device Video Recording**:
A device-level visual artifact recorded from a selected device screen during a Recording Session. It is separate from Scenario actions and Runtime Adapter operations because it records the device display rather than Flutter UI semantics. A saved session returns the final video file path only after recording stops.
_Avoid_: Video action, Runtime Adapter video capture

**Recording Session**:
A programmatically controlled device screen recording that starts with `startRecord` and ends with `stopRecord` or discard behavior. The session represents an active recording process; the final video path belongs to the stop result, not to session start.
_Avoid_: Timed recording, Scenario recording

**Recording Device**:
A device that can be selected by screen recording discovery and used as the source for a Recording Session. Recording Devices are discovered through platform recording backends, such as Android Debug Bridge, iOS Simulator tooling, or native iOS screen capture discovery; they are not the same as Flutter Runtime Targets.
_Avoid_: Runtime Target, Flutter device

**Run Diff**:
A comparison between two Scenario Runs that explains how Step outcomes, visible UI state, diagnostic failures, and visual artifacts changed.
_Avoid_: Directory diff, visual diff

**Regression**:
A Run Diff finding where a Scenario Run has become worse than the run it is compared against, such as a previously passing path failing or a new diagnostic failure appearing.
_Avoid_: Change, difference
