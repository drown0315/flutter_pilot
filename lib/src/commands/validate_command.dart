import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../scenario_parser.dart';

/// `validate` command for checking Scenario YAML without connecting to Flutter.
///
/// It reads exactly one file path. By default it prints human-readable output;
/// with `--json` it prints a stable object containing `valid` and `errors`.
class ValidateCommand extends Command<int> {
  ValidateCommand() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print machine-readable validation output.',
    );
  }

  @override
  String get description => 'Validate a scenario YAML file.';

  @override
  String get name => 'validate';

  @override
  Future<int> run() async {
    final bool jsonOutput = argResults!.flag('json');
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one scenario file.', usage);
    }

    try {
      ScenarioParser.parseFile(argResults!.rest.single);
      if (jsonOutput) {
        _writeValidationJson(valid: true, errors: const []);
      } else {
        stdout.writeln('Scenario is valid.');
      }
      return 0;
    } on ScenarioValidationException catch (error) {
      if (jsonOutput) {
        _writeValidationJson(valid: false, errors: error.errors);
      } else {
        _writeValidationErrors(error.errors);
      }
      return 1;
    }
  }

  /// Print validation status in the `validate --json` response shape.
  void _writeValidationJson({
    required bool valid,
    required List<ScenarioValidationError> errors,
  }) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'valid': valid,
        'errors': [
          for (final ScenarioValidationError error in errors)
            {'path': error.path, 'message': error.message},
        ],
      }),
    );
  }

  /// Print validation errors as `path: message` lines for humans.
  void _writeValidationErrors(List<ScenarioValidationError> errors) {
    for (final ScenarioValidationError error in errors) {
      stderr.writeln('${error.path}: ${error.message}');
    }
  }
}


