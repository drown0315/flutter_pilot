import 'dart:io';

import 'package:test/test.dart';

/// Verifies extraction of the VM service URI from Flutter machine output.
void main() {
  test('prints GitHub output for app debug port websocket URI', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_machine_uri_',
    );
    try {
      final File logFile = File('${tempDirectory.path}/machine.log')
        ..writeAsStringSync('''
{"event":"app.start","params":{"appId":"1"}}
{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:1234/token=/ws"}}
''');

      final ProcessResult result =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            'tool/extract_flutter_machine_ws_uri.dart',
            logFile.path,
            '--timeout-seconds',
            '1',
          ]);

      expect(result.exitCode, 0);
      expect(
        result.stdout,
        contains('vm_service_uri=ws://127.0.0.1:1234/token=/ws'),
      );
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });

  test('exits non-zero when the debug port event is missing', () async {
    final Directory tempDirectory = Directory.systemTemp.createTempSync(
      'flutter_machine_uri_',
    );
    try {
      final File logFile = File('${tempDirectory.path}/machine.log')
        ..writeAsStringSync('{"event":"app.start","params":{"appId":"1"}}');

      final ProcessResult result =
          await Process.run(Platform.resolvedExecutable, [
            'run',
            'tool/extract_flutter_machine_ws_uri.dart',
            logFile.path,
            '--timeout-seconds',
            '1',
          ]);

      expect(result.exitCode, isNonZero);
      expect(result.stderr, contains('Timed out waiting'));
    } finally {
      tempDirectory.deleteSync(recursive: true);
    }
  });
}
