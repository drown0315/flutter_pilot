import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Scenario execution through the public runner API.
///
/// These tests use the fake Runtime Adapter so they can verify step execution
/// and report output without requiring a live Flutter app.
void main() {
  test('executes successful Scenario steps and writes run report', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('runner_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[
            FinderMatch(id: 'tap-match', debugLabel: 'TextButton("Log in")'),
          ],
          'email_input': const <FinderMatch>[
            FinderMatch(id: 'type-match', debugLabel: 'EditableText'),
          ],
          'scrollable': const <FinderMatch>[
            FinderMatch(id: 'scroll-match', debugLabel: 'ListView'),
          ],
          'loading_done': const <FinderMatch>[
            FinderMatch(id: 'wait-match', debugLabel: 'Text("Done")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'login_error',
        description: 'Reproduces the login validation error',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'submit_login',
            action: TapAction(finder: Finder(byText: 'login_button')),
          ),
          ScenarioStep(
            index: 2,
            action: TypeAction(
              finder: Finder(byText: 'email_input'),
              text: 'bad@example.com',
            ),
          ),
          ScenarioStep(
            index: 3,
            action: ScrollAction(
              finder: Finder(byText: 'scrollable'),
              deltaX: 0,
              deltaY: -500,
            ),
          ),
          ScenarioStep(
            index: 4,
            action: WaitForAction(
              finder: Finder(byText: 'loading_done'),
              timeoutMs: 3000,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(report.scenarioName, 'login_error');
      expect(
        report.steps.map((StepRunReport step) => step.status),
        <StepStatus>[
          StepStatus.passed,
          StepStatus.passed,
          StepStatus.passed,
          StepStatus.passed,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.existsSync(), isTrue);
      expect(reportFile.readAsStringSync(), contains('"name": "login_error"'));
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.performTap,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.replaceText,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.performScroll,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });


  test(
    'emits Step started and finished progress events for successful Steps',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('progress_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          finderResults: <String, List<FinderMatch>>{
            'login_button': const <FinderMatch>[
              FinderMatch(id: 'tap-match', debugLabel: 'TextButton("Log in")'),
            ],
          },
        );
        final List<StepProgressEvent> progressEvents = <StepProgressEvent>[];
        final Scenario scenario = Scenario(
          name: 'login_error',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'submit_login',
              action: TapAction(finder: Finder(byText: 'login_button')),
            ),
            ScenarioStep(
              index: 2,
              action: CaptureAction(
                screenshot: false,
                snapshot: false,
                widgetTree: false,
                logs: false,
              ),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario, onProgress: progressEvents.add);

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          progressEvents,
          containsAllInOrder(<Matcher>[
            isA<StepStartedEvent>()
                .having(
                  (StepStartedEvent event) => event.scenarioName,
                  'name',
                  'login_error',
                )
                .having(
                  (StepStartedEvent event) => event.totalSteps,
                  'total',
                  2,
                )
                .having(
                  (StepStartedEvent event) => event.step.index,
                  'index',
                  1,
                )
                .having(
                  (StepStartedEvent event) => event.action,
                  'action',
                  'tap',
                ),
            isA<StepFinishedEvent>()
                .having(
                  (StepFinishedEvent event) => event.report.index,
                  'index',
                  1,
                )
                .having(
                  (StepFinishedEvent event) => event.report.status,
                  'status',
                  StepStatus.passed,
                ),
            isA<StepStartedEvent>()
                .having(
                  (StepStartedEvent event) => event.step.index,
                  'index',
                  2,
                )
                .having(
                  (StepStartedEvent event) => event.action,
                  'action',
                  'capture',
                ),
            isA<StepFinishedEvent>()
                .having(
                  (StepFinishedEvent event) => event.report.index,
                  'index',
                  2,
                )
                .having(
                  (StepFinishedEvent event) => event.report.status,
                  'status',
                  StepStatus.passed,
                ),
          ]),
        );
      });
    },
  );

  test('emits failed Step progress with unlabeled Steps', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('failed_progress_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'missing': const <FinderMatch>[],
        },
      );
      final List<StepProgressEvent> progressEvents = <StepProgressEvent>[];
      final Scenario scenario = Scenario(
        name: 'login_error',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'missing')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario, onProgress: progressEvents.add);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(progressEvents, hasLength(2));
      expect(progressEvents.first, isA<StepStartedEvent>());
      expect(progressEvents.last, isA<StepFinishedEvent>());
      expect((progressEvents.last as StepFinishedEvent).report.label, isNull);
    });
  });

  test('starts Scenario Recording before executing the first Step', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('recording_lifecycle_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'Continue': const <FinderMatch>[FinderMatch(id: 'continue-button')],
        },
      );
      final FakeRecordingController recordingController =
          FakeRecordingController(runtimeEvents: adapter.events);
      final Scenario scenario = Scenario(
        name: 'recorded_run',
        recording: const ScenarioRecording(enabled: true),
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        recordingController: recordingController,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(
        recordingController.events.map(
          (FakeRecordingEvent event) => event.operation,
        ),
        <RecordingOperation>[RecordingOperation.start, RecordingOperation.stop],
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.performTap,
          RuntimeOperation.dispose,
        ],
      );
      expect(
        recordingController.events
            .firstWhere(
              (FakeRecordingEvent event) =>
                  event.operation == RecordingOperation.start,
            )
            .runtimeEventCountAtStart,
        1,
      );
    });
  });

  test('does not start Scenario Recording when omitted or disabled', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('recording_disabled_output');
      final Scenario omittedScenario = Scenario(
        name: 'recording_omitted',
        steps: const <ScenarioStep>[
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
      final Scenario disabledScenario = Scenario(
        name: 'recording_disabled',
        recording: const ScenarioRecording(enabled: false),
        steps: omittedScenario.steps,
      );
      final FakeRecordingController omittedRecordingController =
          FakeRecordingController();
      final FakeRecordingController disabledRecordingController =
          FakeRecordingController();

      final ScenarioRunReport omittedReport = await ScenarioRunner(
        adapter: FakeRuntimeAdapter(),
        recordingController: omittedRecordingController,
        outputDirectory: outputDirectory,
      ).run(omittedScenario);
      final ScenarioRunReport disabledReport = await ScenarioRunner(
        adapter: FakeRuntimeAdapter(),
        recordingController: disabledRecordingController,
        outputDirectory: outputDirectory,
      ).run(disabledScenario);

      expect(omittedReport.status, ScenarioRunStatus.passed);
      expect(disabledReport.status, ScenarioRunStatus.passed);
      expect(omittedRecordingController.events, isEmpty);
      expect(disabledRecordingController.events, isEmpty);
    });
  });

  test('stores Device Video Recording as a run-level artifact', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('recording_artifact_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'Continue': const <FinderMatch>[FinderMatch(id: 'continue-button')],
        },
      );
      final FakeRecordingController recordingController =
          FakeRecordingController(
            result: const RecordingResult(
              path: 'recordings/full-run.mp4',
              mimeType: 'video/mp4',
            ),
          );
      final Scenario scenario = Scenario(
        name: 'recording_artifact',
        recording: const ScenarioRecording(enabled: true),
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        recordingController: recordingController,
        outputDirectory: outputDirectory,
      ).run(scenario);

      final ArtifactReport recordingArtifact = report.artifacts.singleWhere(
        (ArtifactReport artifact) =>
            artifact.type == ArtifactType.deviceVideoRecording,
      );
      expect(report.status, ScenarioRunStatus.passed);
      expect(recordingArtifact.path, 'recordings/full-run.mp4');
      expect(
        report.steps.single.artifacts.map(
          (ArtifactReport artifact) => artifact.type,
        ),
        isNot(contains(ArtifactType.deviceVideoRecording)),
      );
      expect(
        recordingController.events.map(
          (FakeRecordingEvent event) => event.operation,
        ),
        <RecordingOperation>[RecordingOperation.start, RecordingOperation.stop],
      );
      expect(
        _runReportFile(report).readAsStringSync(),
        contains('"type": "deviceVideoRecording"'),
      );
    });
  });

  test(
    'fails before executing Steps when Scenario Recording cannot start',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('recording_failure_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          finderResults: <String, List<FinderMatch>>{
            'Continue': const <FinderMatch>[FinderMatch(id: 'continue-button')],
          },
        );
        final FakeRecordingController recordingController =
            FakeRecordingController(
              failure: const RecordingException(
                operation: RecordingOperation.start,
                message: 'Recording device is unavailable.',
              ),
            );
        final Scenario scenario = Scenario(
          name: 'recording_start_failure',
          recording: const ScenarioRecording(enabled: true),
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              action: TapAction(finder: Finder(byText: 'Continue')),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          recordingController: recordingController,
          outputDirectory: outputDirectory,
        ).run(scenario);

        expect(report.status, ScenarioRunStatus.failed);
        expect(report.failureReason, 'Recording device is unavailable.');
        expect(report.steps, isEmpty);
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.dispose,
          ],
        );
        expect(recordingController.events, isEmpty);
      });
    },
  );
  test('creates a stable run directory with scenario metadata', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('artifact_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'capture_checkpoint',
        description: 'Collect diagnostics at a checkpoint',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'checkpoint',
            action: CaptureAction(
              screenshot: false,
              snapshot: false,
              widgetTree: false,
              logs: false,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      final Directory runsDirectory = Directory(
        '${outputDirectory.path}/.runs',
      );
      final List<Directory> runDirectories = runsDirectory
          .listSync()
          .whereType<Directory>()
          .toList(growable: false);
      expect(runDirectories, hasLength(1));

      final Directory runDirectory = runDirectories.single;
      expect(
        runDirectory.path,
        matches(
          r'artifact_output/\.runs/\d{4}-\d{2}-\d{2}_\d{2}-\d{2}_capture_checkpoint$',
        ),
      );
      expect(report.runDirectoryPath, runDirectory.path);

      final File scenarioFile = File('${runDirectory.path}/scenario.json');
      final File stepFile = File('${runDirectory.path}/step.json');
      final File reportFile = File('${runDirectory.path}/run_report.json');
      expect(scenarioFile.existsSync(), isTrue);
      expect(stepFile.existsSync(), isTrue);
      expect(reportFile.existsSync(), isTrue);
      expect(scenarioFile.readAsStringSync(), contains('"capture_checkpoint"'));
      expect(stepFile.readAsStringSync(), contains('"label": "checkpoint"'));
      expect(
        reportFile.readAsStringSync(),
        contains('"path": "scenario.json"'),
      );
      expect(reportFile.readAsStringSync(), contains('"path": "step.json"'));
    });
  });

  test('writes expanded include-backed Scenario artifacts', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('include_runner_output');
      final Directory scenarioDirectory = Directory('scenarios')
        ..createSync(recursive: true);
      File('${scenarioDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - label: included_capture
    capture:
      screenshot: false
      snapshot: false
      logs: false
''');
      final File scenarioFile = File('${scenarioDirectory.path}/entry.yaml')
        ..writeAsStringSync('''
scenario:
  name: include_runner
steps:
  - label: root_capture
    capture:
      screenshot: false
      snapshot: false
      logs: false
  - include: library.yaml
''');
      final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);

      final ScenarioRunReport report =
          await ScenarioRunner(
            adapter: FakeRuntimeAdapter(),
            outputDirectory: outputDirectory,
          ).run(
            scenario,
            stopPoint: const RunStopPoint.stepLabel('included_capture'),
          );

      expect(report.status, ScenarioRunStatus.passed);
      expect(report.steps.map((StepRunReport step) => step.label), <String?>[
        'root_capture',
        'included_capture',
      ]);
      final Map<String, Object?> scenarioJson =
          jsonDecode(
                File(
                  '${report.runDirectoryPath}/scenario.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final List<Object?> scenarioSteps =
          scenarioJson['steps']! as List<Object?>;
      expect(scenarioSteps, hasLength(2));
      expect(
        scenarioSteps.map(
          (Object? step) => (step! as Map<String, Object?>)['index'],
        ),
        <int>[1, 2],
      );
      expect(scenarioSteps.toString(), isNot(contains('include:')));
      expect(scenarioSteps.toString(), contains('included_capture'));
      expect(scenarioSteps.toString(), contains('source'));

      final Map<String, Object?> reportJson =
          jsonDecode(_runReportFile(report).readAsStringSync())
              as Map<String, Object?>;
      final List<Object?> reportSteps = reportJson['steps']! as List<Object?>;
      expect(reportSteps, hasLength(2));
      expect(
        reportSteps.map(
          (Object? step) => (step! as Map<String, Object?>)['index'],
        ),
        <int>[1, 2],
      );
    });
  });

  test(
    'emits progress events with Step Source metadata for included Steps',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('include_progress_output');
        final Directory scenarioDirectory = Directory('scenarios')
          ..createSync(recursive: true);
        File('${scenarioDirectory.path}/library.yaml').writeAsStringSync('''
steps:
  - label: included_capture
    capture:
      screenshot: false
      snapshot: false
      logs: false
''');
        final File scenarioFile = File('${scenarioDirectory.path}/entry.yaml')
          ..writeAsStringSync('''
scenario:
  name: include_progress
steps:
  - include: library.yaml
''');
        final Scenario scenario = ScenarioParser.parseFile(scenarioFile.path);
        final File progressFile = File('progress.log');
        final IOSink progressSink = progressFile.openWrite();
        final StepProgressRenderer progressRenderer = StepProgressRenderer(
          sink: progressSink,
        );

        await ScenarioRunner(
          adapter: FakeRuntimeAdapter(),
          outputDirectory: outputDirectory,
        ).run(scenario, onProgress: progressRenderer.render);
        await progressSink.close();

        final String progress = progressFile.readAsStringSync();
        expect(progress, contains('1/1 capture'));
        expect(progress, contains('ok'));
        expect(progress, contains('[library.yaml]'));
      });
    },
  );

  test('writes an HTML timeline report by default', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('html_report_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'timeline_report',
        description: 'Shows the run as a timeline',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'checkpoint',
            action: CaptureAction(
              screenshot: false,
              snapshot: false,
              widgetTree: false,
              logs: false,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      final File htmlFile = File('${report.runDirectoryPath}/timeline.html');
      expect(htmlFile.existsSync(), isTrue);
      expect(htmlFile.readAsStringSync(), contains('timeline_report'));
      expect(htmlFile.readAsStringSync(), contains('checkpoint'));
      expect(htmlFile.readAsStringSync(), contains('capture'));
      expect(htmlFile.readAsStringSync(), contains('passed'));

      final String reportJson = _runReportFile(report).readAsStringSync();
      expect(reportJson, contains('"type": "htmlReport"'));
      expect(reportJson, contains('"path": "timeline.html"'));
    });
  });

  test(
    'writes default capture screenshots, snapshots, and logs as Step artifacts',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('capture_output');
        final Uint8List screenshotBytes = Uint8List.fromList(<int>[
          137,
          80,
          78,
          71,
        ]);
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          screenshot: ScreenshotCapture(
            bytes: screenshotBytes,
            mimeType: 'image/png',
          ),
          snapshot: const SnapshotCapture(
            data: <String, Object?>{
              'route': '/login',
              'visibleText': <String>['Email', 'Password'],
            },
          ),
          logs: const LogsCapture(
            data: <String, Object?>{
              'entries': <Object?>[
                <String, Object?>{
                  'level': 'error',
                  'message': 'Incorrect email or password.',
                },
              ],
            },
          ),
        );
        final Scenario scenario = Scenario(
          name: 'capture_checkpoint',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'after_submit',
              action: CaptureAction(
                screenshot: true,
                snapshot: true,
                widgetTree: false,
                logs: true,
              ),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario);

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          report.steps.single.artifacts.map(
            (ArtifactReport artifact) => artifact.type,
          ),
          <ArtifactType>[
            ArtifactType.screenshot,
            ArtifactType.snapshot,
            ArtifactType.logs,
          ],
        );

        final ArtifactReport screenshotArtifact = report.steps.single.artifacts
            .singleWhere(
              (ArtifactReport artifact) =>
                  artifact.type == ArtifactType.screenshot,
            );
        final ArtifactReport snapshotArtifact = report.steps.single.artifacts
            .singleWhere(
              (ArtifactReport artifact) =>
                  artifact.type == ArtifactType.snapshot,
            );
        final ArtifactReport logsArtifact = report.steps.single.artifacts
            .singleWhere(
              (ArtifactReport artifact) => artifact.type == ArtifactType.logs,
            );
        expect(
          screenshotArtifact.path,
          'captures/0001_after_submit_screenshot.png',
        );
        expect(
          snapshotArtifact.path,
          'captures/0001_after_submit_snapshot.json',
        );
        expect(logsArtifact.path, 'captures/0001_after_submit_logs.json');
        expect(
          File(
            '${report.runDirectoryPath}/${screenshotArtifact.path}',
          ).readAsBytesSync(),
          screenshotBytes,
        );
        final Map<String, Object?> snapshotJson =
            jsonDecode(
                  File(
                    '${report.runDirectoryPath}/${snapshotArtifact.path}',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(snapshotJson['route'], '/login');
        final Map<String, Object?> logsJson =
            jsonDecode(
                  File(
                    '${report.runDirectoryPath}/${logsArtifact.path}',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(logsJson['entries'], hasLength(1));

        final String reportJson = _runReportFile(report).readAsStringSync();
        expect(reportJson, contains('"type": "screenshot"'));
        expect(reportJson, contains('"type": "snapshot"'));
        expect(reportJson, contains('"type": "logs"'));
        expect(reportJson, contains('"artifacts"'));
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.captureScreenshot,
            RuntimeOperation.captureSnapshot,
            RuntimeOperation.collectLogs,
            RuntimeOperation.dispose,
          ],
        );
      });
    },
  );

  test(
    'keeps successful capture artifacts when a later capture fails',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('partial_capture_output');
        final Uint8List screenshotBytes = Uint8List.fromList(<int>[
          137,
          80,
          78,
          71,
        ]);
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          screenshot: ScreenshotCapture(
            bytes: screenshotBytes,
            mimeType: 'image/png',
          ),
          failures: <RuntimeOperation, RuntimeOperationException>{
            RuntimeOperation.captureSnapshot: const RuntimeOperationException(
              operation: RuntimeOperation.captureSnapshot,
              message: 'Snapshot RPC failed.',
            ),
          },
        );
        final Scenario scenario = Scenario(
          name: 'partial_capture',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'checkpoint',
              action: CaptureAction(
                screenshot: true,
                snapshot: true,
                widgetTree: false,
                logs: true,
              ),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario);

        expect(report.status, ScenarioRunStatus.failed);
        expect(report.steps.single.status, StepStatus.failed);
        expect(report.steps.single.failureReason, 'Snapshot RPC failed.');
        expect(
          report.steps.single.artifacts.map(
            (ArtifactReport artifact) => artifact.type,
          ),
          <ArtifactType>[ArtifactType.screenshot, ArtifactType.logs],
        );
        final ArtifactReport screenshotArtifact = report.steps.single.artifacts
            .singleWhere(
              (ArtifactReport artifact) =>
                  artifact.type == ArtifactType.screenshot,
            );
        final ArtifactReport logsArtifact = report.steps.single.artifacts
            .singleWhere(
              (ArtifactReport artifact) => artifact.type == ArtifactType.logs,
            );
        expect(
          File(
            '${report.runDirectoryPath}/${screenshotArtifact.path}',
          ).readAsBytesSync(),
          screenshotBytes,
        );
        expect(
          File('${report.runDirectoryPath}/${logsArtifact.path}').existsSync(),
          isTrue,
        );
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.captureScreenshot,
            RuntimeOperation.collectLogs,
            RuntimeOperation.dispose,
          ],
        );

        final String reportJson = _runReportFile(report).readAsStringSync();
        expect(reportJson, contains('"type": "screenshot"'));
        expect(reportJson, contains('"failureReason": "Snapshot RPC failed."'));
      });
    },
  );

  test('does not collect logs when a capture Step disables logs', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('logs_disabled_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        snapshot: const SnapshotCapture(
          data: <String, Object?>{'route': '/settings'},
        ),
      );
      final Scenario scenario = Scenario(
        name: 'logs_disabled',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'checkpoint',
            action: CaptureAction(
              screenshot: false,
              snapshot: true,
              widgetTree: false,
              logs: false,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(
        report.steps.single.artifacts.map(
          (ArtifactReport artifact) => artifact.type,
        ),
        <ArtifactType>[ArtifactType.snapshot],
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.dispose,
        ],
      );

      final String reportJson = _runReportFile(report).readAsStringSync();
      expect(reportJson, isNot(contains('"type": "logs"')));
    });
  });

  test('waits until a Finder has exactly one match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_success_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResultSequences: <String, List<List<FinderMatch>>>{
          'loading_done': <List<FinderMatch>>[
            const <FinderMatch>[],
            const <FinderMatch>[
              FinderMatch(id: 'wait-match', debugLabel: 'Text("Done")'),
            ],
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'wait_for_widget',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byText: 'loading_done'),
              timeoutMs: 100,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.passed);
      expect(report.steps.single.status, StepStatus.passed);
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test(
    'stops after the selected Step number and reports later Steps skipped',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('until_number_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          finderResults: <String, List<FinderMatch>>{
            'first_button': const <FinderMatch>[FinderMatch(id: 'first-match')],
            'second_button': const <FinderMatch>[
              FinderMatch(id: 'second-match'),
            ],
          },
        );
        final Scenario scenario = Scenario(
          name: 'stop_after_first_step',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'first_step',
              action: TapAction(finder: Finder(byText: 'first_button')),
            ),
            ScenarioStep(
              index: 2,
              label: 'second_step',
              action: TapAction(finder: Finder(byText: 'second_button')),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario, stopPoint: const RunStopPoint.stepNumber(1));

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          report.steps.map((StepRunReport step) => step.status),
          <StepStatus>[StepStatus.passed, StepStatus.skipped],
        );
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.resolveFinder,
            RuntimeOperation.performTap,
            RuntimeOperation.dispose,
          ],
        );

        final String reportJson = _runReportFile(report).readAsStringSync();
        expect(reportJson, contains('"status": "skipped"'));
      });
    },
  );

  test(
    'stops after the selected Step label and reports later Steps skipped',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('until_label_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          finderResults: <String, List<FinderMatch>>{
            'first_button': const <FinderMatch>[FinderMatch(id: 'first-match')],
            'second_button': const <FinderMatch>[
              FinderMatch(id: 'second-match'),
            ],
            'third_button': const <FinderMatch>[FinderMatch(id: 'third-match')],
          },
        );
        final Scenario scenario = Scenario(
          name: 'stop_after_labeled_step',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'first_step',
              action: TapAction(finder: Finder(byText: 'first_button')),
            ),
            ScenarioStep(
              index: 2,
              label: 'checkpoint',
              action: TapAction(finder: Finder(byText: 'second_button')),
            ),
            ScenarioStep(
              index: 3,
              label: 'third_step',
              action: TapAction(finder: Finder(byText: 'third_button')),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario, stopPoint: const RunStopPoint.stepLabel('checkpoint'));

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          report.steps.map((StepRunReport step) => step.status),
          <StepStatus>[
            StepStatus.passed,
            StepStatus.passed,
            StepStatus.skipped,
          ],
        );
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.resolveFinder,
            RuntimeOperation.performTap,
            RuntimeOperation.resolveFinder,
            RuntimeOperation.performTap,
            RuntimeOperation.dispose,
          ],
        );
      });
    },
  );

  test(
    'captures printable diagnostics after the stop point in fixed order',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('print_diagnostics_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          finderResults: <String, List<FinderMatch>>{
            'first_button': const <FinderMatch>[FinderMatch(id: 'first-match')],
            'second_button': const <FinderMatch>[
              FinderMatch(id: 'second-match'),
            ],
          },
          snapshot: const SnapshotCapture(
            data: <String, Object?>{
              'route': '/login',
              'visibleText': <String>['Email', 'Password'],
            },
          ),
          widgetTree: const WidgetTreeCapture(
            data: <String, Object?>{
              'root': 'MaterialApp',
              'children': <String>['LoginPage'],
            },
          ),
          logs: const LogsCapture(
            data: <String, Object?>{
              'errors': <Object?>[
                <String, Object?>{'message': 'A RenderFlex overflowed.'},
              ],
            },
          ),
        );
        final Scenario scenario = Scenario(
          name: 'print_after_until',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'first_step',
              action: TapAction(finder: Finder(byText: 'first_button')),
            ),
            ScenarioStep(
              index: 2,
              label: 'checkpoint',
              action: TapAction(finder: Finder(byText: 'second_button')),
            ),
          ],
        );

        final ScenarioRunReport report =
            await ScenarioRunner(
              adapter: adapter,
              outputDirectory: outputDirectory,
            ).run(
              scenario,
              stopPoint: const RunStopPoint.stepLabel('checkpoint'),
              printDiagnostics: const <PrintDiagnostic>{
                PrintDiagnostic.errors,
                PrintDiagnostic.snapshot,
                PrintDiagnostic.widgetTree,
              },
            );

        expect(report.status, ScenarioRunStatus.passed);
        expect(
          report.printedDiagnostics.map(
            (PrintedDiagnostic diagnostic) => diagnostic.type,
          ),
          <PrintDiagnostic>[
            PrintDiagnostic.snapshot,
            PrintDiagnostic.widgetTree,
            PrintDiagnostic.errors,
          ],
        );
        expect(report.printedDiagnostics.first.data, <String, Object?>{
          'route': '/login',
          'visibleText': <String>['Email', 'Password'],
        });
        expect(report.diagnosticSummary?.toJson(), <String, Object?>{
          'visibleText': <Object?>['Email', 'Password'],
          'interactiveWidgets': <Object?>[],
          'routes': <Object?>['/login'],
          'runtimeFailures': <Object?>['A RenderFlex overflowed.'],
        });
        final Map<String, Object?> reportJson =
            jsonDecode(
                  File(
                    '${report.runDirectoryPath}/run_report.json',
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(reportJson['diagnosticSummary'], <String, Object?>{
          'visibleText': <Object?>['Email', 'Password'],
          'interactiveWidgets': <Object?>[],
          'routes': <Object?>['/login'],
          'runtimeFailures': <Object?>['A RenderFlex overflowed.'],
        });
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.resolveFinder,
            RuntimeOperation.performTap,
            RuntimeOperation.resolveFinder,
            RuntimeOperation.performTap,
            RuntimeOperation.captureSnapshot,
            RuntimeOperation.captureWidgetTree,
            RuntimeOperation.collectLogs,
            RuntimeOperation.dispose,
          ],
        );
      });
    },
  );

  test(
    'fails and disposes when printable diagnostics cannot be captured',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory('print_failure_output');
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          failures: <RuntimeOperation, RuntimeOperationException>{
            RuntimeOperation.captureSnapshot: const RuntimeOperationException(
              operation: RuntimeOperation.captureSnapshot,
              message: 'Snapshot capture failed.',
            ),
          },
        );
        final Scenario scenario = Scenario(
          name: 'print_failure',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'checkpoint',
              action: CaptureAction(
                screenshot: false,
                snapshot: false,
                widgetTree: false,
                logs: false,
              ),
            ),
          ],
        );

        final ScenarioRunReport report =
            await ScenarioRunner(
              adapter: adapter,
              outputDirectory: outputDirectory,
            ).run(
              scenario,
              stopPoint: const RunStopPoint.stepLabel('checkpoint'),
              printDiagnostics: const <PrintDiagnostic>{
                PrintDiagnostic.snapshot,
              },
            );

        expect(report.status, ScenarioRunStatus.failed);
        expect(report.failureReason, 'Snapshot capture failed.');
        expect(report.printedDiagnostics, isEmpty);
        expect(
          adapter.events.map((FakeRuntimeEvent event) => event.operation),
          <RuntimeOperation>[
            RuntimeOperation.initialize,
            RuntimeOperation.dispose,
          ],
        );
      });
    },
  );

  test('fails waitFor when timeout expires with no matches', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_timeout_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'wait_for_timeout',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byText: 'missing_loading_done'),
              timeoutMs: 1,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched no widgets before timeout.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        containsAllInOrder(<RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.dispose,
        ]),
      );
    });
  });

  test('fails waitFor when multiple widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('wait_for_multiple_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'loading_done': const <FinderMatch>[
            FinderMatch(id: 'first-match', debugLabel: 'Text("Done")'),
            FinderMatch(id: 'second-match', debugLabel: 'Text("Done")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'wait_for_ambiguous_widget',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: WaitForAction(
              finder: Finder(byText: 'loading_done'),
              timeoutMs: 100,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched multiple widgets.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.collectLogs,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('fails a Finder action when no widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('zero_match_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter();
      final Scenario scenario = Scenario(
        name: 'missing_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'missing_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(report.steps.single.failureReason, 'Finder matched no widgets.');
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.collectLogs,
          RuntimeOperation.dispose,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.readAsStringSync(), contains('"status": "failed"'));
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason": "Finder matched no widgets."'),
      );
    });
  });

  test('collects default failure artifacts when a Step fails', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('failure_artifacts_output');
      final Uint8List screenshotBytes = Uint8List.fromList(<int>[
        137,
        80,
        78,
        71,
      ]);
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        screenshot: ScreenshotCapture(
          bytes: screenshotBytes,
          mimeType: 'image/png',
        ),
        snapshot: const SnapshotCapture(
          data: <String, Object?>{'route': '/login'},
        ),
        logs: const LogsCapture(
          data: <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{
                'level': 'error',
                'message': 'Login button was not found.',
              },
            ],
          },
        ),
      );
      final Scenario scenario = Scenario(
        name: 'missing_button_failure_bundle',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            label: 'submit_login',
            action: TapAction(finder: Finder(byText: 'missing_button')),
          ),
          ScenarioStep(
            index: 2,
            action: CaptureAction(
              screenshot: true,
              snapshot: true,
              widgetTree: true,
              logs: true,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps, hasLength(1));
      expect(report.steps.single.status, StepStatus.failed);
      expect(report.steps.single.failureReason, 'Finder matched no widgets.');
      expect(
        report.steps.single.artifacts.map(
          (ArtifactReport artifact) => artifact.type,
        ),
        <ArtifactType>[
          ArtifactType.screenshot,
          ArtifactType.snapshot,
          ArtifactType.logs,
        ],
      );
      expect(
        report.steps.single.artifacts.every(
          (ArtifactReport artifact) =>
              artifact.purpose == ArtifactPurpose.failure,
        ),
        isTrue,
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.collectLogs,
          RuntimeOperation.dispose,
        ],
      );

      final ArtifactReport screenshotArtifact = report.steps.single.artifacts
          .singleWhere(
            (ArtifactReport artifact) =>
                artifact.type == ArtifactType.screenshot,
          );
      expect(
        File(
          '${report.runDirectoryPath}/${screenshotArtifact.path}',
        ).readAsBytesSync(),
        screenshotBytes,
      );

      final String reportJson = _runReportFile(report).readAsStringSync();
      expect(reportJson, contains('"purpose": "failure"'));
      expect(reportJson, isNot(contains('"type": "widgetTree"')));
    });
  });

  test(
    'records diagnostic failure reason when automatic failure capture fails',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory outputDirectory = Directory(
          'failure_diagnostic_failure_output',
        );
        final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
          snapshot: const SnapshotCapture(
            data: <String, Object?>{'route': '/login'},
          ),
          logs: const LogsCapture(
            data: <String, Object?>{'entries': <Object?>[]},
          ),
          failures: <RuntimeOperation, RuntimeOperationException>{
            RuntimeOperation.captureScreenshot: const RuntimeOperationException(
              operation: RuntimeOperation.captureScreenshot,
              message: 'Screenshot RPC failed.',
            ),
          },
        );
        final Scenario scenario = Scenario(
          name: 'partial_failure_bundle',
          steps: const <ScenarioStep>[
            ScenarioStep(
              index: 1,
              label: 'submit_login',
              action: TapAction(finder: Finder(byText: 'missing_button')),
            ),
          ],
        );

        final ScenarioRunReport report = await ScenarioRunner(
          adapter: adapter,
          outputDirectory: outputDirectory,
        ).run(scenario);

        expect(report.status, ScenarioRunStatus.failed);
        expect(report.steps.single.failureReason, 'Finder matched no widgets.');
        expect(
          report.steps.single.diagnosticFailureReason,
          'Screenshot RPC failed.',
        );
        expect(
          report.steps.single.artifacts.map(
            (ArtifactReport artifact) => artifact.type,
          ),
          <ArtifactType>[ArtifactType.snapshot, ArtifactType.logs],
        );

        final String reportJson = _runReportFile(report).readAsStringSync();
        expect(
          reportJson,
          contains('"failureReason": "Finder matched no widgets."'),
        );
        expect(
          reportJson,
          contains('"diagnosticFailureReason": "Screenshot RPC failed."'),
        );
      });
    },
  );

  test('fails a Finder action when multiple widgets match', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('multiple_match_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[
            FinderMatch(id: 'first-match', debugLabel: 'TextButton("Log in")'),
            FinderMatch(id: 'second-match', debugLabel: 'Text("Log in")'),
          ],
        },
      );
      final Scenario scenario = Scenario(
        name: 'ambiguous_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'login_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.status, StepStatus.failed);
      expect(
        report.steps.single.failureReason,
        'Finder matched multiple widgets.',
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.collectLogs,
          RuntimeOperation.dispose,
        ],
      );
    });
  });

  test('preserves Step failure report when dispose also fails', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory(
        'dispose_after_failure_output',
      );
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.dispose: const RuntimeOperationException(
            operation: RuntimeOperation.dispose,
            message: 'Dispose failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'missing_button',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'missing_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.steps.single.failureReason, 'Finder matched no widgets.');

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('Finder matched no widgets'),
      );
    });
  });

  test('records dispose failure when cleanup is the only failure', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('dispose_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[FinderMatch(id: 'tap-match')],
        },
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.dispose: const RuntimeOperationException(
            operation: RuntimeOperation.dispose,
            message: 'Dispose failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'dispose_failure',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'login_button')),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Dispose failed.');
      expect(report.steps.single.status, StepStatus.passed);

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason": "Dispose failed."'),
      );
    });
  });

  test('records runtime operation failures as failed Steps', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('runtime_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        finderResults: <String, List<FinderMatch>>{
          'login_button': const <FinderMatch>[FinderMatch(id: 'tap-match')],
        },
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.performTap: const RuntimeOperationException(
            operation: RuntimeOperation.performTap,
            message: 'Tap RPC failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'tap_failure',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'login_button')),
          ),
          ScenarioStep(
            index: 2,
            action: CaptureAction(
              screenshot: true,
              snapshot: true,
              widgetTree: false,
              logs: true,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Tap RPC failed.');
      expect(report.steps.single.status, StepStatus.failed);
      expect(report.steps.single.failureReason, 'Tap RPC failed.');
      expect(
        report.steps.single.artifacts.map(
          (ArtifactReport artifact) => artifact.purpose,
        ),
        <ArtifactPurpose>[
          ArtifactPurpose.failure,
          ArtifactPurpose.failure,
          ArtifactPurpose.failure,
        ],
      );
      expect(
        adapter.events.map((FakeRuntimeEvent event) => event.operation),
        <RuntimeOperation>[
          RuntimeOperation.initialize,
          RuntimeOperation.resolveFinder,
          RuntimeOperation.captureScreenshot,
          RuntimeOperation.captureSnapshot,
          RuntimeOperation.collectLogs,
          RuntimeOperation.dispose,
        ],
      );

      final File reportFile = _runReportFile(report);
      expect(reportFile.readAsStringSync(), contains('Tap RPC failed.'));
    });
  });

  test('records initialize failure as a run-level failure', () async {
    await FileTestkit.runZoned(() async {
      final Directory outputDirectory = Directory('initialize_failure_output');
      final FakeRuntimeAdapter adapter = FakeRuntimeAdapter(
        failures: <RuntimeOperation, RuntimeOperationException>{
          RuntimeOperation.initialize: const RuntimeOperationException(
            operation: RuntimeOperation.initialize,
            message: 'Initialize failed.',
          ),
        },
      );
      final Scenario scenario = Scenario(
        name: 'initialize_failure',
        steps: const <ScenarioStep>[
          ScenarioStep(
            index: 1,
            action: CaptureAction(
              screenshot: true,
              snapshot: true,
              widgetTree: false,
              logs: true,
            ),
          ),
        ],
      );

      final ScenarioRunReport report = await ScenarioRunner(
        adapter: adapter,
        outputDirectory: outputDirectory,
      ).run(scenario);

      expect(report.status, ScenarioRunStatus.failed);
      expect(report.failureReason, 'Initialize failed.');
      expect(report.steps, isEmpty);

      final File reportFile = _runReportFile(report);
      expect(
        reportFile.readAsStringSync(),
        contains('"failureReason": "Initialize failed."'),
      );
    });
  });
}

/// Return the report file written for a completed Scenario run.
File _runReportFile(ScenarioRunReport report) {
  return File('${report.runDirectoryPath}/run_report.json');
}
