import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import '../app_setup.dart';

/// `doctor` command for checking Flutter Pilot setup in a Target App Package.
///
/// It inspects the current working directory without modifying files. Missing
/// setup is reported as diagnostic output, while unreadable or unsupported
/// package shapes return an execution failure.
class DoctorCommand extends Command<int> {
  @override
  String get description => 'Check Flutter Pilot setup in a Flutter package.';

  @override
  String get name => 'doctor';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException('Expected no arguments.', usage);
    }
    try {
      final AppSetupStatus status = AppSetupChecker.check(Directory.current);
      if (!status.isFlutterPackage) {
        stderr.writeln(_flutterPackageOnlyMessage);
        return 1;
      }
      stdout.writeln('Flutter Pilot doctor');
      stdout.writeln('');
      if (status.isComplete) {
        stdout.writeln('✅ Flutter Pilot app setup is complete.');
      } else {
        if (!status.hasPilotRuntimeDependency) {
          stdout.writeln(
            '❌ pilot_runtime dependency missing: run `flutter pub add pilot_runtime`',
          );
        }
        if (!status.hasPilotRuntimeBinding) {
          _writeBootstrapGuidance();
        }
      }
      return 0;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on YamlException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// `init` command for adding safe Flutter Pilot setup to a Target App Package.
///
/// It can add the `pilot_runtime` dependency through Flutter tooling, then
/// reports whether the app entrypoint still needs manual binding code.
class InitCommand extends Command<int> {
  @override
  String get description =>
      'Initialize Flutter Pilot setup in a Flutter package.';

  @override
  String get name => 'init';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException('Expected no arguments.', usage);
    }
    try {
      final AppSetupStatus status = AppSetupChecker.check(Directory.current);
      if (!status.isFlutterPackage) {
        stderr.writeln(_flutterPackageOnlyMessage);
        return 1;
      }
      final AppSetupInitResult result = await AppSetupInitializer.initialize(
        Directory.current,
        addPilotRuntimeDependency: _addPilotRuntimeDependency,
      );
      stdout.writeln('Flutter Pilot init');
      stdout.writeln('');
      if (result.addedPilotRuntimeDependency) {
        stdout.writeln('✅ Added pilot_runtime dependency.');
      } else {
        stdout.writeln('✅ pilot_runtime dependency already exists.');
      }
      if (result.status.hasPilotRuntimeBinding) {
        stdout.writeln('✅ PilotRuntimeBinding already exists.');
      } else {
        _writeBootstrapGuidance();
      }
      return 0;
    } on AppSetupInstallException catch (error) {
      stderr.writeln('Failed to add pilot_runtime dependency.');
      if (error.result.stderr.isNotEmpty) {
        stderr.writeln('');
        stderr.writeln('flutter pub add output:');
        stderr.write(error.result.stderr);
      }
      stderr.writeln('');
      stderr.writeln('Run this command manually from the Flutter package:');
      stderr.writeln('flutter pub add pilot_runtime');
      return 1;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      return 1;
    } on YamlException catch (error) {
      stderr.writeln(error.message);
      return 1;
    }
  }
}

/// Run Flutter tooling to add the runtime dependency.
Future<AppSetupInstallResult> _addPilotRuntimeDependency(
  Directory packageDirectory,
) async {
  try {
    final ProcessResult result = await Process.run('flutter', <String>[
      'pub',
      'add',
      'pilot_runtime',
    ], workingDirectory: packageDirectory.path);
    if (result.exitCode == 0) {
      return const AppSetupInstallResult.success();
    }
    return AppSetupInstallResult.failure(
      exitCode: result.exitCode,
      stderr: result.stderr.toString(),
    );
  } on ProcessException catch (error) {
    return AppSetupInstallResult.failure(exitCode: 1, stderr: error.message);
  }
}

/// Print the manual app entrypoint change required for pilot_runtime.
void _writeBootstrapGuidance() {
  stdout.writeln(
    '❌ PilotRuntimeBinding missing: add '
    'PilotRuntimeBinding.ensureInitialized() in lib/main.dart',
  );
  stdout.writeln('');
  stdout.writeln('Add the pilot_runtime import:');
  stdout.writeln("import 'package:pilot_runtime/pilot_runtime.dart';");
  stdout.writeln('');
  stdout.writeln('Initialize PilotRuntimeBinding before runApp:');
  stdout.writeln('void main() {');
  stdout.writeln('  WidgetsFlutterBinding.ensureInitialized();');
  stdout.writeln('  PilotRuntimeBinding.ensureInitialized();');
  stdout.writeln('  runApp(const MyApp());');
  stdout.writeln('}');
}

const String _flutterPackageOnlyMessage =
    'Flutter Pilot only supports Flutter packages. Run this command from a '
    'directory with a pubspec.yaml that declares dependencies.flutter.sdk: '
    'flutter.';
