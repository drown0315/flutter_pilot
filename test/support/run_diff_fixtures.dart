import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Pair of before/after Scenario Run directories used by Run Diff tests.
///
/// Tests write `run_report.json` and referenced artifacts into these
/// directories, then call the public Run Diff engine or CLI against them.
class RunDiffRunPair {
  const RunDiffRunPair({required this.beforeRun, required this.afterRun});

  /// Baseline Scenario Run directory.
  final Directory beforeRun;

  /// Scenario Run directory compared against the baseline.
  final Directory afterRun;
}

/// Create the standard in-memory before/after run directories.
///
/// This helper is intended for `FileTestkit.runZoned` tests. Each test gets a
/// fresh virtual filesystem, so the fixed `/runs/before` and `/runs/after`
/// paths remain isolated.
RunDiffRunPair createMemoryRunPair() {
  final Directory beforeRun = Directory('/runs/before')
    ..createSync(recursive: true);
  final Directory afterRun = Directory('/runs/after')
    ..createSync(recursive: true);
  return RunDiffRunPair(beforeRun: beforeRun, afterRun: afterRun);
}

/// Create before/after run directories under a real temporary directory.
///
/// CLI subprocess tests cannot use `file_testkit`, so they use real files under
/// `tempDirectory`.
RunDiffRunPair createTempRunPair(Directory tempDirectory) {
  final Directory beforeRun = Directory(p.join(tempDirectory.path, 'before'))
    ..createSync(recursive: true);
  final Directory afterRun = Directory(p.join(tempDirectory.path, 'after'))
    ..createSync(recursive: true);
  return RunDiffRunPair(beforeRun: beforeRun, afterRun: afterRun);
}

/// Write the smallest `run_report.json` shape accepted by Run Diff.
///
/// Args:
/// `runDirectory` is the Scenario Run directory that receives
/// `run_report.json`.
/// `scenarioName` is written under `scenario.name`.
/// `steps` are already JSON-compatible Step report objects.
/// `diagnosticSummary` is optional top-level reduced diagnostic data.
/// `artifacts` are optional artifact index entries with relative paths.
void writeRunReport(
  Directory runDirectory, {
  String scenarioName = 'login_error',
  List<Map<String, Object?>> steps = const <Map<String, Object?>>[],
  Map<String, Object?>? diagnosticSummary,
  List<Map<String, Object?>> artifacts = const <Map<String, Object?>>[],
}) {
  final String runDirectoryPath = runDirectory.path;
  final Map<String, Object?> report = <String, Object?>{
    'scenario': <String, Object?>{'name': scenarioName},
    'status': 'passed',
    'startedAt': '2026-06-13T10:00:00.000Z',
    'durationMs': 42,
    'runDirectory': runDirectoryPath,
    'diagnosticSummary': ?diagnosticSummary,
    'artifacts': artifacts,
    'steps': steps,
  };
  File(
    p.join(runDirectoryPath, 'run_report.json'),
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
}

/// Build one Step report object for Run Diff tests.
///
/// The object mirrors the stable Step fields in `run_report.json`.
Map<String, Object?> stepReport({
  required int index,
  required String action,
  required String status,
  String? label,
  String? failureReason,
  int durationMs = 12,
}) {
  return <String, Object?>{
    'index': index,
    'label': ?label,
    'action': action,
    'status': status,
    'durationMs': durationMs,
    'failureReason': ?failureReason,
  };
}

/// Build a diagnostic summary object for top-level `run_report.json` data.
Map<String, Object?> diagnosticSummary({
  List<String> visibleText = const <String>[],
  List<String> runtimeFailures = const <String>[],
}) {
  return <String, Object?>{
    'visibleText': visibleText,
    'interactiveWidgets': const <Object?>[],
    if (runtimeFailures.isNotEmpty) 'runtimeFailures': runtimeFailures,
  };
}

/// Build one artifact index entry for `run_report.json`.
Map<String, Object?> artifactReport({
  required String type,
  required String path,
}) {
  return <String, Object?>{'type': type, 'path': path};
}

/// Write a JSON artifact referenced by a run report.
///
/// `relativePath` is resolved under `runDirectory`.
void writeJsonArtifact(
  Directory runDirectory,
  String relativePath,
  Object? payload,
) {
  final File file = File(p.join(runDirectory.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
}
