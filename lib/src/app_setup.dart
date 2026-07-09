import 'dart:io';

import 'package:yaml/yaml.dart';

/// Setup state for the current Target App Package.
///
/// It records whether the current package is a Flutter package, whether
/// `mcp_toolkit` is available as a runtime dependency, and whether the app
/// entrypoint appears to call `bootstrapFlutter`.
class AppSetupStatus {
  const AppSetupStatus({
    required this.isFlutterPackage,
    required this.hasMcpToolkitDependency,
    required this.hasBootstrapFlutter,
  });

  /// Whether `pubspec.yaml` declares `dependencies.flutter.sdk: flutter`.
  final bool isFlutterPackage;

  /// Whether `mcp_toolkit` is declared under runtime `dependencies`.
  final bool hasMcpToolkitDependency;

  /// Whether `lib/main.dart` contains the MCP Toolkit bootstrap call.
  final bool hasBootstrapFlutter;

  /// Whether all required Flutter Pilot app setup was found.
  bool get isComplete =>
      isFlutterPackage && hasMcpToolkitDependency && hasBootstrapFlutter;
}

/// Result of trying to add `mcp_toolkit` to a Target App Package.
class AppSetupInstallResult {
  const AppSetupInstallResult.success() : exitCode = 0, stderr = '';

  const AppSetupInstallResult.failure({
    required this.exitCode,
    required this.stderr,
  });

  /// Process-like exit code returned by the dependency installer.
  final int exitCode;

  /// Error output returned by the dependency installer.
  final String stderr;

  /// Whether the dependency installer reported success.
  bool get succeeded => exitCode == 0;
}

/// Result of running the safe app setup initializer.
class AppSetupInitResult {
  const AppSetupInitResult({
    required this.status,
    required this.addedMcpToolkitDependency,
  });

  /// Setup status observed before any dependency installation.
  final AppSetupStatus status;

  /// Whether initialization successfully ran `flutter pub add mcp_toolkit`.
  final bool addedMcpToolkitDependency;
}

/// Adds the safe Flutter Pilot dependency setup when it is missing.
typedef AppSetupDependencyInstaller =
    Future<AppSetupInstallResult> Function(Directory packageDirectory);

/// Initializes the dependency portion of Flutter Pilot app setup.
class AppSetupInitializer {
  AppSetupInitializer._();

  /// Add `mcp_toolkit` when the current package lacks the runtime dependency.
  ///
  /// Args:
  /// `packageDirectory` is the Target App Package root.
  /// `addMcpToolkitDependency` runs the dependency tool. Production code uses
  /// `flutter pub add mcp_toolkit`; tests can pass a fake installer.
  ///
  /// Returns:
  /// Whether the dependency install was run and the setup status observed
  /// before the install. The Dart entrypoint is never modified.
  static Future<AppSetupInitResult> initialize(
    Directory packageDirectory, {
    required AppSetupDependencyInstaller addMcpToolkitDependency,
  }) async {
    final AppSetupStatus status = AppSetupChecker.check(packageDirectory);
    if (!status.hasMcpToolkitDependency) {
      final AppSetupInstallResult installResult = await addMcpToolkitDependency(
        packageDirectory,
      );
      if (!installResult.succeeded) {
        throw AppSetupInstallException(installResult);
      }
      return AppSetupInitResult(
        status: status,
        addedMcpToolkitDependency: true,
      );
    }
    return AppSetupInitResult(status: status, addedMcpToolkitDependency: false);
  }
}

/// Failure returned when `flutter pub add mcp_toolkit` does not succeed.
class AppSetupInstallException implements Exception {
  const AppSetupInstallException(this.result);

  /// Failed dependency install result.
  final AppSetupInstallResult result;
}

/// Checks whether a directory is prepared as a Flutter Pilot Target App Package.
class AppSetupChecker {
  AppSetupChecker._();

  static const String bootstrapCall =
      'MCPToolkitBinding.instance.bootstrapFlutter';

  /// Inspect `packageDirectory` without modifying files.
  ///
  /// Args:
  /// `packageDirectory` is the directory expected to contain `pubspec.yaml` and
  /// the Flutter app entrypoint.
  ///
  /// Returns:
  /// Setup status for the package. Missing files are reported as absent setup
  /// rather than being created.
  static AppSetupStatus check(Directory packageDirectory) {
    final File pubspecFile = File('${packageDirectory.path}/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      return const AppSetupStatus(
        isFlutterPackage: false,
        hasMcpToolkitDependency: false,
        hasBootstrapFlutter: false,
      );
    }
    final Object? pubspec = loadYaml(pubspecFile.readAsStringSync());
    final bool isFlutterPackage = _isDeclaresFlutterSdk(pubspec);
    final bool hasMcpToolkitDependency = _hasRuntimeMcpToolkit(pubspec);
    final File mainFile = File('${packageDirectory.path}/lib/main.dart');
    final bool hasBootstrapFlutter =
        mainFile.existsSync() &&
        mainFile.readAsStringSync().contains(bootstrapCall);

    return AppSetupStatus(
      isFlutterPackage: isFlutterPackage,
      hasMcpToolkitDependency: hasMcpToolkitDependency,
      hasBootstrapFlutter: hasBootstrapFlutter,
    );
  }

  /// Return whether the pubspec declares a Flutter SDK dependency.
  static bool _isDeclaresFlutterSdk(Object? pubspec) {
    if (pubspec case {'dependencies': {'flutter': {'sdk': 'flutter'}}}) {
      return true;
    }
    return false;
  }

  /// Return whether the pubspec declares `mcp_toolkit` as a runtime dependency.
  static bool _hasRuntimeMcpToolkit(Object? pubspec) {
    if (pubspec case {'dependencies': {'mcp_toolkit': Object()}}) {
      return true;
    }
    return false;
  }
}
