---
name: capability-calibration
description: Align product expectations with real technical capabilities before implementation. Use when a feature depends on an external SDK, CLI, API, runtime, browser, device, database, model, or service, and you need to verify what is actually supported, compare product intent against technical evidence, or decide whether a capability belongs in the current contract, future scope, or a spike.
---

# Capability Calibration

Use this skill before implementing or reviewing a feature whose behavior depends
on a third-party or external runtime boundary.

Core rule:

```text
Do not infer external support from internal models, mocks, PRDs, or desired DSL.
Calibrate against real external output before adding a capability to the
current contract.
```

## When To Use

Use this skill when the work depends on any external capability, including:

- SDKs, CLIs, APIs, databases, browsers, devices, runtimes, AI models, or cloud services
- adapter or integration layers
- generated output from another tool
- feature claims such as "supports byKey", "can export PDF", "returns bounds",
  "streams logs", or "provides structured errors"

Do not use this skill for purely internal logic where all inputs and behavior are
owned by this repository.

## Workflow

### 1. List Product Expectations

Write the desired user-facing capabilities in product language.

Example:

```text
- Find widgets by visible text.
- Find widgets by key.
- Find widgets by type.
- Capture screenshot, Snapshot, and Logs.
```

### 2. List Technical Approach

Name the concrete external mechanism being relied on.

Include:

- package, CLI, API, endpoint, command, runtime, or device
- version when available
- exact command or call path when known
- whether this is API-first, CLI fallback, or manual workflow

### 3. Gather Real Evidence

Prefer real output over docs, and docs over assumptions.

Use the smallest command or script that exercises the boundary. Capture:

- command/API call
- inputs
- raw response shape or representative excerpt
- version/capability/schema output if available
- failure output for unsupported cases

Avoid relying on mocks or fake adapters as evidence of external support.

### 4. Build A Capability Matrix

Use this structure:

| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| byText Finder | `semantic_snapshot.nodes[].label` | Supported | Current DSL |
| byType Finder | `semantic_snapshot.nodes[].type = button/textField` | Partial | Current DSL, semantic type only |
| byKey Finder | no key field in real output | Unsupported | Future capability |

Status values:

- `Supported`: real evidence covers the product need.
- `Partial`: real evidence supports a narrower or different semantic.
- `Unsupported`: real evidence shows the current approach cannot provide it.
- `Unknown`: evidence is missing; needs a spike before contract changes.
- `Future`: intentionally out of current scope, but worth preserving as a possible direction.

### 5. Decide Contract Placement

For each capability, choose exactly one:

- Current contract: implement, document, and test now.
- Adapter-internal behavior: usable internally, not exposed to users.
- Future capability: document as not currently supported.
- Spike required: create an issue before implementation.
- Reject: remove from product plan or DSL.

If evidence is partial, narrow the product language to match the evidence.

Example:

```text
Wrong: byType accepts Dart widget class names.
Right: byType accepts mcp_flutter semantic node types such as textField/button.
```

### 6. Update Planning Artifacts

Make the calibration result visible where future agents will look:

- PRD or issue body for product scope
- ADR or calibration note for technical evidence
- CONTEXT.md only if a domain term changed
- code comments when they describe adapter semantics
- tests so fake data matches real output shapes

Do not let mocks, fixtures, or examples claim support for unsupported external
capabilities.

## Review Checklist

Before accepting implementation, verify:

- [ ] Every external capability has real evidence or is marked as unknown/future.
- [ ] Mock/fake data matches the real external response shape.
- [ ] Product language does not overstate external support.
- [ ] Parser/model/DSL only expose current-contract capabilities.
- [ ] Unsupported capabilities fail clearly or are absent from the interface.
- [ ] Integration or manual smoke verification exists for the external boundary.

## Output Format

When reporting calibration, use:

```markdown
## Product Expectations
- ...

## Technical Approach
- ...

## Evidence
- Command/API:
- Version/schema:
- Relevant output:

## Capability Matrix
| Product capability | Technical evidence | Status | Decision |
| --- | --- | --- | --- |
| ... | ... | ... | ... |

## Contract Changes
- Current:
- Future:
- Removed:

## Follow-up
- ...
```

