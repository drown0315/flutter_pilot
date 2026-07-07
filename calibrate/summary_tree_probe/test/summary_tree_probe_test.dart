import 'package:test/test.dart';

import '../bin/service_extension_inventory.dart';
import '../bin/summary_tree_probe.dart';

void main() {
  group('ProbeArguments', () {
    test('parses optional output file path', () {
      final ProbeArguments? arguments = ProbeArguments.parse(const <String>[
        '--vm-service-uri',
        'ws://127.0.0.1:12345/token=/ws',
        '--project-root',
        '/Users/example/app',
        '--output',
        'out/summary-tree.txt',
      ]);

      expect(arguments, isNotNull);
      expect(arguments!.outputPath, 'out/summary-tree.txt');
    });

    test('parses full details flag for creation location calibration', () {
      final ProbeArguments? arguments = ProbeArguments.parse(const <String>[
        '--vm-service-uri',
        'ws://127.0.0.1:12345/token=/ws',
        '--project-root',
        '/Users/example/app',
        '--full-details',
      ]);

      expect(arguments, isNotNull);
      expect(arguments!.fullDetails, isTrue);
    });
  });

  group('InventoryArguments', () {
    test('parses optional output file path', () {
      final InventoryArguments? arguments =
          InventoryArguments.parse(const <String>[
        '--vm-service-uri',
        'ws://127.0.0.1:12345/token=/ws',
        '--output',
        'out/service-extensions.txt',
      ]);

      expect(arguments, isNotNull);
      expect(arguments!.outputPath, 'out/service-extensions.txt');
    });
  });
}
