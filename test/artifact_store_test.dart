import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Artifact Store layout through its public API.
void main() {
  test('creates unique run directories for repeated scenario runs', () async {
    await FileTestkit.runZoned(() async {
      final RunArtifactStore store = RunArtifactStore(
        Directory('artifact_output'),
      );
      const Scenario scenario = Scenario(
        name: 'login_error',
        steps: <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: CaptureAction(
              screenshot: false,
              snapshot: false,
              widgetTree: false,
              logs: false,
            ),
          ),
        ],
      );
      final DateTime startedAt = DateTime.utc(2026, 6, 11, 10, 20, 30);

      final RunArtifactWriter firstRun = store.createRun(
        scenario: scenario,
        startedAt: startedAt,
      );
      final RunArtifactWriter secondRun = store.createRun(
        scenario: scenario,
        startedAt: startedAt,
      );

      expect(
        firstRun.runDirectory.path,
        'artifact_output/.runs/2026-06-11_10-20_login_error',
      );
      expect(
        secondRun.runDirectory.path,
        'artifact_output/.runs/2026-06-11_10-20_login_error_1',
      );
      expect(
        File('${firstRun.runDirectory.path}/scenario.json').existsSync(),
        isTrue,
      );
      expect(
        File('${secondRun.runDirectory.path}/scenario.json').existsSync(),
        isTrue,
      );
    });
  });

  test('writes scenario, step metadata, and run report artifacts', () async {
    await FileTestkit.runZoned(() async {
      final RunArtifactWriter writer = RunArtifactWriter(
        Directory('artifact_output/.runs/manual_run'),
      );
      const Scenario scenario = Scenario(
        name: 'login_error',
        description: 'Reproduces login failure',
        steps: <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'submit_login',
            action: TapAction(
              finder: Finder(byText: 'Log in', byType: 'button'),
            ),
          ),
          ScenarioStep(
            index: 2,
            action: TypeAction(
              finder: Finder(byText: 'email_input'),
              text: 'bad@example.com',
            ),
          ),
        ],
      );

      final ArtifactReport scenarioArtifact = writer.writeScenario(scenario);
      final ArtifactReport stepArtifact = writer.writeStepMetadata(
        <Map<String, Object?>>[
          <String, Object?>{
            'index': 1,
            'label': 'submit_login',
            'action': 'tap',
            'status': 'passed',
            'durationMs': 12,
          },
          <String, Object?>{
            'index': 2,
            'action': 'type',
            'status': 'failed',
            'durationMs': 7,
            'failureReason': 'Text entry failed.',
          },
        ],
      );
      final ArtifactReport reportArtifact = writer.writeRunReport(
        <String, Object?>{
          'scenario': <String, Object?>{'name': 'login_error'},
          'status': 'failed',
        },
      );

      expect(scenarioArtifact.type, ArtifactType.scenario);
      expect(scenarioArtifact.path, 'scenario.json');
      expect(stepArtifact.type, ArtifactType.stepMetadata);
      expect(stepArtifact.path, 'step.json');
      expect(reportArtifact.type, ArtifactType.runReport);
      expect(reportArtifact.path, 'run_report.json');

      final Map<String, Object?> scenarioJson =
          jsonDecode(
                File(
                  '${writer.runDirectory.path}/scenario.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(scenarioJson['name'], 'login_error');
      expect(scenarioJson['description'], 'Reproduces login failure');
      expect(scenarioJson['steps'], hasLength(2));
      expect(
        File('${writer.runDirectory.path}/step.json').readAsStringSync(),
        contains('"label": "submit_login"'),
      );
      expect(
        File('${writer.runDirectory.path}/step.json').readAsStringSync(),
        contains('"failureReason": "Text entry failed."'),
      );
      expect(
        File('${writer.runDirectory.path}/run_report.json').readAsStringSync(),
        contains('"status": "failed"'),
      );
    });
  });

  test('writes screenshot, Snapshot, and Logs capture artifacts', () async {
    await FileTestkit.runZoned(() async {
      final RunArtifactWriter writer = RunArtifactWriter(
        Directory('artifact_output/.runs/capture_run'),
      );
      final Uint8List screenshotBytes = Uint8List.fromList(<int>[
        137,
        80,
        78,
        71,
      ]);

      final ArtifactReport screenshotArtifact = writer.writeScreenshot(
        index: 1,
        label: 'checkpoint',
        bytes: screenshotBytes,
        mimeType: 'image/png',
      );
      final ArtifactReport snapshotArtifact = writer.writeSnapshot(
        index: 1,
        label: 'checkpoint',
        data: <String, Object?>{
          'route': '/login',
          'visibleText': <String>['Email'],
        },
      );
      final ArtifactReport logsArtifact = writer.writeLogs(
        index: 1,
        label: 'checkpoint',
        data: <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'level': 'error',
              'message': 'Validation failed.',
            },
          ],
        },
      );
      final ArtifactReport failureLogsArtifact = writer.writeLogs(
        index: 2,
        label: 'failed_submit',
        data: <String, Object?>{'entries': <Object?>[]},
        purpose: ArtifactPurpose.failure,
      );

      expect(screenshotArtifact.type, ArtifactType.screenshot);
      expect(screenshotArtifact.purpose, ArtifactPurpose.capture);
      expect(
        screenshotArtifact.path,
        'captures/0001_checkpoint_screenshot.png',
      );
      expect(snapshotArtifact.type, ArtifactType.snapshot);
      expect(snapshotArtifact.path, 'captures/0001_checkpoint_snapshot.json');
      expect(logsArtifact.type, ArtifactType.logs);
      expect(logsArtifact.path, 'captures/0001_checkpoint_logs.json');
      expect(failureLogsArtifact.purpose, ArtifactPurpose.failure);
      expect(failureLogsArtifact.toJson(), <String, Object?>{
        'type': 'logs',
        'path': 'captures/0002_failed_submit_logs.json',
        'purpose': 'failure',
      });
      expect(
        File(
          '${writer.runDirectory.path}/${screenshotArtifact.path}',
        ).readAsBytesSync(),
        screenshotBytes,
      );
      final Map<String, Object?> snapshotJson =
          jsonDecode(
                File(
                  '${writer.runDirectory.path}/${snapshotArtifact.path}',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(snapshotJson['route'], '/login');
      final Map<String, Object?> logsJson =
          jsonDecode(
                File(
                  '${writer.runDirectory.path}/${logsArtifact.path}',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(logsJson['entries'], hasLength(1));
    });
  });
}
