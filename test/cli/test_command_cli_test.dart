import 'dart:async';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

import '../support/test_command_fakes.dart';

/// Verifies `flutter_pilot test` CLI mode selection and output wiring.
void main() {
  test('test command delegates no-argument Project Run from pilot', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');
      final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
        report: passedProjectRunResult(),
      );

      final int exitCode = await FlutterPilotCli(
        projectRunExecutor: projectExecutor,
      ).run(<String>['test']);

      expect(exitCode, 0);
      expect(projectExecutor.options.discoveryRootPath, 'pilot');
      expect(
        projectExecutor.options.scenarios.map(
          (ProjectScenarioFile file) => file.relativePath,
        ),
        <String>['login.yaml'],
      );
    });
  });

  test(
    'test command delegates directory input as a focused Project Run',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('flows').createSync();
        File('flows/checkout.yaml').writeAsStringSync('''
scenario:
  name: checkout
steps:
  - capture: {}
''');
        final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
          report: passedProjectRunResult(),
        );

        final int exitCode = await FlutterPilotCli(
          projectRunExecutor: projectExecutor,
        ).run(<String>['test', 'flows']);

        expect(exitCode, 0);
        expect(projectExecutor.options.discoveryRootPath, 'flows');
        expect(
          projectExecutor.options.scenarios.map(
            (ProjectScenarioFile file) => file.relativePath,
          ),
          <String>['checkout.yaml'],
        );
      });
    },
  );

  test('test command keeps file input in single Entry Scenario mode', () async {
    await FileTestkit.runZoned(() async {
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
steps:
  - capture: {}
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: passedScenarioRunReport(),
      );
      final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
        report: passedProjectRunResult(),
      );

      final int exitCode = await FlutterPilotCli(
        testCommandExecutor: executor,
        projectRunExecutor: projectExecutor,
      ).run(<String>['test', scenarioFile.path]);

      expect(exitCode, 0);
      expect(executor.options.scenario.name, 'scenario');
      expect(projectExecutor.ran, isFalse);
    });
  });

  test('test command rejects multiple positional inputs', () async {
    await FileTestkit.runZoned(() async {
      File('a.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');
      File('b.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        'a.yaml',
        'b.yaml',
      ]);

      expect(exitCode, 64);
    });
  });

  test('test command does not introduce glob-style inputs', () async {
    await FileTestkit.runZoned(() async {
      File('scenario.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '*.yaml',
      ]);

      expect(exitCode, 64);
    });
  });

  test(
    'test command reports empty Project Run discovery before launch',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/library.yaml').writeAsStringSync('''
steps:
  - capture: {}
''');
        final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
          report: passedProjectRunResult(),
        );

        final int exitCode = await FlutterPilotCli(
          projectRunExecutor: projectExecutor,
        ).run(<String>['test']);

        expect(exitCode, 64);
        expect(projectExecutor.ran, isFalse);
      });
    },
  );

  test('test command rejects --until in Project Run mode', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '--until',
        '1',
      ]);

      expect(exitCode, 64);
    });
  });

  test('test command rejects --print in Project Run mode', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');

      final int exitCode = await FlutterPilotCli().run(<String>[
        'test',
        '--print',
        'widget-tree',
      ]);

      expect(exitCode, 64);
    });
  });

  test('test command delegates validated options to the executor', () async {
    await FileTestkit.runZoned(() async {
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
scenario:
  name: delegated
steps:
  - label: submit
    tap:
      byText: Continue
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: passedScenarioRunReport(),
      );

      final int exitCode = await FlutterPilotCli(testCommandExecutor: executor)
          .run(<String>[
            'test',
            scenarioFile.path,
            '--device',
            'Pixel',
            '--flavor',
            'staging',
            '--target',
            'lib/main_staging.dart',
            '--until',
            'submit',
            '--print',
            'widget-tree',
            '--json',
          ]);

      expect(exitCode, 0);
      expect(executor.options.scenario.name, 'delegated');
      expect(executor.options.device, 'Pixel');
      expect(executor.options.flavor, 'staging');
      expect(executor.options.target, 'lib/main_staging.dart');
      expect(executor.options.stopPoint, isA<StepLabelStopPoint>());
      expect(executor.options.printDiagnostics, <PrintDiagnostic>{
        PrintDiagnostic.widgetTree,
      });
      expect(executor.options.jsonOutput, isTrue);
      expect(executor.onProgress, isNull);
    });
  });

  test('test command rejects empty Project Run launch options', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: login
steps:
  - capture: {}
''');
      final List<List<String>> optionCases = <List<String>>[
        <String>['--device', ' '],
        <String>['--flavor', ' '],
        <String>['--target', ' '],
      ];

      for (final List<String> optionCase in optionCases) {
        final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
          report: passedProjectRunResult(),
        );

        final int exitCode = await FlutterPilotCli(
          projectRunExecutor: projectExecutor,
        ).run(<String>['test', ...optionCase]);

        expect(exitCode, 64);
        expect(projectExecutor.ran, isFalse);
      }
    });
  });

  test(
    'test command enables Step progress for human-readable output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: progress
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: passedScenarioRunReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]);

        expect(exitCode, 0);
        expect(executor.onProgress, isNotNull);
      });
    },
  );

  test('test command enables Step progress for Project Run output', () async {
    await FileTestkit.runZoned(() async {
      Directory('pilot').createSync();
      File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_step_progress
steps:
  - capture: {}
''');
      final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
        report: passedProjectRunResult(),
      );

      final int exitCode = await FlutterPilotCli(
        projectRunExecutor: projectExecutor,
      ).run(<String>['test']);

      expect(exitCode, 0);
      expect(projectExecutor.onProgress, isNotNull);
    });
  });

  test(
    'test command enables Target App Launch Progress for human-readable output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: passedScenarioRunReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]);

        expect(exitCode, 0);
        expect(executor.onLaunchProgress, isNotNull);
      });
    },
  );

  test(
    'test command enables Target App Launch Progress for Project Run output',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_launch_progress
steps:
  - capture: {}
''');
        final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
          report: passedProjectRunResult(),
        );

        final int exitCode = await FlutterPilotCli(
          projectRunExecutor: projectExecutor,
        ).run(<String>['test']);

        expect(exitCode, 0);
        expect(projectExecutor.onLaunchProgress, isNotNull);
        expect(projectExecutor.launchHeartbeatEnabled, isTrue);
      });
    },
  );

  test(
    'test command keeps Project Run --json scoped to progress suppression',
    () async {
      await FileTestkit.runZoned(() async {
        Directory('pilot').createSync();
        File('pilot/login.yaml').writeAsStringSync('''
scenario:
  name: project_json
steps:
  - capture: {}
''');
        final FakeProjectRunExecutor projectExecutor = FakeProjectRunExecutor(
          report: passedProjectRunResult(),
        );

        final int exitCode = await FlutterPilotCli(
          projectRunExecutor: projectExecutor,
        ).run(<String>['test', '--json']);

        expect(exitCode, 0);
        expect(projectExecutor.options.jsonOutput, isTrue);
        expect(projectExecutor.onProgress, isNull);
        expect(projectExecutor.onLaunchProgress, isNull);
      });
    },
  );

  test(
    'test command suppresses Target App Launch Progress for JSON output',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress_json
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: passedScenarioRunReport(),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path, '--json']);

        expect(exitCode, 0);
        expect(executor.onLaunchProgress, isNull);
      });
    },
  );

  test(
    'test command suppresses JSON launch failure progress but preserves failure',
    () async {
      await FileTestkit.runZoned(() async {
        final File scenarioFile = File('scenario.yaml')
          ..writeAsStringSync('''
scenario:
  name: launch_progress_failure_json
steps:
  - tap:
      byText: Continue
''');
        final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
          report: passedScenarioRunReport(),
          exception: const TestCommandException(
            message: 'Flutter exited before Runtime Target URI was available.',
            exitCode: 1,
          ),
        );

        final int exitCode = await FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path, '--json']);

        expect(exitCode, 1);
        expect(executor.onLaunchProgress, isNull);
      });
    },
  );

  test('test command does not duplicate rendered launch failure', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_failure.log');
      final IOSink sink = output.openWrite();
      final File scenarioFile = File('scenario.yaml')
        ..writeAsStringSync('''
scenario:
  name: launch_failure
steps:
  - tap:
      byText: Continue
''');
      final FakeTestCommandExecutor executor = FakeTestCommandExecutor(
        report: passedScenarioRunReport(),
        exception: const TestCommandException(
          message: 'Flutter exited before Runtime Target URI was available.',
          exitCode: 1,
          alreadyRendered: true,
        ),
      );

      final int exitCode = await runZoned(
        () => FlutterPilotCli(
          testCommandExecutor: executor,
        ).run(<String>['test', scenarioFile.path]),
        zoneValues: <Object?, Object?>{#stderr: sink},
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(exitCode, 1);
      expect(rendered, isNot(contains('Runtime Target URI')));
    });
  });
}
