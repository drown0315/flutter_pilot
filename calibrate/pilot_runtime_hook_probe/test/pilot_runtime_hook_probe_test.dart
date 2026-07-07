import 'package:test/test.dart';

import '../bin/pilot_runtime_hook_probe.dart';

void main() {
  group('ProbeArguments', () {
    test('parses required VM Service URI', () {
      final ProbeArguments? arguments = ProbeArguments.parse(const <String>[
        '--vm-service-uri',
        'ws://127.0.0.1:12345/token=/ws',
      ]);

      expect(arguments, isNotNull);
      expect(arguments!.vmServiceUri, 'ws://127.0.0.1:12345/token=/ws');
    });

    test('parses optional output path', () {
      final ProbeArguments? arguments = ProbeArguments.parse(const <String>[
        '--vm-service-uri=ws://127.0.0.1:12345/token=/ws',
        '--output',
        'out/hook-probe-macos.txt',
      ]);

      expect(arguments, isNotNull);
      expect(arguments!.outputPath, 'out/hook-probe-macos.txt');
    });
  });
}
