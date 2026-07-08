import 'dart:io';

import 'package:args/command_runner.dart';

import '../run_diff.dart';

/// `diff` command for comparing two existing Scenario Run directories.
///
/// It reads each directory's `run_report.json`, generates a Step-focused Run
/// Diff, and prints either human-readable output or `--json` output.
/// Regressions are report content, not process failures, so successful diff
/// generation exits `0`.
class DiffCommand extends Command<int> {
  DiffCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print machine-readable Run Diff output.',
    );
  }

  @override
  String get description => 'Compare two Scenario Run directories.';

  @override
  String get name => 'diff';

  @override
  Future<int> run() async {
    final bool jsonOutput = argResults!.flag('json');
    if (argResults!.rest.length != 2) {
      throw UsageException('Expected before and after run directories.', usage);
    }
    final Directory beforeRunDirectory = Directory(argResults!.rest[0]);
    final Directory afterRunDirectory = Directory(argResults!.rest[1]);
    try {
      final RunDiff diff = RunDiffEngine.diffDirectories(
        beforeRunDirectory: beforeRunDirectory,
        afterRunDirectory: afterRunDirectory,
      );
      if (jsonOutput) {
        stdout.writeln(RunDiffJsonRenderer.render(diff));
      } else {
        stdout.writeln(RunDiffTextRenderer.render(diff));
      }
      return 0;
    } on RunDiffException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}
