import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Target App Package setup checks through the public app setup API.
void main() {
  test(
    'reports complete setup for a Flutter package with mcp_toolkit',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory packageDirectory = Directory('/target_app')
          ..createSync(recursive: true);
        _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
  mcp_toolkit: ^0.6.0
''');
        _writeMain(packageDirectory, '''
import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

Future<void> main() async {
  await MCPToolkitBinding.instance.bootstrapFlutter(
    runApp: () => runApp(const Placeholder()),
  );
}
''');

        final AppSetupStatus status = AppSetupChecker.check(packageDirectory);

        expect(status.isFlutterPackage, isTrue);
        expect(status.hasMcpToolkitDependency, isTrue);
        expect(status.hasBootstrapFlutter, isTrue);
        expect(status.isComplete, isTrue);
      });
    },
  );

  test('does not accept mcp_toolkit from dev dependencies', () async {
    await FileTestkit.runZoned(() async {
      final Directory packageDirectory = Directory('/target_app')
        ..createSync(recursive: true);
      _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  mcp_toolkit: ^0.6.0
''');
      _writeMain(packageDirectory, '''
void main() {
  MCPToolkitBinding.instance.bootstrapFlutter();
}
''');

      final AppSetupStatus status = AppSetupChecker.check(packageDirectory);

      expect(status.isFlutterPackage, isTrue);
      expect(status.hasMcpToolkitDependency, isFalse);
      expect(status.hasBootstrapFlutter, isTrue);
      expect(status.isComplete, isFalse);
    });
  });

  test(
    'init adds mcp_toolkit dependency when runtime dependency is missing',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory packageDirectory = Directory('/target_app')
          ..createSync(recursive: true);
        _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
''');
        final List<Directory> installDirectories = <Directory>[];

        final AppSetupInitResult result = await AppSetupInitializer.initialize(
          packageDirectory,
          addMcpToolkitDependency: (Directory directory) async {
            installDirectories.add(directory);
            return const AppSetupInstallResult.success();
          },
        );

        expect(result.addedMcpToolkitDependency, isTrue);
        expect(result.status.hasMcpToolkitDependency, isFalse);
        expect(installDirectories, <Directory>[packageDirectory]);
      });
    },
  );

  test('init stops when mcp_toolkit dependency install fails', () async {
    await FileTestkit.runZoned(() async {
      final Directory packageDirectory = Directory('/target_app')
        ..createSync(recursive: true);
      _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
''');

      expect(
        () => AppSetupInitializer.initialize(
          packageDirectory,
          addMcpToolkitDependency: (Directory directory) async {
            return const AppSetupInstallResult.failure(
              exitCode: 69,
              stderr: 'pub failed',
            );
          },
        ),
        throwsA(isA<AppSetupInstallException>()),
      );
    });
  });
}

void _writePubspec(Directory packageDirectory, String contents) {
  File('${packageDirectory.path}/pubspec.yaml').writeAsStringSync(contents);
}

void _writeMain(Directory packageDirectory, String contents) {
  final Directory libDirectory = Directory('${packageDirectory.path}/lib')
    ..createSync(recursive: true);
  File('${libDirectory.path}/main.dart').writeAsStringSync(contents);
}
