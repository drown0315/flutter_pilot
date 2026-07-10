import 'dart:io';

import 'package:file_testkit/file_testkit.dart';
import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Exercises Target App Package setup checks through the public app setup API.
void main() {
  test(
    'reports complete setup for a Flutter package with pilot_runtime',
    () async {
      await FileTestkit.runZoned(() async {
        final Directory packageDirectory = Directory('/target_app')
          ..createSync(recursive: true);
        _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
  pilot_runtime:
    path: packages/pilot_runtime
''');
        _writeMain(packageDirectory, '''
import 'package:flutter/material.dart';
import 'package:pilot_runtime/pilot_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PilotRuntimeBinding.ensureInitialized();
  runApp(const Placeholder());
}
''');

        final AppSetupStatus status = AppSetupChecker.check(packageDirectory);

        expect(status.isFlutterPackage, isTrue);
        expect(status.hasPilotRuntimeDependency, isTrue);
        expect(status.hasPilotRuntimeBinding, isTrue);
        expect(status.isComplete, isTrue);
      });
    },
  );

  test('does not accept pilot_runtime from dev dependencies', () async {
    await FileTestkit.runZoned(() async {
      final Directory packageDirectory = Directory('/target_app')
        ..createSync(recursive: true);
      _writePubspec(packageDirectory, '''
name: target_app
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  pilot_runtime:
    path: packages/pilot_runtime
''');
      _writeMain(packageDirectory, '''
void main() {
  PilotRuntimeBinding.ensureInitialized();
}
''');

      final AppSetupStatus status = AppSetupChecker.check(packageDirectory);

      expect(status.isFlutterPackage, isTrue);
      expect(status.hasPilotRuntimeDependency, isFalse);
      expect(status.hasPilotRuntimeBinding, isTrue);
      expect(status.isComplete, isFalse);
    });
  });

  test(
    'init adds pilot_runtime dependency when runtime dependency is missing',
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
          addPilotRuntimeDependency: (Directory directory) async {
            installDirectories.add(directory);
            return const AppSetupInstallResult.success();
          },
        );

        expect(result.addedPilotRuntimeDependency, isTrue);
        expect(result.status.hasPilotRuntimeDependency, isFalse);
        expect(installDirectories, <Directory>[packageDirectory]);
      });
    },
  );

  test('init stops when pilot_runtime dependency install fails', () async {
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
          addPilotRuntimeDependency: (Directory directory) async {
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
