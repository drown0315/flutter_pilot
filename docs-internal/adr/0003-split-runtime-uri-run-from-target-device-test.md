# Make Test The Only Scenario Execution Command

Flutter Pilot will expose `test` as the only CLI command that executes a
Scenario. The command launches the current Target App Package with
`flutter run --machine`, obtains the Runtime Target URI from Flutter's machine
output, runs the Scenario through the shared runner, and cleans up the launched
app process.

The `run` command and user-supplied VM service URI mode are intentionally not
part of the CLI. This keeps the user-facing surface focused on the common e2e
workflow and lets `test --target` keep Flutter CLI semantics: it names the
Flutter app entrypoint file, while `--device` selects the Target Device and
`--flavor` selects the Flutter flavor.

Scenario Recording under `test` makes Target Device a first-class concept. When
recording is enabled, the selected Target Device must be a supported Flutter
Device paired with a Recording Device by exact id or by a unique exact name
match. Flutter Pilot uses the Flutter Device id for app launch and the paired
Recording Device id for device recording. The trade-off is that workflows which
want to connect to an already-running app, such as an IDE debug session or an
externally supplied VM service URI, are out of the first CLI contract and would
require a future command if they become important again.
