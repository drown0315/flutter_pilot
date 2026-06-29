import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../scenario.dart';

const JsonEncoder _artifactJsonEncoder = JsonEncoder.withIndent('  ');

/// Store for files produced by one or more Scenario runs.
///
/// It contains the output root selected by the runner. Each call to
/// `createRun` creates one directory under `<outputDirectory>/.runs/` using
/// the run timestamp and Scenario name.
///
/// Example:
/// `RunArtifactStore(Directory('build')).createRun(...)` writes files under a
/// directory like `build/.runs/2026-06-11_10-20_login_error/`.
class RunArtifactStore {
  const RunArtifactStore(this.outputDirectory);

  final Directory outputDirectory;

  /// Create a run directory and write the Scenario artifact.
  ///
  /// Args:
  /// `scenario` provides the run directory suffix and the content for
  /// `scenario.json`.
  /// `startedAt` provides the timestamp prefix. The value is converted to UTC
  /// before it is formatted for the directory name.
  ///
  /// Returns:
  /// A `RunArtifactWriter` whose `runDirectory` points at the newly created
  /// directory.
  ///
  /// Example:
  /// A Scenario named `login_error` started at `2026-06-11T10:20:30Z` creates
  /// `.runs/2026-06-11_10-20_login_error/`.
  RunArtifactWriter createRun({
    required Scenario scenario,
    required DateTime startedAt,
  }) {
    final Directory runsDirectory = Directory(
      p.join(outputDirectory.path, '.runs'),
    )..createSync(recursive: true);
    final Directory runDirectory = _createUniqueRunDirectory(
      runsDirectory: runsDirectory,
      startedAt: startedAt,
      scenarioName: scenario.name,
    );
    final RunArtifactWriter runStore = RunArtifactWriter(runDirectory);
    runStore.writeScenario(scenario);
    return runStore;
  }

  /// Create the next available run directory for a timestamp and Scenario name.
  ///
  /// Args:
  /// `runsDirectory` is the parent `.runs` directory.
  /// `startedAt` provides the timestamp prefix.
  /// `scenarioName` provides the suffix after the timestamp.
  ///
  /// Returns:
  /// A newly created directory. If the base path already exists, the method
  /// appends `_1`, `_2`, and so on until it finds an unused name.
  ///
  /// Example:
  /// If `2026-06-11_10-20_login_error` exists, the next directory is
  /// `2026-06-11_10-20_login_error_1`.
  Directory _createUniqueRunDirectory({
    required Directory runsDirectory,
    required DateTime startedAt,
    required String scenarioName,
  }) {
    final String timestamp = _formatTimestamp(startedAt);
    final String baseName = '${timestamp}_$scenarioName';
    var suffix = 0;
    while (true) {
      final String directoryName = suffix == 0
          ? baseName
          : '${baseName}_$suffix';
      final Directory directory = Directory(
        p.join(runsDirectory.path, directoryName),
      );
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
        return directory;
      }
      suffix++;
    }
  }

  /// Convert a timestamp into the run directory timestamp prefix.
  ///
  /// Args:
  /// `startedAt` is any `DateTime`; local values are converted to UTC before
  /// formatting.
  ///
  /// Returns:
  /// A filesystem-friendly timestamp without colons.
  ///
  /// Example:
  /// `2026-06-11T10:20:30Z` returns `2026-06-11_10-20`.
  String _formatTimestamp(DateTime startedAt) {
    final DateTime utcStartedAt = startedAt.toUtc();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${utcStartedAt.year}-'
        '${twoDigits(utcStartedAt.month)}-'
        '${twoDigits(utcStartedAt.day)}_'
        '${twoDigits(utcStartedAt.hour)}-'
        '${twoDigits(utcStartedAt.minute)}';
  }
}

/// Writer for files inside one Scenario run directory.
///
/// It contains the run directory path and writes files using paths relative to
/// that directory. Each write method returns an `ArtifactReport` that can be
/// copied into `run_report.json`.
///
/// Example:
/// `writeStepMetadata([...])` writes all Step report records to `step.json`.
class RunArtifactWriter {
  const RunArtifactWriter(this.runDirectory);

  final Directory runDirectory;

  /// Write the typed Scenario as `scenario.json`.
  ///
  /// Args:
  /// `scenario` is the Scenario being executed.
  ///
  /// Returns:
  /// An artifact record with `type: scenario` and `path: scenario.json`.
  ArtifactReport writeScenario(Scenario scenario) {
    const String relativePath = 'scenario.json';
    final File scenarioFile = File(p.join(runDirectory.path, relativePath));
    scenarioFile.parent.createSync(recursive: true);
    scenarioFile.writeAsStringSync(
      _artifactJsonEncoder.convert(_scenarioToJson(scenario)),
    );
    return const ArtifactReport(
      type: ArtifactType.scenario,
      path: relativePath,
    );
  }

  /// Write the final report as `run_report.json`.
  ///
  /// Args:
  /// `reportJson` is the JSON-compatible report object produced by
  /// `ScenarioRunReport.toJson`.
  ///
  /// Returns:
  /// An artifact record with `type: runReport` and `path: run_report.json`.
  ArtifactReport writeRunReport(Map<String, Object?> reportJson) {
    const String relativePath = 'run_report.json';
    final File reportFile = File(p.join(runDirectory.path, relativePath));
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(_artifactJsonEncoder.convert(reportJson));
    return const ArtifactReport(
      type: ArtifactType.runReport,
      path: relativePath,
    );
  }

  /// Write the human-readable timeline report as `timeline.html`.
  ///
  /// Args:
  /// `html` is the complete HTML document generated from `run_report.json`
  /// data and relative artifact paths.
  ///
  /// Returns:
  /// An artifact record with `type: htmlReport` and `path: timeline.html`.
  ArtifactReport writeHtmlReport(String html) {
    const String relativePath = 'timeline.html';
    final File reportFile = File(p.join(runDirectory.path, relativePath));
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(html);
    return const ArtifactReport(
      type: ArtifactType.htmlReport,
      path: relativePath,
    );
  }

  /// Write metadata for all executed Steps as `step.json`.
  ///
  /// Args:
  /// `steps` are JSON-compatible Step report payloads in execution order.
  ///
  /// Returns:
  /// An artifact record with `type: stepMetadata` and `path: step.json`.
  ArtifactReport writeStepMetadata(List<Map<String, Object?>> steps) {
    const String relativePath = 'step.json';
    final File stepFile = File(p.join(runDirectory.path, relativePath));
    stepFile.parent.createSync(recursive: true);
    stepFile.writeAsStringSync(
      _artifactJsonEncoder.convert(<String, Object?>{'steps': steps}),
    );
    return const ArtifactReport(
      type: ArtifactType.stepMetadata,
      path: relativePath,
    );
  }

  /// Write one screenshot captured by a Step.
  ///
  /// Args:
  /// `index` is the 1-based Step number.
  /// `label` is the optional Step label used in the artifact file name.
  /// `bytes` is the encoded image returned by the Runtime Adapter.
  /// `mimeType` describes the image format. The first version writes PNG files
  /// for `image/png` and uses a binary extension for other formats.
  /// `purpose` explains whether this screenshot came from an explicit capture
  /// Step or from an automatic failure bundle.
  ///
  /// Returns:
  /// An artifact record with `type: screenshot` and a path relative to the run
  /// directory.
  ArtifactReport writeScreenshot({
    required int index,
    required String? label,
    required Uint8List bytes,
    required String mimeType,
    ArtifactPurpose purpose = ArtifactPurpose.capture,
  }) {
    final String relativePath = p.join(
      'captures',
      _captureFileName(
        index: index,
        label: label,
        suffix: 'screenshot',
        extension: mimeType == 'image/png' ? 'png' : 'bin',
      ),
    );
    final File screenshotFile = File(p.join(runDirectory.path, relativePath));
    screenshotFile.parent.createSync(recursive: true);
    screenshotFile.writeAsBytesSync(bytes);
    return ArtifactReport(
      type: ArtifactType.screenshot,
      path: relativePath,
      purpose: purpose,
    );
  }

  /// Write one structured Snapshot captured by a Step.
  ///
  /// Args:
  /// `index` is the 1-based Step number.
  /// `label` is the optional Step label used in the artifact file name.
  /// `data` is the JSON-compatible Snapshot payload returned by the Runtime
  /// Adapter.
  /// `purpose` explains whether this Snapshot came from an explicit capture
  /// Step or from an automatic failure bundle.
  ///
  /// Returns:
  /// An artifact record with `type: snapshot` and a path relative to the run
  /// directory.
  ArtifactReport writeSnapshot({
    required int index,
    required String? label,
    required Object data,
    ArtifactPurpose purpose = ArtifactPurpose.capture,
  }) {
    final String relativePath = p.join(
      'captures',
      _captureFileName(
        index: index,
        label: label,
        suffix: 'snapshot',
        extension: 'json',
      ),
    );
    final File snapshotFile = File(p.join(runDirectory.path, relativePath));
    snapshotFile.parent.createSync(recursive: true);
    snapshotFile.writeAsStringSync(_artifactJsonEncoder.convert(data));
    return ArtifactReport(
      type: ArtifactType.snapshot,
      path: relativePath,
      purpose: purpose,
    );
  }

  /// Write one structured Logs capture produced by a Step.
  ///
  /// Args:
  /// `index` is the 1-based Step number.
  /// `label` is the optional Step label used in the artifact file name.
  /// `data` is the JSON-compatible Logs payload returned by the Runtime
  /// Adapter. Runtime errors are represented inside this payload when the
  /// adapter exposes them.
  /// `purpose` explains whether these Logs came from an explicit capture Step
  /// or from an automatic failure bundle.
  ///
  /// Returns:
  /// An artifact record with `type: logs` and a path relative to the run
  /// directory.
  ArtifactReport writeLogs({
    required int index,
    required String? label,
    required Object data,
    ArtifactPurpose purpose = ArtifactPurpose.capture,
  }) {
    final String relativePath = p.join(
      'captures',
      _captureFileName(
        index: index,
        label: label,
        suffix: 'logs',
        extension: 'json',
      ),
    );
    final File logsFile = File(p.join(runDirectory.path, relativePath));
    logsFile.parent.createSync(recursive: true);
    logsFile.writeAsStringSync(_artifactJsonEncoder.convert(data));
    return ArtifactReport(
      type: ArtifactType.logs,
      path: relativePath,
      purpose: purpose,
    );
  }

  /// Return the file name for one captured Step artifact.
  ///
  /// Args:
  /// `index` is the 1-based Step number. It is padded to four digits.
  /// `label` is appended after the padded number when present.
  /// `suffix` identifies the capture kind, such as `screenshot`.
  /// `extension` is the file extension without a leading dot.
  ///
  /// Returns:
  /// A capture file name such as `0001_checkpoint_screenshot.png`.
  String _captureFileName({
    required int index,
    required String? label,
    required String suffix,
    required String extension,
  }) {
    final String stepNumber = index.toString().padLeft(4, '0');
    final String prefix = label == null ? stepNumber : '${stepNumber}_$label';
    return '${prefix}_$suffix.$extension';
  }

  /// Convert a Scenario into the JSON stored in `scenario.json`.
  ///
  /// Args:
  /// `scenario` is the typed Scenario being executed.
  ///
  /// Returns:
  /// A JSON-compatible map with Scenario name, optional description, and Step
  /// records.
  Map<String, Object?> _scenarioToJson(Scenario scenario) {
    return <String, Object?>{
      'name': scenario.name,
      if (scenario.description != null) 'description': scenario.description,
      if (scenario.recording != null)
        'recording': _recordingToJson(scenario.recording!),
      'steps': <Object?>[
        for (final ScenarioStep step in scenario.steps) _stepToJson(step),
      ],
    };
  }

  /// Convert Scenario Recording metadata into the Scenario artifact shape.
  ///
  /// Args:
  /// `recording` is the parsed Scenario-level recording configuration.
  ///
  /// Returns:
  /// A JSON-compatible map that preserves the normalized `enabled` value.
  Map<String, Object?> _recordingToJson(ScenarioRecording recording) {
    return <String, Object?>{'enabled': recording.enabled};
  }

  /// Convert one Scenario Step into a JSON-compatible record.
  ///
  /// Args:
  /// `step` is the typed Scenario Step.
  ///
  /// Returns:
  /// A map containing the Step index, optional label, and one action object.
  Map<String, Object?> _stepToJson(ScenarioStep step) {
    return <String, Object?>{
      'index': step.index,
      if (step.label != null) 'label': step.label,
      if (step.source != null) 'source': _stepSourceToJson(step.source!),
      'action': _actionToJson(step.action),
    };
  }

  /// Convert Step Source metadata into the Scenario artifact shape.
  ///
  /// Args:
  /// `source` records the file and Include Chain that produced an expanded
  /// Step.
  ///
  /// Returns:
  /// A JSON-compatible source object. In-memory parsed Steps omit this object
  /// because they do not have file context.
  Map<String, Object?> _stepSourceToJson(StepSource source) {
    return <String, Object?>{
      'fileIdentity': source.fileIdentity,
      'displayPath': source.displayPath,
      'yamlPath': source.yamlPath,
      'includeChain': <Object?>[
        for (final IncludeSource include in source.includeChain)
          _includeSourceToJson(include),
      ],
    };
  }

  /// Convert one Include Chain entry into JSON.
  Map<String, Object?> _includeSourceToJson(IncludeSource include) {
    return <String, Object?>{
      'fileIdentity': include.fileIdentity,
      'displayPath': include.displayPath,
      'includePath': include.includePath,
    };
  }

  /// Convert one Scenario action into a JSON object keyed by action name.
  ///
  /// Args:
  /// `action` is the typed action from a Scenario Step.
  ///
  /// Returns:
  /// A JSON-compatible map with exactly one top-level key such as `tap`,
  /// `scroll`, or `capture`.
  Map<String, Object?> _actionToJson(StepAction action) {
    return switch (action) {
      TapAction(:final Finder finder) => <String, Object?>{
        'tap': _finderToJson(finder),
      },
      TypeAction(:final Finder finder, :final String text) => <String, Object?>{
        'type': <String, Object?>{..._finderToJson(finder), 'text': text},
      },
      ScrollAction(
        :final Finder? finder,
        :final double deltaX,
        :final double deltaY,
      ) =>
        <String, Object?>{
          'scroll': <String, Object?>{
            if (finder != null) ..._finderToJson(finder),
            'deltaX': deltaX,
            'deltaY': deltaY,
          },
        },
      WaitForAction(:final Finder finder, :final int timeoutMs) =>
        <String, Object?>{
          'waitFor': <String, Object?>{
            ..._finderToJson(finder),
            'timeoutMs': timeoutMs,
          },
        },
      CaptureAction(
        :final bool screenshot,
        :final bool snapshot,
        :final bool widgetTree,
        :final bool logs,
      ) =>
        <String, Object?>{
          'capture': <String, Object?>{
            'screenshot': screenshot,
            'snapshot': snapshot,
            'widgetTree': widgetTree,
            'logs': logs,
          },
        },
    };
  }

  /// Convert a Finder into JSON-compatible constraints.
  ///
  /// Args:
  /// `finder` contains the byText and byType constraints that were present in
  /// the Scenario.
  ///
  /// Returns:
  /// A map containing only the Finder fields that are present.
  Map<String, Object?> _finderToJson(Finder finder) {
    return <String, Object?>{
      if (finder.byText != null) 'byText': finder.byText,
      if (finder.byType != null) 'byType': finder.byType,
    };
  }
}

/// Artifact family names used in `run_report.json`.
///
/// Each value identifies the kind of file referenced by an `ArtifactReport`.
enum ArtifactType {
  scenario,
  runReport,
  htmlReport,
  stepMetadata,
  screenshot,
  snapshot,
  logs,
}

/// Reason one artifact was written during a Scenario run.
///
/// Capture artifacts can come from:
/// - an explicit Scenario `capture` Step
/// - an automatic failure bundle collected after a Step fails
///
/// Example:
/// A screenshot from `capture: {}` uses `capture`; a screenshot collected
/// after a failed tap uses `failure`.
enum ArtifactPurpose { capture, failure }

/// Metadata for one file written in a run directory.
///
/// It contains:
/// - `type`: the artifact family
/// - `path`: the file path relative to the run directory
/// - `purpose`: why a capture artifact was written, when applicable
///
/// Example:
/// `ArtifactReport(type: ArtifactType.screenshot, path: 'captures/0001.png',
/// purpose: ArtifactPurpose.failure)` records a failure screenshot.
class ArtifactReport {
  const ArtifactReport({required this.type, required this.path, this.purpose});

  final ArtifactType type;
  final String path;

  /// Why this artifact was written.
  ///
  /// Non-capture artifacts such as `scenario.json` and `run_report.json` omit
  /// this field because their role is already described by `type`.
  final ArtifactPurpose? purpose;

  /// Convert this artifact record to the JSON stored in `run_report.json`.
  ///
  /// Returns:
  /// A JSON-compatible map with `type`, `path`, and optional `purpose`.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'path': path,
      if (purpose != null) 'purpose': purpose!.name,
    };
  }
}
