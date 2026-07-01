import 'dart:async';
import 'dart:convert';

import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies Target App launcher behavior without starting a real Flutter app.
///
/// The tests use fake process streams so launch command construction, machine
/// event parsing, stderr buffering, and cleanup can be exercised deterministically.
void main() {
  group('TargetAppLauncher', () {
    test(
      'builds flutter run machine commands with supported launch options',
      () {
        final TargetAppLaunchCommand command = TargetAppLaunchCommand(
          deviceId: 'pixel-8',
          flavor: 'staging',
          target: 'lib/main_staging.dart',
        );

        expect(command.executable, 'flutter');
        expect(command.arguments, <String>[
          'run',
          '--machine',
          '--device-id',
          'pixel-8',
          '--flavor',
          'staging',
          '--target',
          'lib/main_staging.dart',
        ]);
      },
    );

    test('extracts runtime target URI and hides raw machine stdout', () async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final TargetAppLauncher launcher = TargetAppLauncher(starter: starter);
      final Future<TargetAppLaunch> launchFuture = launcher.launch(
        const TargetAppLaunchCommand(),
      );

      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );

      final TargetAppLaunch launch = await launchFuture;

      expect(
        launch.runtimeTargetUri.toString(),
        'ws://127.0.0.1:1234/token=/ws',
      );
      expect(starter.startedArguments, <String>['run', '--machine']);
      expect(starter.forwardedStdout, isEmpty);
    });

    test(
      'fails with last forty stderr lines when Flutter exits before URI',
      () async {
        final FakeTargetAppProcess process = FakeTargetAppProcess();
        final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
          process,
        );
        final TargetAppLauncher launcher = TargetAppLauncher(starter: starter);
        final Future<TargetAppLaunch> launchFuture = launcher.launch(
          const TargetAppLaunchCommand(),
        );

        for (var index = 1; index <= 45; index++) {
          process.emitStderr('stderr line $index');
        }
        process.exit(1);

        await expectLater(
          launchFuture,
          throwsA(
            isA<TargetAppLaunchException>()
                .having(
                  (TargetAppLaunchException error) => error.message,
                  'message',
                  contains(
                    'Flutter exited before Runtime Target URI was available.',
                  ),
                )
                .having(
                  (TargetAppLaunchException error) => error.stderrLines,
                  'stderrLines',
                  allOf(
                    hasLength(40),
                    isNot(contains('stderr line 5')),
                    contains('stderr line 6'),
                    contains('stderr line 45'),
                  ),
                ),
          ),
        );
      },
    );

    test('cleanup sends Flutter quit before falling back to kill', () async {
      final FakeTargetAppProcess process = FakeTargetAppProcess();
      final FakeTargetAppProcessStarter starter = FakeTargetAppProcessStarter(
        process,
      );
      final TargetAppLauncher launcher = TargetAppLauncher(starter: starter);
      final Future<TargetAppLaunch> launchFuture = launcher.launch(
        const TargetAppLaunchCommand(),
      );
      process.emitStdout(
        jsonEncode(<String, Object?>{
          'event': 'app.debugPort',
          'params': <String, Object?>{'wsUri': 'ws://127.0.0.1:1234/token=/ws'},
        }),
      );
      final TargetAppLaunch launch = await launchFuture;

      await launch.cleanup(gracePeriod: Duration.zero);

      expect(process.stdinWrites, <String>['q\n']);
      expect(process.killCount, 1);
    });
  });
}

class FakeTargetAppProcessStarter implements TargetAppProcessStarter {
  FakeTargetAppProcessStarter(this.process);

  final FakeTargetAppProcess process;
  List<String> startedArguments = const <String>[];
  final List<String> forwardedStdout = <String>[];

  @override
  Future<TargetAppProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startedArguments = arguments;
    return process;
  }
}

class FakeTargetAppProcess implements TargetAppProcess {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();
  final List<String> stdinWrites = <String>[];
  int killCount = 0;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  void emitStdout(String line) {
    _stdoutController.add(utf8.encode('$line\n'));
  }

  void emitStderr(String line) {
    _stderrController.add(utf8.encode('$line\n'));
  }

  void exit(int exitCode) {
    _stdoutController.close();
    _stderrController.close();
    _exitCodeCompleter.complete(exitCode);
  }

  @override
  void writeStdin(String text) {
    stdinWrites.add(text);
  }

  @override
  bool kill() {
    killCount++;
    return true;
  }
}
