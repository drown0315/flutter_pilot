# VitePress User Documentation Site

## Problem Statement

Flutter Pilot already has internal product notes, architecture decisions, and
calibration documents, but it does not yet have a clean user-facing documentation
site. That makes it hard to give users one place to learn the CLI, the Scenario
DSL, and the reporting workflow, and it also makes it easy for internal
planning material to leak into published docs by accident. The project needs a
simple documentation site that stays close to the code, is easy to build, and
keeps drift between docs and behavior under control.

## Solution

Flutter Pilot will use VitePress as the user documentation site. The published
docs will live in a dedicated documentation root, while internal PRDs, ADRs,
and calibration notes will stay in a separate internal documentation area.

The first version of the site will be English-only and focused on the most
useful user journeys:

1. Getting started
2. Writing a Scenario
3. Running a Scenario
4. Scenario DSL reference
5. CLI reference

The documentation will be written for humans first, with lightweight automated
checks for facts that drift easily. Scenario examples in the reference pages
will be validated by the real parser, and CLI documentation will be checked
against the command surface so stale examples fail fast.

## User Stories

1. As a Flutter developer, I want a single published documentation site, so
   that I can learn Flutter Pilot without reading internal planning docs.
2. As a Flutter developer, I want getting-started docs, so that I can try the
   tool in a few minutes.
3. As a Flutter developer, I want a clear guide for writing Scenarios, so that
   I can describe UI journeys in YAML correctly.
4. As a Flutter developer, I want a clear guide for running Scenarios, so that
   I understand how validation and execution differ.
5. As a Flutter developer, I want a reference page for the Scenario DSL, so
   that I can look up fields, actions, and Finder rules quickly.
6. As a Flutter developer, I want a reference page for the CLI, so that I can
   check the supported commands and options without reading source code.
7. As a Flutter developer, I want the docs site to stay in sync with code, so
   that I do not learn stale behavior.
8. As a Flutter developer, I want documented Scenario examples to be validated
   automatically, so that broken examples do not accumulate in the reference
   pages.
9. As a Flutter developer, I want CLI examples to match the actual command
   surface, so that copy-pasted commands work.
10. As a Flutter developer, I want the documentation homepage to point me to
    the right starting pages, so that I can navigate without hunting.
11. As a Flutter developer, I want the docs site to avoid internal PRDs and ADRs
    in the published tree, so that only user-facing content is exposed.
12. As a Flutter developer, I want the docs site structure to be simple, so
    that I can find guides and references by category.
13. As a Flutter developer, I want the site to build from the repository
    without extra setup, so that local doc checks are cheap to run.
14. As a Flutter developer, I want standard npm scripts for the docs site, so
    that I can build and preview it with familiar commands.
15. As a Flutter developer, I want static assets to render correctly in the docs
    site, so that screenshots and diagrams display reliably.
16. As a maintainer, I want internal design docs kept out of the published site,
    so that planning notes do not become part of the user contract.
17. As a maintainer, I want the docs site to stay English-only in the first
    version, so that localization does not block the initial release.
18. As a maintainer, I want a small, stable page set first, so that the site is
    easy to review and evolve.
19. As a maintainer, I want reference pages to be human-written but fact-checked,
    so that the docs stay readable and still resist drift.
20. As a maintainer, I want the documentation checks to run in the existing test
    pipeline, so that docs regressions fail alongside code regressions.
21. As an AI coding agent, I want the docs to expose the project vocabulary in
    one place, so that I can use the same terms as the codebase.
22. As an AI coding agent, I want a reference page for the Scenario DSL with
    real examples, so that I can generate or review valid YAML faster.
23. As an AI coding agent, I want a reference page for the CLI, so that I can
    map commands to behavior without digging through implementation details.
24. As an AI coding agent, I want the documentation homepage to be a navigation
    surface rather than a marketing page, so that I can jump straight to the
    relevant content.
25. As a QA engineer, I want the docs site to build cleanly, so that published
    documentation does not break on deployment.

## Implementation Decisions

- Use VitePress for the user documentation site.
- Keep internal PRDs, ADRs, and calibration notes outside the published docs
  tree.
- Make the published docs English-only in the first version.
- Keep the homepage as a documentation entry point, not a marketing landing
  page.
- Organize the first site around a small set of guide pages and reference
  pages.
- Write reference pages for humans first, but validate facts that drift easily.
- Keep Scenario DSL examples in the reference docs and validate them with the
  real parser.
- Keep CLI documentation human-written, but check that documented commands and
  options remain real.
- Avoid a separate generated-docs route in the site tree; if generated content is
  needed, it should land in the final page location.
- Use npm for the docs toolchain and root-level scripts for build and preview
  commands.
- Keep the documentation site and internal docs structurally separate so that
  published docs remain a clean user-facing contract.
- Build the work around a few deep modules rather than a large pile of page
  files:
  - docs site scaffold and navigation config
  - guide and reference page content
  - Scenario DSL example validation
  - CLI documentation fact checks
  - static asset publication for diagrams and screenshots
- Keep the docs site implementation small enough that most behavioral drift is
  caught by parser and CLI checks rather than by page-by-page assertions.

## Testing Decisions

- Good tests verify external behavior, not implementation details.
- The docs site build should be verified with the site builder so that broken
  markdown, config, or asset references fail early.
- Scenario DSL reference examples should be covered by parser-facing tests that
  load the documented YAML and assert that it still parses.
- CLI documentation should be covered by tests that check documented commands
  and options against the actual command surface.
- Existing parser tests and CLI subprocess tests provide the pattern for
  external-behavior coverage.
- The highest-value tests are:
  - docs site build succeeds
  - documented Scenario YAML examples still parse
  - documented CLI commands and options still exist
  - published asset references still resolve

## Out of Scope

- Full localization for the docs site.
- A marketing-style homepage.
- Separate generated-docs directories in the published site.
- Publishing internal PRDs, ADRs, or calibration notes as user docs.
- New product behavior unrelated to documentation structure.
- A complete redesign of existing internal documentation.

## Further Notes

The main value of this work is not visual polish; it is giving Flutter Pilot a
clean public documentation contract that stays close to the code and stays
useful as the CLI and Scenario DSL evolve. The site should stay small enough to
maintain, and the doc checks should focus on the facts most likely to drift.
