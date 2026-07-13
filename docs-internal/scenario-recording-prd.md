# Flutter Pilot Scenario Recording PRD

## Problem Statement

Flutter Pilot can already replay a Scenario and collect step-level diagnostic
artifacts such as Screenshot, Snapshot, Widget Tree, and Logs. That is useful
for step-by-step debugging, but it does not capture the full device-level visual
flow across the whole Scenario Run.

Teams that already have the `screen_recorder` package need Flutter Pilot to
optionally create a Device Video Recording for the full Scenario Run without
turning recording into a Step or mixing it into Capture Action semantics.
Users need a strict Scenario DSL option that enables run-scoped recording,
starts the saved video segment before the first Step executes, stops after the
run completes, and fails clearly when recording was requested but cannot be
started.

## Solution

Add a Scenario-level recording option under `scenario.recording`. The option is
part of Scenario metadata, not a Step Action. When enabled, Flutter Pilot
creates one Recording Session for the full Scenario Run: it may prepare device
capture before Target App launch, starts the saved segment before Step
execution begins, and stops recording during run shutdown.

The first slice supports only a strict recording toggle in the YAML Scenario
schema. The accepted forms are:

- `scenario.recording: {}`
- `scenario.recording.enabled: true`
- `scenario.recording.enabled: false`

Omitting `scenario.recording` means the Scenario does not request recording.
`scenario.recording: {}` is normalized to enabled recording. The resulting
Device Video Recording is stored as a run-level artifact rather than a Step
artifact.

If a Scenario explicitly enables recording and Flutter Pilot cannot establish
the Recording Session, the `test` command fails before executing any Step.
Validation remains schema-only and does not attempt to verify local recording
backend availability.

## User Stories

1. As a Flutter developer, I want a Scenario to request full-run device video recording, so that I can review the entire visual flow around a bug.
2. As a Flutter developer, I want recording to be configured in Scenario metadata, so that it is clearly separate from Step behavior.
3. As a Flutter developer, I want the saved recording segment to start before the first Step, so that the video includes pre-interaction context without Flutter build or launch time.
4. As a Flutter developer, I want recording to stop after the run finishes, so that the final artifact covers the complete Scenario Run.
5. As a Flutter developer, I want recording to remain optional, so that ordinary runs do not pay recording cost by default.
6. As a Flutter developer, I want `scenario.recording: {}` to enable default recording behavior, so that simple Scenarios stay compact.
7. As a Flutter developer, I want `scenario.recording.enabled: true` to be accepted, so that the DSL stays explicit when desired.
8. As a Flutter developer, I want `scenario.recording.enabled: false` to be accepted, so that templates and shared Scenario files can explicitly disable recording.
9. As a Flutter developer, I want omitting `scenario.recording` to mean no recording, so that existing Scenarios remain unchanged.
10. As a Flutter developer, I want recording configuration to reject unknown fields, so that unsupported options do not appear to work silently.
11. As a Flutter developer, I want `scenario.recording: true` to be rejected, so that the schema stays structurally consistent and forward-compatible.
12. As a Flutter developer, I want recording to be represented as a typed Scenario model, so that runner behavior can depend on a stable parsed contract.
13. As a Flutter developer, I want the parsed model to distinguish missing recording configuration from explicit disablement, so that future template and merge behavior stays possible.
14. As a Flutter developer, I want `recording: {}` and `recording.enabled: true` to normalize to the same domain value, so that runner code does not depend on YAML spelling.
15. As a Flutter developer, I want recording not to appear as a Step Action, so that Capture Action semantics remain focused on diagnostic artifacts.
16. As a Flutter developer, I want the recorded video to belong to the Scenario Run rather than any individual Step, so that reports reflect its true scope.
17. As a Flutter developer, I want the run report to include the recorded video as a run-level artifact, so that automation can discover it reliably.
18. As a Flutter developer, I want recording startup failure to stop the run before Step execution, so that a requested artifact is never silently skipped.
19. As a Flutter developer, I want recording shutdown to happen during run cleanup, so that saved video files are finalized consistently.
20. As a Flutter developer, I want YAML validation to remain local and deterministic, so that `validate` does not depend on the host recording environment.
21. As a CLI user, I want `flutter_pilot validate` to accept valid recording configuration, so that I can lint Scenario files before running them.
22. As a CLI user, I want `flutter_pilot validate` to reject invalid recording keys with field paths, so that I can fix schema issues quickly.
23. As a CLI user, I want `flutter_pilot test` to fail clearly when recording is required but unavailable, so that setup problems are obvious.
24. As a CLI user, I want existing Scenarios without recording config to keep working unchanged, so that the feature is additive.
25. As an AI coding agent, I want Scenario-level recording to remain separate from Runtime Adapter operations, so that Flutter UI semantics and device recording lifecycles do not get conflated.
26. As an AI coding agent, I want the run artifact model to expose video separately from Step captures, so that downstream tooling can reason about artifact scope correctly.
27. As a maintainer, I want recording lifecycle integration isolated from Step execution logic, so that the runner remains testable.
28. As a maintainer, I want the screen recorder boundary to be narrow and fakeable, so that recording integration can be tested without real devices.
29. As a maintainer, I want artifact writing for Device Video Recording to reuse the run-level artifact model, so that report generation stays consistent.
30. As a maintainer, I want recording-enabled and recording-disabled runs covered by tests, so that future changes do not regress parser or runner behavior.

## Implementation Decisions

- Add a new Scenario domain object for Scenario Recording rather than flattening recording to a single Scenario boolean.
- The typed Scenario model carries an optional Scenario Recording object.
- Missing recording metadata is represented as `null` in the typed Scenario model.
- Explicit disablement is represented as a Scenario Recording object with `enabled: false`.
- The Scenario DSL keeps recording under `scenario.recording`, not as a top-level peer of `scenario` and `steps`.
- Recording is not a Step Action and does not modify Capture Action behavior.
- The only supported recording field in the first slice is `enabled`.
- `scenario.recording: {}` is valid and normalizes to enabled recording.
- `scenario.recording.enabled: true` and `scenario.recording.enabled: false` are valid.
- `scenario.recording: true` and `scenario.recording: false` are invalid because recording must remain a structured map.
- Unknown fields inside `scenario.recording` are validation errors.
- The parser continues to return typed domain objects on success and `ScenarioValidationException` on failure.
- The runner treats Scenario Recording as run lifecycle state, not step lifecycle state.
- The executor may prepare backend recording capture before Target App launch when a backend requires it. Physical iOS uses this to keep AVFoundation capture warm without starting the saved movie segment.
- When recording is enabled, the runner starts a Recording Session before executing any Scenario Step.
- When recording is enabled, the runner stops the Recording Session during run shutdown so the final Device Video Recording path is available.
- Prepared recording capture is disposed after Target App cleanup. Disposal is awaited and idempotent.
- If recording startup fails, the run fails before Step execution begins.
- Validation remains schema-only; host recording capability is checked only during `test`.
- Device Video Recording is stored as a run-level artifact rather than a Step artifact.
- The artifact store should expose Device Video Recording with stable run-level metadata so JSON and HTML reporting can discover it without scanning raw directories.
- Recording integration should depend on a narrow recording boundary rather than teaching the Runtime Adapter about device recording.
- The Runtime Adapter remains responsible for Flutter Runtime Target operations only: Finder resolution, Step actions, Screenshot, Snapshot, Widget Tree, and Logs.
- Build or adapt a small recording integration module that translates Scenario Recording intent into `screen_recorder` prepared capture and Recording Session lifecycle calls.
- Keep recording session acquisition, stop, and failure normalization behind a fakeable interface so runner tests do not require real Android or iOS devices.
- Documentation and glossary language should use Scenario Recording, Recording Session, Recording Device, and Device Video Recording consistently.
- No ADR is required for the Scenario DSL addition by itself; the harder-to-reverse package-separation decision is already covered by the existing screen recorder ADR.

## Testing Decisions

- Tests should verify public behavior and stable contracts, not private implementation details.
- Parser tests should extend the existing public `ScenarioParser` test style.
- Parser tests should cover omitted recording metadata.
- Parser tests should cover `scenario.recording: {}` normalizing to enabled recording.
- Parser tests should cover explicit `enabled: true`.
- Parser tests should cover explicit `enabled: false`.
- Parser tests should reject non-map recording values such as booleans or strings.
- Parser tests should reject unknown fields inside `scenario.recording`.
- CLI validation tests should verify that valid recording DSL passes `validate`.
- CLI validation tests should verify that invalid recording DSL reports structured field paths.
- Runner tests should use a fake recording boundary in the same spirit as existing fake Runtime Adapter tests.
- Runner tests should verify that recording preparation can happen before launch and that the saved Recording Session starts before Step execution when enabled.
- Runner tests should verify that recording is not started when recording is omitted or explicitly disabled.
- Runner tests should verify that startup failure ends the run before any Step executes.
- Runner tests should verify that a successful run saves a run-level Device Video Recording artifact.
- Runner tests should verify that recording cleanup integrates with existing run completion and failure reporting.
- Artifact/report tests should verify that the recorded video appears in stable run-level metadata.
- Prior art should follow the repository's existing parser tests and Scenario runner tests that assert on typed domain output, step ordering, exit behavior, and artifact metadata.

## Out of Scope

- Step-level recording start or stop actions.
- Adding video options to Capture Action.
- Device selection in Scenario YAML.
- Backend priority or platform filtering in Scenario YAML.
- Output naming, overwrite, MIME type, or richer recording backend options in Scenario YAML.
- Treating Device Video Recording as a Runtime Adapter operation.
- Recording audio.
- Mapping video files to individual Steps.
- Using video as a replacement for Screenshot, Snapshot, Widget Tree, or Logs.
- Automatic discovery or verification of recording capability during `validate`.
- Broad visual regression features based on video artifacts.

## Further Notes

- This PRD depends on the existing `screen_recorder` package effort and assumes Flutter Pilot consumes that package through a narrow integration boundary.
- Scenario Recording is intentionally a run-scoped option because the recorded device video spans the entire Scenario Run and does not belong to one Step.
- Step screenshots remain the primary step-owned visual artifact because they align directly with Step metadata, while Device Video Recording provides complementary full-run context.
- The issue tracker integration and triage label configuration are not present in the local workspace, so this PRD is currently maintained as a local document rather than published with the `ready-for-agent` label.
