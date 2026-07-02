---
layout: home

hero:
  name: Flutter Pilot
  text: Make Flutter UI bugs reproducible and explainable.
  tagline: Replay user journeys whenever needed, and get the screenshots, logs, UI state, and timeline reports behind every run.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/getting-started
    - theme: alt
      text: Scenario DSL
      link: /reference/scenario-dsl

features:
  - title: Write portable Scenarios
    details: Describe UI paths with Steps, Finders, waits, scrolls, and capture checkpoints.
    link: /guide/write-scenario
    linkText: Write a Scenario
  - title: Run the same path repeatedly
    details: Launch the Target App Package, wait for a Runtime Target, and collect run artifacts from one command.
    link: /guide/run-scenario
    linkText: Run a Scenario
  - title: Keep references close to code
    details: Document Scenario YAML and CLI behavior in pages that can be checked against the parser and command surface.
    link: /reference/cli
    linkText: CLI Reference
---

## Common Commands

```bash
flutter_pilot init
flutter_pilot doctor
flutter_pilot validate scenarios/login.yaml
flutter_pilot test scenarios/login.yaml
```

## Documentation Map

| Page | Use it when |
| --- | --- |
| [Getting Started](./guide/getting-started.md) | You want the shortest path from install to first run. |
| [Write a Scenario](./guide/write-scenario.md) | You are authoring YAML for a reproducible UI path. |
| [Run a Scenario](./guide/run-scenario.md) | You need launch options, checkpoints, or printed diagnostics. |
| [Scenario DSL](./reference/scenario-dsl.md) | You need exact fields, actions, and Finder rules. |
| [CLI](./reference/cli.md) | You need commands and options. |
