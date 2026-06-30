import 'dart:convert';
import 'dart:io';

import 'artifacts/artifact_store.dart';
import 'scenario_runner.dart';

/// Generates a browser-readable timeline from one Scenario run report.
///
/// The report uses only `ScenarioRunReport` data and relative artifact paths,
/// so it can be regenerated from an existing run directory without replaying
/// the Scenario.
class HtmlTimelineReport {
  HtmlTimelineReport._();

  /// Build a complete HTML document for one Scenario run.
  ///
  /// Args:
  /// `report` is the structured run report already written to
  /// `run_report.json`.
  ///
  /// Returns:
  /// A self-contained HTML document. Step artifacts are linked with their
  /// run-directory-relative paths, and screenshots are also shown as previews.
  static String render(ScenarioRunReport report) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('<!doctype html>')
      ..writeln('<html lang="en">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln('<title>${_escape(report.scenarioName)} timeline</title>')
      ..writeln('<style>')
      ..writeln(_styles)
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('<main>')
      ..writeln('<header class="run-summary">')
      ..writeln('<h1>${_escape(report.scenarioName)}</h1>')
      ..writeln(
        '<p class="status status-${report.status.name}">'
        '${_escape(report.status.name)}</p>',
      );
    if (report.scenarioDescription != null) {
      buffer.writeln('<p>${_escape(report.scenarioDescription!)}</p>');
    }
    buffer
      ..writeln('<dl>')
      ..writeln('<dt>Started</dt>')
      ..writeln('<dd>${_escape(report.startedAt.toIso8601String())}</dd>')
      ..writeln('<dt>Duration</dt>')
      ..writeln('<dd>${report.durationMs} ms</dd>')
      ..writeln('</dl>');
    if (report.failureReason != null) {
      buffer.writeln(
        '<p class="failure-reason">${_escape(report.failureReason!)}</p>',
      );
    }
    buffer
      ..writeln('</header>')
      ..writeln('<section class="timeline">');
    for (final StepRunReport step in report.steps) {
      _writeStep(buffer, step);
    }
    buffer
      ..writeln('</section>')
      ..writeln('</main>')
      ..writeln('</body>')
      ..writeln('</html>');
    return buffer.toString();
  }

  /// Read `run_report.json` from a run directory and rewrite `timeline.html`.
  ///
  /// Args:
  /// `runDirectory` is a directory produced by Flutter Pilot. It must contain a
  /// readable `run_report.json`.
  ///
  /// Returns:
  /// The generated HTML artifact record.
  ///
  /// Throws:
  /// `FormatException` when the report JSON is missing required fields or has
  /// an unsupported enum value.
  static ArtifactReport generateFromRunDirectory(Directory runDirectory) {
    final File reportFile = File('${runDirectory.path}/run_report.json');
    final Object? decoded = jsonDecode(reportFile.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'run_report.json must contain a JSON object.',
      );
    }
    final ScenarioRunReport report = _reportFromJson(
      decoded,
      fallbackRunDirectoryPath: runDirectory.path,
    );
    return RunArtifactWriter(runDirectory).writeHtmlReport(render(report));
  }

  /// Convert the stored `run_report.json` object back into a run report.
  static ScenarioRunReport _reportFromJson(
    Map<String, Object?> json, {
    required String fallbackRunDirectoryPath,
  }) {
    final Map<String, Object?> scenario = _requiredMap(json, 'scenario');
    final List<StepRunReport> steps = _stepsFromJson(
      _requiredList(json, 'steps'),
    );
    return ScenarioRunReport(
      scenarioName: _requiredString(scenario, 'name'),
      scenarioDescription: _optionalString(scenario, 'description'),
      totalSteps: _optionalInt(scenario, 'totalSteps') ?? steps.length,
      status: _scenarioStatus(_requiredString(json, 'status')),
      startedAt: DateTime.parse(_requiredString(json, 'startedAt')),
      durationMs: _requiredInt(json, 'durationMs'),
      steps: steps,
      runDirectoryPath:
          _optionalString(json, 'runDirectory') ?? fallbackRunDirectoryPath,
      artifacts: _artifactsFromJson(_optionalList(json, 'artifacts')),
      failureReason: _optionalString(json, 'failureReason'),
    );
  }

  /// Convert stored Step records into report Step objects.
  static List<StepRunReport> _stepsFromJson(List<Object?> items) {
    return <StepRunReport>[
      for (final Object? item in items)
        StepRunReport(
          index: _requiredInt(_asMap(item, 'steps[]'), 'index'),
          label: _optionalString(_asMap(item, 'steps[]'), 'label'),
          action: _requiredString(_asMap(item, 'steps[]'), 'action'),
          status: _stepStatus(
            _requiredString(_asMap(item, 'steps[]'), 'status'),
          ),
          durationMs: _requiredInt(_asMap(item, 'steps[]'), 'durationMs'),
          artifacts: _artifactsFromJson(
            _optionalList(_asMap(item, 'steps[]'), 'artifacts'),
          ),
          failureReason: _optionalString(
            _asMap(item, 'steps[]'),
            'failureReason',
          ),
          diagnosticFailureReason: _optionalString(
            _asMap(item, 'steps[]'),
            'diagnosticFailureReason',
          ),
        ),
    ];
  }

  /// Convert stored artifact records into report artifact objects.
  static List<ArtifactReport> _artifactsFromJson(List<Object?> items) {
    final List<ArtifactReport> artifacts = <ArtifactReport>[];
    for (final Object? item in items) {
      final Map<String, Object?> artifactJson = _asMap(item, 'artifacts[]');
      final String? purpose = _optionalString(artifactJson, 'purpose');
      artifacts.add(
        ArtifactReport(
          type: _artifactType(_requiredString(artifactJson, 'type')),
          path: _requiredString(artifactJson, 'path'),
          purpose: purpose == null ? null : _artifactPurpose(purpose),
        ),
      );
    }
    return artifacts;
  }

  /// Append one Step card to the timeline.
  static void _writeStep(StringBuffer buffer, StepRunReport step) {
    buffer
      ..writeln('<article class="step step-${step.status.name}">')
      ..writeln('<div class="step-heading">')
      ..writeln('<h2>Step ${step.index}${_labelSuffix(step.label)}</h2>')
      ..writeln(
        '<span class="status status-${step.status.name}">'
        '${_escape(step.status.name)}</span>',
      )
      ..writeln('</div>')
      ..writeln('<dl>')
      ..writeln('<dt>Action</dt>')
      ..writeln('<dd>${_escape(step.action)}</dd>')
      ..writeln('<dt>Duration</dt>')
      ..writeln('<dd>${step.durationMs} ms</dd>')
      ..writeln('</dl>');
    if (step.failureReason != null) {
      buffer.writeln(
        '<p class="failure-reason">${_escape(step.failureReason!)}</p>',
      );
    }
    if (step.diagnosticFailureReason != null) {
      buffer.writeln(
        '<p class="failure-reason">'
        '${_escape(step.diagnosticFailureReason!)}</p>',
      );
    }
    if (step.artifacts.isNotEmpty) {
      buffer.writeln('<ul class="artifacts">');
      for (final ArtifactReport artifact in step.artifacts) {
        _writeArtifact(buffer, artifact);
      }
      buffer.writeln('</ul>');
    }
    buffer.writeln('</article>');
  }

  /// Append one artifact link or preview to a Step card.
  static void _writeArtifact(StringBuffer buffer, ArtifactReport artifact) {
    final String path = _escapeAttribute(artifact.path);
    final String label = _escape(artifact.type.name);
    buffer.writeln('<li>');
    if (artifact.type == ArtifactType.screenshot) {
      buffer
        ..writeln('<a href="$path">$label</a>')
        ..writeln('<img src="$path" alt="$label">');
    } else {
      buffer.writeln('<a href="$path">$label</a>');
    }
    buffer.writeln('</li>');
  }

  /// Return the optional Step label portion for a heading.
  static String _labelSuffix(String? label) {
    if (label == null) {
      return '';
    }
    return ': ${_escape(label)}';
  }

  /// Escape text for HTML element and attribute contexts.
  static String _escape(String value) {
    return const HtmlEscape().convert(value);
  }

  /// Escape attribute values while keeping relative paths readable.
  static String _escapeAttribute(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static ScenarioRunStatus _scenarioStatus(String value) {
    return ScenarioRunStatus.values.singleWhere(
      (ScenarioRunStatus status) => status.name == value,
      orElse: () => throw FormatException('Unsupported run status: $value.'),
    );
  }

  static StepStatus _stepStatus(String value) {
    return StepStatus.values.singleWhere(
      (StepStatus status) => status.name == value,
      orElse: () => throw FormatException('Unsupported step status: $value.'),
    );
  }

  static ArtifactType _artifactType(String value) {
    return ArtifactType.values.singleWhere(
      (ArtifactType type) => type.name == value,
      orElse: () => throw FormatException('Unsupported artifact type: $value.'),
    );
  }

  static ArtifactPurpose _artifactPurpose(String value) {
    return ArtifactPurpose.values.singleWhere(
      (ArtifactPurpose purpose) => purpose.name == value,
      orElse: () =>
          throw FormatException('Unsupported artifact purpose: $value.'),
    );
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
  ) {
    return _asMap(json[key], key);
  }

  static Map<String, Object?> _asMap(Object? value, String fieldName) {
    if (value is Map<String, Object?>) {
      return value;
    }
    throw FormatException('$fieldName must be an object.');
  }

  static List<Object?> _requiredList(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is List<Object?>) {
      return value;
    }
    throw FormatException('$key must be a list.');
  }

  static List<Object?> _optionalList(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null) {
      return const <Object?>[];
    }
    if (value is List<Object?>) {
      return value;
    }
    throw FormatException('$key must be a list.');
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is String) {
      return value;
    }
    throw FormatException('$key must be a string.');
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null || value is String) {
      return value as String?;
    }
    throw FormatException('$key must be a string.');
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('$key must be an integer.');
  }

  static int? _optionalInt(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value == null || value is int) {
      return value as int?;
    }
    throw FormatException('$key must be an integer.');
  }

  static const String _styles = '''
body {
  margin: 0;
  background: #f6f7f9;
  color: #202124;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

main {
  max-width: 960px;
  margin: 0 auto;
  padding: 32px 20px;
}

.run-summary,
.step {
  background: #ffffff;
  border: 1px solid #d9dde3;
  border-radius: 8px;
  margin-bottom: 16px;
  padding: 20px;
}

.step-heading {
  align-items: center;
  display: flex;
  gap: 12px;
  justify-content: space-between;
}

h1,
h2,
p {
  margin-top: 0;
}

dl {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: 8px 16px;
}

dt {
  color: #59616e;
  font-weight: 600;
}

dd {
  margin: 0;
}

.status {
  border-radius: 999px;
  display: inline-block;
  font-size: 13px;
  font-weight: 700;
  padding: 4px 10px;
  text-transform: uppercase;
}

.status-passed {
  background: #d8f5df;
  color: #116329;
}

.status-failed {
  background: #ffe0e0;
  color: #9f1c1c;
}

.status-skipped {
  background: #eceff3;
  color: #4f5b67;
}

.step-failed {
  border-color: #e05b5b;
}

.failure-reason {
  color: #9f1c1c;
  font-weight: 600;
}

.artifacts {
  display: grid;
  gap: 12px;
  list-style: none;
  padding: 0;
}

.artifacts img {
  border: 1px solid #d9dde3;
  display: block;
  margin-top: 8px;
  max-width: 100%;
}
''';
}
