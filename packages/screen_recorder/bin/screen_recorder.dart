import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';

/// Entrypoint for the interactive `screen_recorder` command.
Future<void> main(List<String> arguments) async {
  final ScreenRecorderCli cli = ScreenRecorderCli();
  final int exitCode = await cli.run(arguments);
  exit(exitCode);
}
