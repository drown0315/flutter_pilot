# Use VitePress For User Documentation

Flutter Pilot will use `docs/` as the VitePress user documentation site and
keep internal planning material in `docs-internal/`. User documentation covers
installation, getting started, Scenario authoring, CLI usage, reports, and
references that can be published directly. Internal documents such as PRDs,
ADRs, calibration notes, and design drafts stay outside the published site so
they do not become part of the user-facing contract by accident.

Documentation pages will be written for humans first, with automated checks for
facts that drift easily. Scenario examples in `docs/reference/scenario-dsl.md`
should be parsed by the real Scenario parser, and CLI documentation should
eventually be checked against the command surface. Generated content should be
written into the final page when needed rather than exposed through a separate
`generated/` documentation route. The first VitePress site is English-only; the
existing Chinese README remains an entry point until the site structure is
stable enough to justify localization.
