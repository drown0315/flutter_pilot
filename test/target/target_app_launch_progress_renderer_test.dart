import 'dart:async';
import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies Target App Launch Progress rendering independently of execution.
void main() {
  test('plain launch progress renders before Step progress', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('progress.log');
      final IOSink sink = output.openWrite();
      final TargetAppLaunchProgressRenderer launchRenderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            clock: () => DateTime.utc(2026, 6, 30, 12, 0, 38),
          );
      final StepProgressRenderer stepRenderer = StepProgressRenderer(
        sink: sink,
      );

      launchRenderer.render(
        TargetAppLaunchStartedEvent(startedAt: DateTime.utc(2026, 6, 30, 12)),
      );
      launchRenderer.render(
        TargetAppLaunchSucceededEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          finishedAt: DateTime.utc(2026, 6, 30, 12, 0, 38),
        ),
      );
      stepRenderer.render(
        const StepStartedEvent(
          scenarioName: 'launch_progress',
          totalSteps: 1,
          step: ScenarioStep(
            index: 1,
            action: TapAction(finder: Finder(byText: 'Continue')),
          ),
          action: 'tap',
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('> Target App Launch'));
      expect(rendered, contains('Launching Target App Package... elapsed 38s'));
      expect(rendered, contains('Target App launched in 38s'));
      expect(rendered, contains('Scenario: launch_progress (1 steps)'));
      expect(
        rendered.indexOf('Target App launched in 38s'),
        lessThan(rendered.indexOf('Scenario: launch_progress (1 steps)')),
      );
    });
  });

  test(
    'plain launch progress shows explicit Target Device selection',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              targetDevice: TargetDevice(
                id: 'pixel-8',
                name: 'Pixel 8',
                targetPlatform: 'android-arm64',
                emulator: true,
                sdk: 'Android 35',
              ),
              selectionReason: TargetDeviceSelectionReason.explicit(
                selector: 'Pixel',
              ),
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered,
          contains(
            'Target Device: pixel-8 (Pixel 8, android-arm64, Android 35)',
          ),
        );
        expect(rendered, contains('Selection: --device Pixel'));
      });
    },
  );

  test(
    'plain launch progress shows recording auto-selected Target Device',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              targetDevice: TargetDevice(
                id: 'pixel-8',
                name: 'Pixel 8',
                targetPlatform: 'android-arm64',
                emulator: true,
                sdk: 'Android 35',
              ),
              selectionReason:
                  TargetDeviceSelectionReason.autoSelectedForRecording(),
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered,
          contains(
            'Target Device: pixel-8 (Pixel 8, android-arm64, Android 35)',
          ),
        );
        expect(rendered, contains('Selection: auto-selected for recording'));
      });
    },
  );

  test(
    'plain launch progress shows Flutter default without placeholders',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(startedAt: DateTime.utc(2026, 6, 30, 12)),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('Target Device: Flutter default'));
        expect(rendered, isNot(contains('Selection:')));
        expect(rendered, isNot(contains('Flavor:')));
        expect(rendered, isNot(contains('Entrypoint:')));
      });
    },
  );

  test(
    'plain launch progress shows flavor and entrypoint when provided',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('progress.log');
        final IOSink sink = output.openWrite();
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink);

        renderer.render(
          TargetAppLaunchStartedEvent(
            startedAt: DateTime.utc(2026, 6, 30, 12),
            choices: const TargetAppLaunchChoices(
              flavor: 'staging',
              target: 'lib/main_staging.dart',
            ),
          ),
        );
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(rendered, contains('Flavor: staging'));
        expect(rendered, contains('Entrypoint: lib/main_staging.dart'));
      });
    },
  );

  test('plain launch progress shows bounded failure details', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('progress.log');
      final IOSink sink = output.openWrite();
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(sink: sink);

      renderer.render(
        TargetAppLaunchFailedEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          failedAt: DateTime.utc(2026, 6, 30, 12, 0, 4),
          message: 'Flutter exited before Runtime Target URI was available.',
          stderrLines: const <String>['stderr line 6', 'stderr line 45'],
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('Target App launch failed after 4s'));
      expect(
        rendered,
        contains('Flutter exited before Runtime Target URI was available.'),
      );
      expect(rendered, contains('Flutter stderr tail:'));
      expect(rendered, contains('stderr line 6'));
      expect(rendered, contains('stderr line 45'));
    });
  });

  test('redraws the interactive launch panel in place', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_refresh.log');
      final IOSink sink = output.openWrite();
      DateTime now = DateTime.utc(2026, 6, 30, 12, 0, 1);
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            interactive: true,
            clock: () => now,
          );
      final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
        startedAt: DateTime.utc(2026, 6, 30, 12),
        choices: const TargetAppLaunchChoices(flavor: 'staging'),
      );

      renderer.render(started);
      now = DateTime.utc(2026, 6, 30, 12, 0, 2);
      renderer.render(started);
      renderer.render(
        TargetAppLaunchSucceededEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
          finishedAt: DateTime.utc(2026, 6, 30, 12, 0, 3),
          choices: started.choices,
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('\u001b['));
      final String plain = TerminalStyle.stripAnsi(rendered);
      expect(plain, contains('> Target App Launch'));
      expect(plain, contains('⏳ Waiting for Runtime Target... elapsed 2s'));
      expect(plain, contains('Flavor: staging'));
      expect(plain, contains('Target App launched in 3s'));
      expect(plain, isNot(contains('%')));
    });
  });

  test('interactive launch heartbeat refreshes elapsed time', () async {
    await FileTestkit.runZoned(() async {
      final File output = File('launch_heartbeat_refresh.log');
      final IOSink sink = output.openWrite();
      DateTime now = DateTime.utc(2026, 6, 30, 12, 0, 1);
      final TargetAppLaunchProgressRenderer renderer =
          TargetAppLaunchProgressRenderer(
            sink: sink,
            interactive: true,
            clock: () => now,
          );
      final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
        startedAt: DateTime.utc(2026, 6, 30, 12),
      );

      renderer.render(started);
      now = DateTime.utc(2026, 6, 30, 12, 0, 11);
      renderer.render(
        TargetAppLaunchHeartbeatEvent(
          startedAt: started.startedAt,
          heartbeatAt: now,
          choices: started.choices,
        ),
      );
      await sink.close();

      final String rendered = output.readAsStringSync();
      expect(rendered, contains('\u001b['));
      final String plain = TerminalStyle.stripAnsi(rendered);
      expect(plain, contains('⏳ Waiting for Runtime Target... elapsed 11s'));
    });
  });

  test(
    'non-interactive launch heartbeat prints every ten seconds until stopped',
    () async {
      await FileTestkit.runZoned(() async {
        final File output = File('launch_heartbeat.log');
        final IOSink sink = output.openWrite();
        DateTime now = DateTime.utc(2026, 6, 30, 12);
        final TargetAppLaunchProgressRenderer renderer =
            TargetAppLaunchProgressRenderer(sink: sink, clock: () => now);
        final StreamController<void> ticks = StreamController<void>();
        final TargetAppLaunchHeartbeat heartbeat = TargetAppLaunchHeartbeat(
          ticks: ticks.stream,
          onProgress: renderer.render,
          clock: () => now,
        );
        final TargetAppLaunchStartedEvent started = TargetAppLaunchStartedEvent(
          startedAt: DateTime.utc(2026, 6, 30, 12),
        );

        heartbeat.start(started);
        now = DateTime.utc(2026, 6, 30, 12, 0, 9);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        now = DateTime.utc(2026, 6, 30, 12, 0, 10);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await heartbeat.stop();
        now = DateTime.utc(2026, 6, 30, 12, 0, 20);
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        await ticks.close();
        await sink.close();

        final String rendered = output.readAsStringSync();
        expect(
          rendered
              .split('\n')
              .where(
                (String line) =>
                    line.contains('Launching Target App Package... elapsed'),
              )
              .toList(),
          <String>['Launching Target App Package... elapsed 10s'],
        );
      });
    },
  );
}
