# Flutter Pilot

Flutter Pilot is a reproducible UI debugging context for Flutter apps. It defines the language for describing UI paths, diagnostic capture, and agent-ready debugging artifacts.

## Language

**Scenario**:
A YAML-defined, reproducible UI path that Flutter Pilot can run against a Flutter app. It includes ordered actions, waits, and diagnostic capture points.
_Avoid_: Flow, script, test case

**Entry Scenario**:
The Scenario YAML file passed directly to Flutter Pilot CLI validation or execution. Its Scenario metadata is optional and, when present, belongs to the Scenario being validated or run.
_Avoid_: Root scenario, main scenario, scenario file

**Pilot Directory**:
The conventional project directory that contains Flutter Pilot-authored Scenario assets for a Target App Package. It is the default discovery location for Project Scenarios.
_Avoid_: Test directory, scenarios directory, e2e directory

**Project Scenarios**:
The Entry Scenario files discovered for a Target App Package when Flutter Pilot is asked to run the project's Scenario set. Directory discovery includes only files that declare Scenario metadata, so Step Libraries are not run by themselves.
_Avoid_: Scenario Suite, full test, all YAML files

**Project Run**:
A Flutter Pilot execution that runs multiple Project Scenarios as one batch for a Target App Package. A Project Run has one batch-level run directory that groups each Scenario Run directory and a project-level summary report.
_Avoid_: Full test run, test suite run, all-Scenario run

**Test Execution Session**:
The shared execution lifetime inside `flutter_pilot test` that prepares one launched Target App Package for Scenario execution, exposes the Runtime Target and Target Device selected for that launch, handles launch progress and interruption, and owns cleanup. A single Entry Scenario uses one Test Execution Session for one Scenario Run; a Project Run uses one Test Execution Session across multiple Project Scenarios with hot restarts between later Scenarios.
_Avoid_: Run command, Project Run, Scenario Run

**Runtime Target**:
The running Flutter app instance that a Scenario is executed against. Connection details for the Runtime Target are provided outside the Scenario.
_Avoid_: Target configuration, environment block

**Debug Runtime Target**:
A Runtime Target running as a Flutter debug app with a reachable VM Service URI and the Flutter runtime extensions needed by Flutter Pilot.
_Avoid_: Profile target, release target, installed app

**Non-invasive Runtime Access**:
Runtime Target access that does not require the Target App Package to add Flutter Pilot code, plugins, hooks, or SDK initialization.
_Avoid_: App SDK integration, target-side hook

**Invasive Runtime Access**:
Runtime Target access that requires the Target App Package to depend on and initialize Flutter Pilot runtime code so Flutter Pilot can inspect and interact with the app from inside the app isolate.
_Avoid_: Non-invasive Runtime Access, external-only runtime access

**Target App Package**:
The Flutter app package in the current working directory that is expected to expose the runtime capabilities Flutter Pilot needs before it can be used as a Runtime Target.
_Avoid_: Scenario workspace, CLI workspace, project root

**Target App Launch Progress**:
User-facing feedback shown while Flutter Pilot prepares the Target App Package for a Scenario Run and waits until a Runtime Target is available. It happens before Step progress because no Scenario Step can execute until the app is running.
_Avoid_: Step progress, Scenario progress, Flutter build progress

**Target Device**:
The device selected for a high-level Flutter Pilot test run. It may be selected explicitly by the user or automatically when Scenario Recording requires one recordable device. The Target App Package runs on this Flutter Device. Scenario Recording for that run must use the paired Recording Device for the same physical or virtual device, matched by exact id or by unique exact name.
_Avoid_: Runtime Target, Recording Device

**Runtime Adapter**:
The narrow interface between the Flutter Pilot runner and a concrete Flutter runtime bridge. It maps Scenario Finders, actions, and capture requests to executable runtime operations, then converts runtime results back into Flutter Pilot types.
_Avoid_: Runtime Target, driver, bridge

**pilot_runtime**:
A Flutter package that provides low-level capabilities against a Flutter Runtime Target for Flutter Pilot to consume through an adapter.
_Avoid_: Runtime Adapter, Flutter Pilot runtime

**PilotRuntimeAdapter**:
The Flutter Pilot Runtime Adapter implementation backed by `pilot_runtime`.
_Avoid_: pilot_runtime, mcp_flutter adapter

**Finder**:
A rule for finding a visible Runtime Target match that a Scenario step should interact with or wait for. A Finder may combine text, semantic node type, value key, and widget type constraints in the same step; every configured constraint must match, each constraint has one string value, and there is no separate match option.
_Avoid_: Selector, locator, query

**Finder Match**:
A Runtime Target match produced by applying a Finder during a Scenario run. A valid Finder resolution requires exactly one Finder Match; zero matches or multiple matches fail the step, and action-specific capabilities such as tapping, typing, or scrolling are validated when the action executes.
_Avoid_: First match, best match

**Finder Action Budget**:
The total time available for a Finder-backed action to synchronize with a Flutter frame and resolve exactly one Finder Match. `tap`, `type`, and targeted `scroll` use the runner's default 3000ms budget; `waitFor.timeoutMs` supplies the budget for that WaitFor Action. Frame synchronization consumes the same budget rather than adding a separate timeout.
_Avoid_: Finder timeout plus frame timeout, retry count

**Runtime Handle**:
An opaque runtime token returned with a Finder Match and accepted back by the Runtime Adapter for the immediately following action. Flutter Pilot may record it for diagnostics, but must not parse it, construct it, or treat it as stable identity.
_Avoid_: Widget id, key, Inspector id, stable reference

**Semantic Node Type**:
The semantic UI role used by the `byType` Finder constraint. It names the role exposed by runtime semantics, such as `textField`, `button`, `text`, `scrollable`, or `header`; it is not a Dart widget class name.
_Avoid_: Widget class name, runtime type expression, qualified type name

**Text Finder**:
A Finder constraint that matches exact user-visible text exposed by runtime semantics or editable text state.
_Avoid_: Contains text, fuzzy text match

**Value Key Finder**:
A Finder constraint that matches a visible target by `ValueKey<String>` value.
_Avoid_: Object key, GlobalKey, typed key expression

**Widget Type Finder**:
A Finder constraint that matches a visible target by exact Dart widget runtime type display name through the `byWidget` Scenario field.
_Avoid_: Semantic Node Type, `byType`, widget instance, widget subtree query

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
An action that moves a scrollable area by configured gesture drag deltas. It may target a specific scrollable with a Finder, or select the unique outermost visible scrollable on the dominant drag axis when no Finder is provided.
_Avoid_: Swipe

**Screenshot**:
A visual image artifact captured during a Scenario run. It represents what a human user would see on screen.
_Avoid_: Snapshot

**Widget Tree**:
A structured Flutter widget hierarchy artifact captured during a Scenario run for programmatic and agent consumption.
_Avoid_: Snapshot, screenshot, full dump

**Inspector Summary Widget Tree**:
A normalized Flutter Inspector-provided summary widget hierarchy used as Flutter Pilot's Widget Tree source. It preserves useful widget identity and hierarchy without promising a complete source-level Flutter widget dump.
_Avoid_: Full Widget Tree, Snapshot, debugDumpApp, raw Inspector response

**Capture Action**:
An action that records diagnostic artifacts at a specific Step in a Scenario. Its default bundle includes Screenshot, Widget Tree, and Logs.
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
