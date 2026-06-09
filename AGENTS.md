# AGENTS.md

Guidance for coding agents working in this repository.

## Project Snapshot

Flutter Pilot is a Dart CLI for reproducible Flutter UI debugging artifacts. It
replays YAML Scenarios against a running Flutter app through `mcp_flutter`, then
collects screenshots, Snapshots, Widget Tree data, logs, run reports, and later
diffs.

The first implementation slice is a Dart CLI package with:

- `validate` and `run` command shells
- strict Scenario YAML parsing
- typed Scenario, Step, Finder, and action models
- structured validation exceptions
- parser tests and CLI subprocess tests

UI execution through `mcp_flutter` is not implemented yet.

## Read First

Read these before changing behavior:

- `CONTEXT.md`: project vocabulary. Preserve these terms.
- `docs/flutter-pilot-prd.md`: product scope, user stories, implementation
  decisions, testing decisions.
- `docs/adr/0001-use-dart-cli-with-yaml-scenario-dsl.md`: ADR for Dart CLI +
  YAML Scenario DSL.
- `code_conventions/dart.md`: Dart-specific coding rules.
- `code_conventions/comments.md`: comment/docstring style.

## Commands

Use the Dart SDK available in the environment.

```bash
dart format .
dart analyze
dart test
```

Third-party Dart dependencies must be added with `dart pub add`; do not manually
edit dependency entries in `pubspec.yaml`.

## Coding Rules

Follow `code_conventions/dart.md`:

- Use explicit local variable types for CLI arguments, parsed YAML values,
  validation objects, domain models, and loop variables that affect validation
  paths.
- Stateless utility classes should expose static methods and a private
  constructor.
- Parser APIs return typed domain objects on success and throw domain validation
  exceptions on failure.
- Boolean CLI flags should use `negatable: false` when the negative form is not
  meaningful.
- Every code file should contain useful doc comments. Explain objects, methods,
  arguments, return values, and validation behavior. Do not repeat obvious code.

Use `apply_patch` for manual edits. Keep edits scoped to the requested feature.

## Scenario DSL Guardrails

Runtime Target connection details are CLI options, not YAML fields.

Current Scenario rules:

- Top-level `steps` is required.
- Top-level `scenario` metadata is optional.
- Unknown fields are validation errors.
- A Step may have `label` plus exactly one action.
- Step label belongs beside the action, not inside the action.
- Supported actions: `tap`, `type`, `scroll`, `waitFor`, `capture`.
- Supported Finder fields: `byText`, `byKey`, `byType`.
- Finder fields are single strings.
- Multiple `by*` fields mean all constraints must match. There is no `match`
  field.
- `tap`, `type`, and `waitFor` require a Finder.
- `scroll` may omit Finder and then targets the primary scrollable.
- Finder Match cardinality is strict: 0 fails, 1 executes, more than 1 fails.
- `byText` is exact visible text.
- `byKey` is a logical key string, not a Dart `ValueKey(...)` expression.
- `byType` is a simple widget type name.
- `type` clears existing text and enters the configured text.
- `waitFor.timeoutMs` defaults to `3000`.
- `scroll` uses gesture drag deltas. At least one of `deltaX` or `deltaY` must
  be non-zero.
- `capture: {}` defaults to screenshot, Snapshot, and logs; Widget Tree is off
  by default. Runtime errors are part of logs in the first version.

## Testing Rules

Tests should verify public behavior, not private implementation details.

Current test shape:

- Parser tests call the public `ScenarioParser` API and assert on typed Scenario
  output or `ScenarioValidationException`.
- CLI tests run the real Dart subprocess and assert exit codes/stdout/stderr.
- Future runner tests should use a fake Runtime Adapter so core behavior can be
  tested without a live Flutter app.

Before finishing code changes, run format, analyze, and tests unless the user
explicitly asks not to.

## Issue Workflow

The local `to-issues` skill requires a version string, such as `0.0.1`, before
drafting issues. After approval, it writes the final issue breakdown to:

```text
issues/[version]-[title].md
```

GitHub issue publishing depends on a configured issue tracker or an authenticated
GitHub CLI. If publishing is unavailable, still write the local issues document
and record the publishing status.

## Current Boundaries

Do not implement these unless the task explicitly asks for them:

- video recording
- natural language Scenario generation
- interactive recording of manual usage into YAML
- source-code patching automation
- replacing `mcp_flutter`
- broad visual regression infrastructure beyond the planned before/after diff

## Git Hygiene

The worktree may contain user changes. Do not revert unrelated changes. If a
file has user edits that overlap with your task, read the file carefully and
work with those edits.

Before recommending commits, check:

```bash
git status --short
git diff --cached --stat
git diff --cached --name-status
```

Only discuss staged content as staged if `git diff --cached` is non-empty.
