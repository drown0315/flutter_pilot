# Flutter Pilot App Setup PRD

## Problem Statement

Flutter Pilot can only run a Scenario against a Flutter app after the Target App Package exposes the MCP Toolkit runtime extension. Today, users can install the `flutter_pilot` command but still miss the app-side setup: adding `mcp_toolkit` to the Flutter package and wrapping `runApp` with `MCPToolkitBinding.instance.bootstrapFlutter`.

That failure mode is confusing because the CLI appears installed correctly, but `flutter_pilot run` cannot interact with the Runtime Target. Users need an obvious command that checks the current Flutter package setup and a low-risk initialization command that performs the safe dependency step while leaving app entrypoint edits to the developer.

## Solution

Add two CLI commands for the current working directory's Target App Package:

- `flutter_pilot doctor` checks whether the current directory is a Flutter package, whether `dependencies.mcp_toolkit` is present, and whether `lib/main.dart` appears to call `MCPToolkitBinding.instance.bootstrapFlutter`.
- `flutter_pilot init` performs the safe initialization step by running `flutter pub add mcp_toolkit` when the dependency is missing, then checks whether `lib/main.dart` appears to call `MCPToolkitBinding.instance.bootstrapFlutter` and prints manual code guidance when it does not.

Both commands operate on the current working directory. They do not take a path option in the first version. They use human-readable emoji status output and do not support JSON output.

## User Stories

1. As a Flutter developer, I want to check whether my Flutter app is ready for Flutter Pilot, so that I can fix setup issues before running a Scenario.
2. As a Flutter developer, I want setup checks to run from the current Flutter package, so that I do not confuse the Scenario workspace with the app being driven.
3. As a Flutter developer, I want Flutter Pilot to tell me when I am not in a Flutter package, so that I know to run the command from the app package root.
4. As a Flutter developer, I want `doctor` to check for `mcp_toolkit`, so that I know whether the Runtime Target can expose MCP Toolkit capabilities.
5. As a Flutter developer, I want `doctor` to reject `mcp_toolkit` in `dev_dependencies`, so that runtime app code imports a real dependency.
6. As a Flutter developer, I want `doctor` to check whether `bootstrapFlutter` appears in the app entrypoint, so that I know whether `runApp` has likely been wrapped.
7. As a Flutter developer, I want missing setup output to include the exact command or code direction I need, so that I can fix setup without searching documentation.
8. As a Flutter developer, I want complete setup output to be short, so that the command is useful during repeated debugging.
9. As a Flutter developer, I want `doctor` to return success when it completes checks even if setup is missing, so that diagnosis is not confused with command failure.
10. As a Flutter developer, I want `doctor` to return failure only when it cannot complete the check, so that scripts can distinguish invalid input from incomplete setup.
11. As a Flutter developer, I want `init` to add `mcp_toolkit` for me, so that the safe dependency step is automated.
12. As a Flutter developer, I want `init` to use `flutter pub add mcp_toolkit`, so that Flutter tooling owns dependency edits and lockfile updates.
13. As a Flutter developer, I want `init` to skip `flutter pub add` when `dependencies.mcp_toolkit` already exists, so that repeated runs are harmless.
14. As a Flutter developer, I want `init` to still run `flutter pub add mcp_toolkit` when the package only appears in `dev_dependencies`, so that the dependency lands in the runtime dependency section.
15. As a Flutter developer, I want `init` to stop if adding the dependency fails, so that I can address the dependency tool failure before editing app code.
16. As a Flutter developer, I want `init` not to rewrite my Dart entrypoint automatically, so that custom startup code is not broken by a generic source transform.
17. As a Flutter developer, I want `init` to print the `bootstrapFlutter` snippet when it is missing, so that I can apply the app-specific change manually.
18. As a contributor, I want app setup detection isolated from CLI rendering, so that checks can be unit tested without invoking subprocesses.
19. As a contributor, I want dependency installation isolated behind a small command runner boundary, so that `init` tests do not require a real Flutter SDK or network access.
20. As a maintainer, I want setup command output to be stable enough for CLI tests, so that changes to user-facing setup behavior are intentional.

## Implementation Decisions

- Add `doctor` to the existing CLI command surface.
- Add `init` to the existing CLI command surface.
- Both commands operate on the current working directory as the Target App Package.
- A directory qualifies as a Flutter package only when it contains `pubspec.yaml` and that file declares `dependencies.flutter.sdk: flutter`.
- If the current directory is not a Flutter package, both commands print this error and exit non-zero: `Flutter Pilot only supports Flutter packages. Run this command from a directory with a pubspec.yaml that declares dependencies.flutter.sdk: flutter.`
- `doctor` does not modify files and does not run `flutter pub add`.
- `doctor` prints only missing setup items when setup is incomplete.
- `doctor` prints a single success line when all required setup is found.
- `doctor` exits `0` when checks complete, even when setup items are missing.
- `doctor` exits `1` when setup cannot be checked, such as missing Flutter package shape, unreadable `pubspec.yaml`, malformed YAML, or file system failure.
- `init` runs `flutter pub add mcp_toolkit` when `dependencies.mcp_toolkit` is absent.
- `init` calls the `flutter` executable from `PATH`.
- `init` does not hand-edit `pubspec.yaml`.
- `init` skips dependency installation when `dependencies.mcp_toolkit` already exists.
- `init` does not accept `dev_dependencies.mcp_toolkit` as satisfying setup.
- When `mcp_toolkit` exists only in `dev_dependencies`, `init` still runs `flutter pub add mcp_toolkit`.
- `init` exits `1` and stops when `flutter pub add mcp_toolkit` fails.
- `init` never automatically edits `lib/main.dart`.
- The bootstrap check only scans `lib/main.dart` in the first version.
- The bootstrap check searches for the exact text `MCPToolkitBinding.instance.bootstrapFlutter`.
- Missing `lib/main.dart` should be reported as a missing or unconfirmed bootstrap setup item, not as a source modification opportunity.
- Human-readable command output uses `✅` for satisfied or completed items and `❌` for missing items.
- Neither command supports `--json` in the first version.
- Do not add an ADR for this feature. The decision is useful but reversible and not broad enough to need architectural history.
- Add or update user-facing documentation for Target App Package setup, `doctor`, and `init`.
- Build a deep app setup inspection module that parses the current package and returns setup findings without printing or invoking Flutter.
- Build a small dependency installer boundary that can run `flutter pub add mcp_toolkit` in production and be faked in tests.
- Keep CLI commands responsible for argument handling, exit codes, and rendering only.

## Testing Decisions

- Tests should verify public behavior and stable command output, not private helper implementation details.
- Add app setup checker tests that use filesystem test utilities to create representative Flutter and non-Flutter package shapes.
- App setup checker tests should cover a valid Flutter package with dependency and bootstrap present.
- App setup checker tests should cover a valid Flutter package missing `dependencies.mcp_toolkit`.
- App setup checker tests should cover `mcp_toolkit` present only in `dev_dependencies`.
- App setup checker tests should cover missing `lib/main.dart`.
- App setup checker tests should cover `lib/main.dart` without `MCPToolkitBinding.instance.bootstrapFlutter`.
- App setup checker tests should cover missing `pubspec.yaml`.
- App setup checker tests should cover malformed `pubspec.yaml`.
- CLI tests should run the real Dart subprocess for `doctor` and assert exit code and stdout or stderr.
- CLI tests should cover `doctor` success output.
- CLI tests should cover `doctor` missing dependency and missing bootstrap output.
- CLI tests should cover `doctor` in a non-Flutter package returning exit `1`.
- `init` command behavior should be tested with an injected dependency installer rather than a real `flutter pub add` call where possible.
- If subprocess CLI tests cannot inject the installer directly, keep detailed install behavior in module tests and use focused CLI tests for rendering and package validation.
- The test style should follow existing parser and CLI tests: public APIs for domain behavior, real subprocess tests for command behavior.

## Out of Scope

- Automatically editing `lib/main.dart`.
- Adding `init --check`.
- Adding `doctor --json` or `init --json`.
- Adding `doctor --strict`.
- Supporting a path option for checking a package other than the current working directory.
- Scanning every Dart file under `lib/` for bootstrap usage.
- Using Dart AST analysis for the bootstrap check.
- Managing FVM, custom Flutter SDK discovery, or non-PATH Flutter executables.
- Removing `mcp_toolkit` from `dev_dependencies` manually.
- Publishing an ADR for this feature.

## Further Notes

- This PRD uses the term Target App Package for the Flutter package in the current working directory that is expected to become the Runtime Target.
- The issue tracker integration and triage label configuration are not present in the local workspace, so this PRD is maintained as a local document until publishing credentials and tracker conventions are available.
