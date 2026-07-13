import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:screen_recorder/screen_recorder.dart';
import 'package:test/test.dart';

/// Verifies physical iOS recording through the public API and fake commands.
void main() {
  group('Physical iOS ScreenRecorder', () {
    test('lists physical iOS Recording Devices from helper output', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addHelperList(
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
id\tname\tmodel\tmanufacturer
ios-device-1\tDrown iPhone\tiOS Device\tApple Inc.
ios-device-2\tOffice iPhone\tiOS Device\tApple Inc.
''',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, <RecordingDevice>[
        const RecordingDevice(
          id: 'ios-device-1',
          name: 'Drown iPhone',
          platform: RecordingDevicePlatform.iosPhysical,
        ),
        const RecordingDevice(
          id: 'ios-device-2',
          name: 'Office iPhone',
          platform: RecordingDevicePlatform.iosPhysical,
        ),
      ]);
    });

    test('excludes xctrace-only devices from Recording Devices', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addHelperList(
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
id\tname\tmodel\tmanufacturer
avfoundation-id\t钟惠彬的 iPhone\tiOS Device\tApple Inc.
''',
            stderr: '',
          ),
        )
        ..addXctraceList(
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
== Devices ==
drown的MacBook Pro (413457E0-CF99-52D4-A082-30349AC884F5)
钟惠彬的 iPhone (15.8.8) (269bfd1ccaa634d5f2250efe6a22016b18fd16da)

== Devices Offline ==
Unknown (6FC56E18-825D-5F44-909F-43C55FBB2A12)

== Simulators ==
iPhone 17 Simulator (26.4) (58CC29EF-4758-4E4E-A79A-398E4A26C91F)
''',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );

      final List<RecordingDevice> devices = await recorder.listDevices();

      expect(devices, const <RecordingDevice>[
        RecordingDevice(
          id: 'avfoundation-id',
          name: '钟惠彬的 iPhone',
          platform: RecordingDevicePlatform.iosPhysical,
        ),
      ]);
    });

    test(
      'resolves physical iOS devices by id, name, and name prefix',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addSwiftBuild()
          ..addPhysicalDeviceList(<String, String>{
            'ios-device-1': 'Drown iPhone',
          });
        final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_physical_ios_test_')
            .path;

        final RecordingSession byId = await recorder.startRecord(
          deviceSelector: 'ios-device-1',
          outputDirectory: outputDirectory,
          outputName: 'by_id',
        );
        await recorder.discardRecord(byId);

        final RecordingSession byName = await recorder.startRecord(
          deviceSelector: 'Drown iPhone',
          outputDirectory: outputDirectory,
          outputName: 'by_name',
        );
        await recorder.discardRecord(byName);

        final RecordingSession byPrefix = await recorder.startRecord(
          deviceSelector: 'dro',
          outputDirectory: outputDirectory,
          outputName: 'by_prefix',
        );
        await recorder.discardRecord(byPrefix);

        expect(byId.device.id, 'ios-device-1');
        expect(byName.device.id, 'ios-device-1');
        expect(byPrefix.device.id, 'ios-device-1');
        expect(
          commandRunner.startedCommands,
          contains(
            equals(<String>[
              commandRunner.helperPath,
              'serve',
              '--device-id',
              'ios-device-1',
            ]),
          ),
        );
        expect(byId.expectedOutputPath, endsWith('by_id.mov'));
      },
    );

    test(
      'stops physical iOS helper and returns a finalized mov result',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addSwiftBuild()
          ..addPhysicalDeviceList(<String, String>{
            'ios-device-1': 'Drown iPhone',
          });
        final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
          commandRunner: commandRunner,
        );
        final String outputDirectory = Directory.systemTemp
            .createTempSync('screen_recorder_physical_ios_test_')
            .path;

        final RecordingSession session = await recorder.startRecord(
          deviceSelector: 'Drown iPhone',
          outputDirectory: outputDirectory,
          outputName: 'physical_recording',
        );
        commandRunner.completeProcessWithFile(
          outputPath: session.expectedOutputPath,
          bytes: <int>[5, 4, 3, 2],
        );

        final RecordingResult result = await recorder.stopRecord(session);

        expect(result.outputPath, endsWith('physical_recording.mov'));
        expect(result.mimeType, 'video/quicktime');
        expect(File(result.outputPath).readAsBytesSync(), <int>[5, 4, 3, 2]);
        expect(result.fileSizeBytes, 4);
      },
    );

    test(
      'reports missing Swift toolchain with missing-dependency code and raw output',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addRun(
            <String>['swiftc'],
            const ScreenRecorderCommandResult(
              exitCode: 1,
              stdout: '',
              stderr: 'xcrun: error: toolchain not found',
            ),
          );
        final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
          commandRunner: commandRunner,
        );

        await expectLater(
          recorder.listDevices(),
          throwsA(
            isA<ScreenRecorderException>()
                .having(
                  (ScreenRecorderException exception) => exception.code,
                  'code',
                  ScreenRecorderErrorCode.missingDependency,
                )
                .having(
                  (ScreenRecorderException exception) => exception.rawOutput,
                  'rawOutput',
                  contains('toolchain not found'),
                ),
          ),
        );
      },
    );

    test(
      'reports helper list failures with permission-denied code and raw output',
      () async {
        final _FakeCommandRunner commandRunner = _FakeCommandRunner()
          ..addSwiftBuild()
          ..addHelperList(
            const ScreenRecorderCommandResult(
              exitCode: 3,
              stdout: '',
              stderr: 'camera permission denied',
            ),
          );
        final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
          commandRunner: commandRunner,
        );

        await expectLater(
          recorder.listDevices(),
          throwsA(
            isA<ScreenRecorderException>()
                .having(
                  (ScreenRecorderException exception) => exception.code,
                  'code',
                  ScreenRecorderErrorCode.permissionDenied,
                )
                .having(
                  (ScreenRecorderException exception) => exception.rawOutput,
                  'rawOutput',
                  contains('camera permission denied'),
                ),
          ),
        );
      },
    );

    test('reports helper immediate exit as a start failure', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'avfoundation-id': 'Drown iPhone',
        })
        ..completeNextProcessImmediately(
          exitCode: 4,
          stderr: 'No physical iOS capture device matched id avfoundation-id.',
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      await expectLater(
        recorder.startRecord(
          deviceSelector: 'Drown iPhone',
          outputDirectory: outputDirectory,
          outputName: 'immediate_exit',
        ),
        throwsA(
          isA<ScreenRecorderException>()
              .having(
                (ScreenRecorderException exception) => exception.code,
                'code',
                ScreenRecorderErrorCode.startFailed,
              )
              .having(
                (ScreenRecorderException exception) => exception.rawOutput,
                'rawOutput',
                allOf(
                  contains('helper exitCode: 4'),
                  contains('No physical iOS capture device matched'),
                ),
              ),
        ),
      );
    });

    test('cleans up helper when prepared capture readiness fails', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addHelperList(
          const ScreenRecorderCommandResult(
            exitCode: 0,
            stdout: '''
id\tname\tmodel\tmanufacturer
ios-device-1\tDrown iPhone\tiOS Device\tApple Inc.
''',
            stderr: '',
          ),
        );
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );

      final Future<PreparedCapture> prepare = recorder.prepare(
        deviceSelector: 'ios-device-1',
      );
      await Future<void>.delayed(Duration.zero);
      commandRunner.emitStdoutLine('{"event":"notReady"}');

      await expectLater(
        prepare,
        throwsA(
          isA<ScreenRecorderException>().having(
            (ScreenRecorderException exception) => exception.code,
            'code',
            ScreenRecorderErrorCode.startFailed,
          ),
        ),
      );
      expect(commandRunner.writtenOperations, <String>['shutdown']);
      expect(commandRunner.lastProcess?.hasExited, isTrue);
    });

    test('process boundary exposes streamed stdout and stdin lines', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner();
      final ScreenRecorderProcess process = await commandRunner.start(
        commandRunner.helperPath,
        <String>['serve', '--device-id', 'ios-device-1'],
      );
      final List<String> stdoutLines = <String>[];
      final StreamSubscription<String> subscription =
          process.stdoutLines.listen(stdoutLines.add);

      commandRunner.emitStdoutLine('READY');
      process.writeLine('START /tmp/ios-recording.mov');
      await process.closeStdin();

      expect(commandRunner.writtenLines, <String>[
        'START /tmp/ios-recording.mov',
      ]);
      expect(stdoutLines, <String>['READY']);

      await subscription.cancel();
    });

    test('prepared capture reuses one serve helper across segments', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        })
        ..defaultServeOutputBytes = <int>[5, 4, 3, 2];
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      final PreparedCapture capture = await recorder.prepare(
        deviceSelector: 'Drown iPhone',
      );
      final RecordingSession firstSession = await recorder.startRecord(
        preparedCapture: capture,
        outputDirectory: outputDirectory,
        outputName: 'first_segment',
        overwrite: true,
      );
      final RecordingResult firstResult = await recorder.stopRecord(
        firstSession,
      );
      final RecordingSession secondSession = await recorder.startRecord(
        preparedCapture: capture,
        outputDirectory: outputDirectory,
        outputName: 'second_segment',
        overwrite: true,
      );
      final RecordingResult secondResult = await recorder.stopRecord(
        secondSession,
      );
      await recorder.dispose(capture);

      expect(firstResult.outputPath, endsWith('first_segment.mov'));
      expect(secondResult.outputPath, endsWith('second_segment.mov'));
      expect(commandRunner.startedCommands, <List<String>>[
        <String>[
          commandRunner.helperPath,
          'serve',
          '--device-id',
          'ios-device-1',
        ],
      ]);
      expect(commandRunner.writtenOperations, <String>[
        'start',
        'stop',
        'start',
        'stop',
        'shutdown',
      ]);
      expect(commandRunner.lastProcess?.hasExited, isTrue);
    });

    test('prepared capture rejects segment start after disposal', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        })
        ..defaultServeOutputBytes = <int>[5, 4, 3, 2];
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;
      final PreparedCapture capture = await recorder.prepare(
        deviceSelector: 'ios-device-1',
      );

      await recorder.dispose(capture);

      await expectLater(
        recorder.startRecord(
          preparedCapture: capture,
          outputDirectory: outputDirectory,
          outputName: 'after_dispose',
          overwrite: true,
        ),
        throwsA(isA<ScreenRecorderException>()),
      );
    });

    test('prepared capture rejects concurrent segments', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        })
        ..defaultServeOutputBytes = <int>[5, 4, 3, 2];
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;
      final PreparedCapture capture = await recorder.prepare(
        deviceSelector: 'ios-device-1',
      );

      final RecordingSession activeSession = await recorder.startRecord(
        preparedCapture: capture,
        outputDirectory: outputDirectory,
        outputName: 'active',
        overwrite: true,
      );

      await expectLater(
        recorder.startRecord(
          preparedCapture: capture,
          outputDirectory: outputDirectory,
          outputName: 'concurrent',
          overwrite: true,
        ),
        throwsA(
          isA<ScreenRecorderException>().having(
            (ScreenRecorderException exception) => exception.code,
            'code',
            ScreenRecorderErrorCode.alreadyRecording,
          ),
        ),
      );
      await recorder.stopRecord(activeSession);
      await recorder.dispose(capture);
    });

    test('prepared capture disposal is idempotent', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        })
        ..autoServeProtocol = true;
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final PreparedCapture capture = await recorder.prepare(
        deviceSelector: 'ios-device-1',
      );

      await recorder.dispose(capture);
      await recorder.dispose(capture);

      expect(commandRunner.writtenOperations, <String>['shutdown']);
    });

    test('reports stop failure when physical iOS output is missing', () async {
      final _FakeCommandRunner commandRunner = _FakeCommandRunner()
        ..addSwiftBuild()
        ..addPhysicalDeviceList(<String, String>{
          'ios-device-1': 'Drown iPhone',
        });
      final ScreenRecorder recorder = ScreenRecorder.iosPhysical(
        commandRunner: commandRunner,
      );
      final String outputDirectory = Directory.systemTemp
          .createTempSync('screen_recorder_physical_ios_test_')
          .path;

      final RecordingSession session = await recorder.startRecord(
        deviceSelector: 'Drown iPhone',
        outputDirectory: outputDirectory,
        outputName: 'missing_output',
      );

      await expectLater(
        recorder.stopRecord(session),
        throwsA(
          isA<ScreenRecorderException>().having(
            (ScreenRecorderException exception) => exception.code,
            'code',
            ScreenRecorderErrorCode.stopFailed,
          ),
        ),
      );
    });
  });
}

class _FakeCommandRunner implements ScreenRecorderCommandRunner {
  final Map<String, ScreenRecorderCommandResult> _runResults =
      <String, ScreenRecorderCommandResult>{};
  final List<List<String>> runCommands = <List<String>>[];
  final List<List<String>> startedCommands = <List<String>>[];
  final String helperPath =
      '${Directory.systemTemp.path}${Platform.pathSeparator}screen_recorder_ios_physical_capture';
  _FakeScreenRecorderProcess? _lastProcess;
  bool autoServeProtocol = false;
  List<int>? defaultServeOutputBytes;
  int? _nextProcessExitCode;
  String _nextProcessStdout = '';
  String _nextProcessStderr = '';
  final List<String> writtenLines = <String>[];

  _FakeScreenRecorderProcess? get lastProcess => _lastProcess;

  List<String> get writtenOperations {
    return writtenLines.map((String line) {
      final Object? decoded = jsonDecode(line);
      if (decoded
          case <String, Object?>{'operation': final Object? operation}) {
        return operation.toString();
      }
      return line;
    }).toList();
  }

  void addSwiftBuild() {
    addRun(<String>[
      'swiftc',
    ], const ScreenRecorderCommandResult(exitCode: 0, stdout: '', stderr: ''));
  }

  void addRun(List<String> command, ScreenRecorderCommandResult result) {
    if (command.length == 1 && command.first == 'swiftc') {
      _runResults[_buildKey] = result;
      return;
    }
    _runResults[command.join('\u{1f}')] = result;
  }

  void addHelperList(ScreenRecorderCommandResult result) {
    _runResults['helper:list'] = result;
  }

  void addXctraceList(ScreenRecorderCommandResult result) {
    _runResults['xctrace:list'] = result;
  }

  void addPhysicalDeviceList(Map<String, String> devicesById) {
    autoServeProtocol = true;
    final StringBuffer buffer = StringBuffer('id\tname\tmodel\tmanufacturer\n');
    for (final MapEntry<String, String> entry in devicesById.entries) {
      buffer.writeln('${entry.key}\t${entry.value}\tiOS Device\tApple Inc.');
    }
    addHelperList(
      ScreenRecorderCommandResult(
        exitCode: 0,
        stdout: buffer.toString(),
        stderr: '',
      ),
    );
  }

  void completeNextProcessImmediately({
    required int exitCode,
    String stdout = '',
    String stderr = '',
  }) {
    _nextProcessExitCode = exitCode;
    _nextProcessStdout = stdout;
    _nextProcessStderr = stderr;
  }

  @override
  Future<ScreenRecorderCommandResult> run(
    String executable,
    List<String> arguments,
  ) async {
    runCommands.add(<String>[executable, ...arguments]);
    if (executable == 'swiftc') {
      return _runResults[_buildKey] ??
          (throw StateError('Unexpected swift build command'));
    }
    if (arguments.length == 1 && arguments.first == 'list') {
      return _runResults['helper:list'] ??
          (throw StateError('Unexpected helper list command'));
    }
    if (executable == 'xcrun' &&
        arguments.length == 3 &&
        arguments[0] == 'xctrace' &&
        arguments[1] == 'list' &&
        arguments[2] == 'devices') {
      return _runResults['xctrace:list'] ??
          (throw StateError('Unexpected xctrace list command'));
    }
    throw StateError(
      'Unexpected command: ${<String>[executable, ...arguments]}',
    );
  }

  @override
  Future<ScreenRecorderByteCommandResult> runBytes(
    String executable,
    List<String> arguments,
  ) async {
    throw StateError(
      'Unexpected byte command: ${<String>[executable, ...arguments]}',
    );
  }

  @override
  Future<ScreenRecorderProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    startedCommands.add(<String>[executable, ...arguments]);
    final _FakeScreenRecorderProcess process = _FakeScreenRecorderProcess(
      stdoutValue: _nextProcessStdout,
      stderrValue: _nextProcessStderr,
      writtenLines: writtenLines,
      autoServeProtocol: autoServeProtocol,
      serveOutputBytes: defaultServeOutputBytes,
    );
    _lastProcess = process;
    final int? immediateExitCode = _nextProcessExitCode;
    if (autoServeProtocol &&
        immediateExitCode == null &&
        arguments.length == 3 &&
        arguments[0] == 'serve' &&
        arguments[1] == '--device-id') {
      scheduleMicrotask(() {
        process.emitStdoutLine('{"event":"ready"}');
      });
    }
    if (immediateExitCode != null) {
      process.complete(immediateExitCode);
    }
    _nextProcessExitCode = null;
    _nextProcessStdout = '';
    _nextProcessStderr = '';
    return process;
  }

  void completeProcessWithFile({
    required String outputPath,
    required List<int> bytes,
  }) {
    _lastProcess?.serveOutputBytes = bytes;
    _lastProcess?.onKill = () {
      File(outputPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    };
  }

  void emitStdoutLine(String line) {
    _lastProcess?.emitStdoutLine(line);
  }

  static const String _buildKey = 'swiftc';
}

class _FakeScreenRecorderProcess implements ScreenRecorderProcess {
  _FakeScreenRecorderProcess({
    this.stdoutValue = '',
    this.stderrValue = '',
    required this.writtenLines,
    required this.autoServeProtocol,
    this.serveOutputBytes,
  });

  final Completer<int> _exitCode = Completer<int>();
  final StreamController<String> _stdoutLines = StreamController<String>();
  final String stdoutValue;
  final String stderrValue;
  final List<String> writtenLines;
  final bool autoServeProtocol;
  List<int>? serveOutputBytes;
  void Function()? onKill;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<String> get stdout async => stdoutValue;

  @override
  Future<String> get stderr async => stderrValue;

  @override
  Stream<String> get stdoutLines => _stdoutLines.stream;

  bool get hasExited => _exitCode.isCompleted;

  @override
  void writeLine(String line) {
    writtenLines.add(line);
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, Object?>) {
      return;
    }
    if (decoded['operation'] == 'shutdown') {
      complete(0);
      return;
    }
    if (!autoServeProtocol) {
      return;
    }
    switch (decoded['operation']) {
      case 'start':
        emitStdoutLine('{"event":"started"}');
      case 'stop':
        final String? outputPath = _lastStartOutputPath();
        final List<int>? bytes = serveOutputBytes;
        if (outputPath != null && bytes != null) {
          File(outputPath)
            ..createSync(recursive: true)
            ..writeAsBytesSync(bytes);
        }
        emitStdoutLine(
          jsonEncode(<String, String>{
            'event': 'saved',
            if (outputPath != null) 'outputPath': outputPath,
          }),
        );
    }
  }

  @override
  Future<void> closeStdin() async {}

  void emitStdoutLine(String line) {
    _stdoutLines.add(line);
  }

  String? _lastStartOutputPath() {
    for (final String line in writtenLines.reversed) {
      final Object? decoded = jsonDecode(line);
      if (decoded
          case <String, Object?>{
            'operation': 'start',
            'outputPath': final Object? outputPath,
          }) {
        return outputPath?.toString();
      }
    }
    return null;
  }

  void complete(int exitCode) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(exitCode);
    }
    unawaited(_stdoutLines.close());
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    onKill?.call();
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
    unawaited(_stdoutLines.close());
    return true;
  }
}
