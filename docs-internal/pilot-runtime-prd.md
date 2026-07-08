# pilot_runtime PRD

## Problem Statement

Flutter Pilot currently depends on `mcp_toolkit` / `flutter-mcp-toolkit` for
low-level Runtime Target communication. That bridge made the first Scenario
runner possible, but it limits Flutter Pilot's ability to own its runtime
contract, add stronger Finders such as `byKey` and `byWidget`, control artifact
shape, and calibrate behavior directly against Flutter debug apps.

Flutter Pilot needs a Flutter Pilot-owned runtime package that can replay
Scenarios against Debug Runtime Targets, capture normalized Widget Tree
artifacts, and eventually replace `mcp_toolkit` without weakening the existing
Scenario semantics.

## Solution

Build `pilot_runtime` as an independent Flutter package consumed by Flutter
Pilot through `PilotRuntimeAdapter`. The package provides an app-side
`PilotRuntimeBinding` for Invasive Runtime Access and a client that connects to
the Runtime Target through VM Service. Flutter Pilot keeps the current
`mcp_flutter` path as the default until `pilot_runtime` reaches parity and is
calibrated.

`pilot_runtime` v1 requires the Target App Package to initialize
`PilotRuntimeBinding` in debug mode. Missing initialization is a run-level
initialization failure before any Scenario Step executes. There is no
Non-invasive Runtime Access fallback for runtime replay.

The new runtime keeps the current Scenario model where possible, but extends
Finder capability with `byKey` for `ValueKey<String>` and `byWidget` for exact
Dart widget runtime type matching. Snapshot artifacts are removed from the
current contract; normalized Inspector Summary Widget Tree becomes the
structured UI artifact exposed through `widgetTree`.

## User Stories

1. As a Flutter developer, I want Flutter Pilot to own its runtime bridge, so that Scenario execution is not blocked by third-party runtime limitations.
2. As a Flutter developer, I want to initialize a debug-only runtime hook in my Target App Package, so that Flutter Pilot can inspect and interact with my app from inside the app isolate.
3. As a Flutter developer, I want missing runtime initialization to fail before any Step runs, so that setup mistakes are clear and not mistaken for Finder failures.
4. As a Flutter developer, I want `mcp_toolkit` to remain the default until the new runtime is ready, so that existing Scenario workflows do not regress during development.
5. As a Flutter developer, I want an experimental switch for `PilotRuntimeAdapter`, so that I can calibrate the new runtime without changing the public CLI.
6. As a Flutter developer, I want `byText` to keep exact visible text semantics, so that existing Scenario intent stays predictable.
7. As a Flutter developer, I want `byType` to keep semantic node type semantics, so that `button` and `textField` continue to mean UI roles rather than Dart classes.
8. As a Flutter developer, I want to find widgets by `ValueKey<String>`, so that Scenarios can remain stable when visible text changes.
9. As a Flutter developer, I want to find widgets by Dart widget runtime type with `byWidget`, so that app-authored wrapper widgets can be targeted.
10. As a Flutter developer, I want `byText`, `byType`, `byKey`, and `byWidget` to combine with AND semantics, so that I can disambiguate similar UI targets.
11. As a Flutter developer, I want Finder cardinality to remain strict, so that Flutter Pilot never silently picks the first matching target.
12. As a Flutter developer, I want `byKey` and `byWidget` to work for `tap`, `type`, `waitFor`, and targeted `scroll`, so that Finder fields behave consistently across actions.
13. As a Flutter developer, I want `waitFor` to succeed for a unique visible target even if it is not tappable, so that I can wait for display-only UI.
14. As a Flutter developer, I want `tap` to fail clearly when the matched target is not tappable, so that Scenario failures explain action capability problems.
15. As a Flutter developer, I want `type` to fail clearly when the matched target is not editable text, so that text-entry failures are actionable.
16. As a Flutter developer, I want `scroll` to fail clearly when the matched target is not scrollable, so that scrolling mistakes are not hidden.
17. As a Flutter developer, I want Finder matches to ignore offstage and inactive UI, so that `waitFor` does not pass on targets the user cannot see.
18. As a Flutter developer, I want Finder diagnostics to show matched widget type, action widget type, semantic type, visible text, key, and bounds, so that ambiguous matches can be debugged.
19. As a Flutter developer, I want Runtime Handles to be opaque and short-lived, so that Flutter Pilot does not depend on unstable Flutter internals.
20. As a Flutter developer, I want wrapper widgets and child semantics to combine within the same visible target subtree, so that `byWidget` can work with custom button wrappers.
21. As a Flutter developer, I want tap to prefer semantic tap actions when available, so that taps use the most stable Flutter action path.
22. As a Flutter developer, I want tap to fall back to pointer center taps on calibrated platforms, so that targets without semantic tap actions can still be exercised.
23. As a Flutter developer, I want `type` to replace editable text without simulating platform keyboard input, so that text entry is deterministic.
24. As a Flutter developer, I want scroll deltas to remain Flutter logical pixel drag deltas, so that existing Scenario scroll semantics remain intact.
25. As a Flutter developer, I want untargeted scroll to use the primary scrollable, so that simple scrolling Scenarios remain concise.
26. As a Flutter developer, I want untargeted scroll to fail when the primary scrollable is ambiguous, so that Flutter Pilot does not pick an arbitrary scrollable.
27. As a Flutter developer, I want Widget Tree capture to use Flutter Inspector summary tree data, so that artifacts preserve useful hierarchy without raw dump noise.
28. As a Flutter developer, I want Widget Tree JSON to be normalized, so that artifacts are stable and not tied to raw Inspector response envelopes.
29. As a Flutter developer, I want Widget Tree artifacts to include schema and source metadata, so that tools can version and interpret them safely.
30. As a Flutter developer, I want Widget Tree nodes to expose `inspectorValueId` only as diagnostic data, so that it is not confused with a Runtime Handle or Finder identity.
31. As a Flutter developer, I want Widget Tree capture to require the Target App Package project root, so that Inspector can mark local project nodes.
32. As a Flutter developer, I want Widget Tree capture failures to fail explicit capture Steps, so that missing core diagnostics are visible.
33. As a Flutter developer, I want default capture and failure diagnostics to include Widget Tree, so that structured UI context is always available.
34. As a Flutter developer, I want `snapshot` removed from new Scenario capture syntax, so that there is one structured UI artifact concept.
35. As a Flutter developer, I want `--print widget-tree` to be the printed structured UI diagnostic, so that CLI language matches artifacts.
36. As a Flutter developer, I want logs to produce a not-implemented artifact in v1, so that existing capture flows can proceed while log collection is deferred.
37. As a Flutter developer, I want screenshot capture to use Flutter-layer output, so that screenshots represent the app UI rather than device chrome.
38. As a Flutter developer, I want hot reload and hot restart available through the runtime client, so that Project Runs and debugging workflows can reset app state efficiently.
39. As a Flutter developer, I want hot reload and hot restart to use VM Service or Flutter runtime capabilities, so that app-side hooks stay focused on UI replay.
40. As a contributor, I want the runtime client to hide VM Service and service extension details, so that Flutter Pilot code depends on stable package types.
41. As a contributor, I want the app-side hook protocol to have a versioned handshake, so that client/runtime incompatibilities fail clearly.
42. As a contributor, I want the Widget Tree normalizer to be a deep module, so that Inspector response changes can be handled behind one interface.
43. As a contributor, I want Finder resolution to be a deep module, so that Element, RenderObject, and Semantics evidence can evolve without changing Scenario semantics.
44. As a contributor, I want action execution to be isolated from Finder parsing, so that tap, type, and scroll capability checks can be tested independently.
45. As a contributor, I want fake VM Service and fake runtime tests, so that most runtime client behavior can be verified without launching a Flutter app.
46. As a contributor, I want calibrated smoke tests against real macOS and Android Debug Runtime Targets, so that replacement decisions are backed by live evidence.
47. As a tech lead, I want `pilot_runtime` to reach parity before replacing `mcp_toolkit`, so that migration is deliberate rather than speculative.
48. As a tech lead, I want Web, profile, and release builds excluded from the v1 support contract, so that uncalibrated runtime behavior is not overpromised.

## Implementation Decisions

- Build `pilot_runtime` as an independent Flutter package, not a pure Dart package, because the app-side hook needs Flutter bindings, Elements, Semantics, gestures, editable text state, and render objects.
- Keep `McpFlutterRuntimeAdapter` as the default runtime adapter while `pilot_runtime` is built and calibrated.
- Select `PilotRuntimeAdapter` initially with `FLUTTER_PILOT_RUNTIME=pilot_runtime`; omit the variable or set `FLUTTER_PILOT_RUNTIME=mcp_flutter` for the default path. Other values fail before Scenario execution.
- Do not update `init`, `doctor`, or default Target App Package setup until `pilot_runtime` reaches replacement parity.
- Provide one public package barrel that exports both app-side hook API and client API.
- The app-side setup uses `PilotRuntimeBinding.ensureInitialized()` inside an explicit debug-mode branch.
- `PilotRuntimeBinding.ensureInitialized()` is a no-op outside debug mode.
- Use app-side service extensions under an `ext.flutter_pilot.runtime.*` prefix.
- Add a protocol handshake extension that returns protocol version and capabilities.
- Accept only protocol version 1 in the first client.
- Treat missing runtime hook, missing handshake capability, and protocol version mismatch as run-level initialization failures.
- Derive project root from the Target App Package working directory during ordinary `flutter_pilot test` execution and carry it in runtime target metadata.
- Keep VM Service, Flutter Inspector extension names, and app hook extension names behind `PilotRuntimeClient`.
- Runtime Adapter `initialize` maps `pilot_runtime` setup failures into Flutter Pilot run-level failures before Step execution.
- Add `byKey` and `byWidget` to the public Scenario DSL once the `pilot_runtime` path lands.
- `byKey` supports only `ValueKey<String>` in v1.
- `byWidget` is exact Dart widget runtime type display name matching. It is intentionally named `byWidget` rather than `byWidgetType`.
- Preserve `byType` as Semantic Node Type and do not overload it with Dart widget class matching.
- All Finder fields remain single strings and use AND semantics.
- Do not add `match`, OR semantics, first-match behavior, priority, or fallback chains.
- `resolveFinder` returns visible Runtime Target matches. Action methods validate whether a match supports tap, text replacement, or scrolling.
- Finder matching excludes targets known to be offstage, inactive, zero-size, or invisible. Overlay occlusion is not a strong v1 guarantee.
- Finder constraints may be satisfied across the same visible target subtree and collapsed into one Runtime Target match.
- Finder match diagnostics include separate matched widget type and action widget type when those differ.
- Runtime Handles are opaque, immediate-use tokens. Flutter Pilot may pass them back and record them but must not parse, construct, or cache them across Steps.
- Tap execution prefers semantic tap actions and falls back to pointer center tap on calibrated platforms.
- Text entry supports editable text targets only and replaces existing text. It does not simulate keyboard or IME input.
- Scroll execution uses pointer drag gestures and Flutter logical pixel deltas. It does not use semantic scroll actions.
- Untargeted scroll resolves the primary scrollable and fails when that target cannot be uniquely determined.
- Remove Snapshot from the new Scenario capture contract, Runtime Adapter contract, print diagnostics, and artifact language.
- Use `widgetTree` as the structured UI capture field, print diagnostic, and report artifact type.
- Write Widget Tree artifacts with a `widget_tree` filename suffix.
- `capture: {}` defaults to Screenshot, Widget Tree, and Logs.
- Automatic failure diagnostics include Widget Tree by default.
- Widget Tree capture uses Flutter Inspector summary tree data with previews and without full details.
- Widget Tree capture sets Flutter Inspector pub root directories using the CLI-derived project root before requesting the tree.
- Widget Tree capture fails when setting pub root directories fails or the summary tree cannot be normalized.
- Widget Tree JSON includes a schema identifier, a source identifier, and one normalized root node.
- Widget Tree nodes normalize Inspector description, widget runtime type, Inspector value id, text preview, local project marker, and children.
- Rename Inspector `valueId` to `inspectorValueId` in normalized artifacts.
- Do not parse keys from Inspector `description`; `byKey` must use app-side access to real `ValueKey<String>` values.
- Screenshot capture uses a Flutter-layer or Flutter Inspector screenshot path, not device screenshots.
- Keep `collectLogs()` in the Runtime Adapter contract, but return a not-implemented logs payload from `pilot_runtime` v1.
- A `logs: true` capture writes the not-implemented logs artifact and does not fail the Step.
- Hot reload and hot restart are required runtime client capabilities before replacing `mcp_toolkit`, but they are not Scenario Step actions.
- Hot reload and hot restart use VM Service or Flutter runtime capabilities rather than app-side hook extensions.
- Web, profile, and release builds are outside the v1 support contract. macOS desktop and Android debug are the first calibrated targets; iOS requires later calibration before being claimed.

Major modules to build or modify:

- `pilot_runtime` client module: connects to VM Service, discovers the main isolate, performs protocol handshake, calls runtime and Inspector capabilities, and exposes stable Flutter Pilot-owned types.
- `pilot_runtime` app-side binding module: registers debug-only service extensions and owns hook lifecycle.
- Runtime protocol module: defines request and response envelopes, protocol versioning, capability names, and normalized errors.
- Finder resolution module: combines Element, RenderObject, editable text, and Semantics evidence into visible Runtime Target matches.
- Action execution module: performs tap, text replacement, and scroll operations against Runtime Handles.
- Widget Tree normalizer module: converts Inspector summary diagnostics into the normalized Widget Tree artifact model.
- Screenshot module: captures Flutter-layer screenshots through a calibrated runtime path.
- Hot reload/restart module: wraps VM Service or Flutter runtime reset operations.
- Flutter Pilot adapter module: maps Scenario Finders, actions, and capture requests to `pilot_runtime` client calls.
- Scenario parser and model modules: add `byKey`, `byWidget`, remove `snapshot`, and update capture defaults.
- Artifact store and report modules: add Widget Tree artifact writing and report type, remove Snapshot artifact writing from the current path.
- CLI print diagnostics module: remove `snapshot` and keep `widget-tree`.
- Diff and diagnostic summary modules: compare and summarize Widget Tree artifacts rather than Snapshot artifacts.

## Testing Decisions

- Tests should verify public behavior and contracts, not private traversal details.
- Parser tests should verify that `byKey` and `byWidget` are accepted as single-string Finder fields and combine with existing Finder fields.
- Parser tests should verify that `snapshot` is rejected in capture YAML and that `capture: {}` defaults to Widget Tree.
- Runner tests should continue using fake Runtime Adapters to verify strict cardinality, Step status, failure diagnostics, and capture behavior.
- Runner tests should verify that initialization failure from `PilotRuntimeAdapter` becomes a run-level failure before Step progress.
- Runtime adapter tests should use a fake `PilotRuntimeClient` to verify mapping between Flutter Pilot model objects and runtime calls.
- Runtime client tests should use fake VM Service responses for handshake, protocol mismatch, capability missing, Widget Tree capture, and error mapping.
- Runtime protocol tests should cover response decoding, version validation, capability validation, and structured runtime failures.
- Finder resolution tests inside `pilot_runtime` should use Flutter widget tests for visible matching, offstage exclusion, `byText`, semantic `byType`, `ValueKey<String>`, `byWidget`, strict AND combinations, and wrapper-child subtree evidence.
- Action execution tests inside `pilot_runtime` should use Flutter widget tests for semantic tap, pointer fallback, editable text replacement, targeted scroll, and primary scrollable resolution.
- Widget Tree normalizer tests should use recorded Inspector summary tree fixtures and verify normalized schema, source, node fields, child structure, missing optional fields, and rejection of invalid required shape.
- Screenshot tests should verify returned MIME type and bytes shape where the chosen screenshot path can be faked; real screenshot quality should be covered by calibration smoke tests.
- Logs tests should verify the not-implemented payload and that `logs: true` does not fail a capture Step.
- Hot reload and hot restart tests should cover client request/response behavior with fake VM Service first; real behavior should be calibrated separately.
- CLI tests should verify hidden environment switch selection, invalid environment values, `--print widget-tree`, and rejection of `--print snapshot`.
- Artifact store tests should verify `widget_tree.json` file naming, artifact type `widgetTree`, report serialization, and failure artifact purpose.
- Diff tests should verify Widget Tree artifact comparison and missing Widget Tree artifact warnings.
- Existing prior art includes parser tests through the public Scenario parser, CLI subprocess tests for command behavior, fake Runtime Adapter runner tests, artifact store tests, progress renderer tests, and adapter contract tests with mocked command responses.
- Live calibration tests should first target macOS desktop and Android debug Runtime Targets. iOS and Web should not be claimed until separate calibration evidence exists.
- Real Flutter app smoke tests should prove `byText`, semantic `byType`, `byKey`, `byWidget`, tap, type, scroll with Finder, untargeted scroll, Screenshot, Widget Tree, hot reload, and hot restart before replacement begins.

## Out of Scope

- Replacing `mcp_toolkit` as the default before `pilot_runtime` reaches parity.
- Updating `init`, `doctor`, or app setup migration before the runtime package is complete.
- Non-invasive Runtime Access fallback for runtime replay.
- Flutter Web support in the v1 contract.
- Profile or release build support.
- Natural language Scenario generation.
- Interactive recording of manual usage into YAML.
- Source-code patching automation.
- Public coordinate tap Scenario actions.
- Broad visual regression infrastructure beyond existing planned run diff behavior.
- Full log collection in `pilot_runtime` v1.
- Parsing key values out of Inspector description strings.
- Supporting `ValueKey<int>`, `ObjectKey`, `GlobalKey`, private object keys, regex Finders, fuzzy text, inherited widget type matching, or qualified widget type names.
- Exposing VM Service, Inspector, Element, SemanticsNode, or RenderObject details as Flutter Pilot's public contract.

## Further Notes

The current decision snapshot is recorded in the `pilot_runtime` grill notes and
the ADR for building `pilot_runtime` with Invasive Runtime Access. The research
report remains useful as calibration evidence, but its conservative early
recommendations are superseded where the later grill notes make a more specific
decision.

The next useful step after this PRD is to break the work into independently
grabbable issues. The safest implementation order is package skeleton and
protocol first, Widget Tree capture next, then app-side Finder/action replay,
then Flutter Pilot adapter integration behind the hidden switch, and only then
Scenario DSL/artifact migration work.
