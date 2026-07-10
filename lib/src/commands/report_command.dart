import 'dart:io';

import 'package:args/command_runner.dart';

import '../reports/html_timeline_report.dart';

/// `report` command for regenerating HTML from an existing run directory.
///
/// It reads `<run-directory>/run_report.json` and writes `timeline.html` beside
/// the existing report artifacts.
class ReportCommand extends Command<int> {
  @override
  String get description =>
      'Generate an HTML timeline report from an existing run directory.';

  @override
  String get name => 'report';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one run directory.', usage);
    }
    final Directory runDirectory = Directory(argResults!.rest.single);
    if (!runDirectory.existsSync()) {
      stderr.writeln('Run directory does not exist: ${runDirectory.path}');
      return 1;
    }
    try {
      HtmlTimelineReport.generateFromRunDirectory(runDirectory);
      stdout.writeln('HTML report: ${runDirectory.path}/timeline.html');
      return 0;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on FormatException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}
