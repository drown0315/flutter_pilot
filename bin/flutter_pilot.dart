import 'dart:io';

import 'package:flutter_pilot/src/cli.dart';

/// Start the Flutter Pilot command-line program.
///
/// Args:
/// `arguments` are passed by the Dart runtime after executable name parsing.
///
/// Returns:
/// This function exits the process with the code returned by `FlutterPilotCli`.
Future<void> main(List<String> arguments) async {
  final int exitCode = await FlutterPilotCli().run(arguments);
  exit(exitCode);
}
