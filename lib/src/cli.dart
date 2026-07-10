import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/app_setup_commands.dart';
import 'commands/diff_command.dart';
import 'commands/report_command.dart';
import 'commands/test_command.dart';
import 'commands/validate_command.dart';
import 'test_command_support.dart';

/// Command-line entry point for Flutter Pilot.
///
/// It installs the first-version command surface:
/// - `validate <scenario.yaml>`
/// - `test <scenario.yaml>`
///
/// Example:
/// `FlutterPilotCli().run(['validate', 'examples/login_error.yaml'])`
class FlutterPilotCli {
  /// Creates a Flutter Pilot CLI instance.
  ///
  /// `testCommandExecutor` is injectable so tests can exercise the `test`
  /// command without launching a real Flutter app.
  const FlutterPilotCli({
    TestCommandExecutor testCommandExecutor =
        const DefaultTestCommandExecutor(),
    ProjectRunExecutor projectRunExecutor = const DefaultProjectRunExecutor(),
  }) : _testCommandExecutor = testCommandExecutor,
       _projectRunExecutor = projectRunExecutor;

  final TestCommandExecutor _testCommandExecutor;
  final ProjectRunExecutor _projectRunExecutor;

  /// Run the CLI with already-tokenized command-line arguments.
  ///
  /// Args:
  /// `arguments` is the argument list passed from `main`.
  ///
  /// Returns:
  /// A process exit code. Usage errors return `64`; validation errors return
  /// `1`; successful command shells return `0`.
  Future<int> run(List<String> arguments) async {
    final CommandRunner<int> runner =
        CommandRunner<int>(
            'flutter_pilot',
            'Replay Flutter UI scenarios and collect debugging artifacts.',
          )
          ..addCommand(ValidateCommand())
          ..addCommand(
            TestCommand(
              executor: _testCommandExecutor,
              projectRunExecutor: _projectRunExecutor,
            ),
          )
          ..addCommand(ReportCommand())
          ..addCommand(DiffCommand())
          ..addCommand(DoctorCommand())
          ..addCommand(InitCommand());

    try {
      return await runner.run(arguments) ?? 0;
    } on UsageException catch (error) {
      stderr.writeln(error.message);
      stderr.writeln();
      stderr.writeln(error.usage);
      return 64;
    }
  }
}
