import 'dart:io';
import 'dart:typed_data';

import 'package:pilot_runtime/pilot_runtime.dart';

import '../scenario/scenario.dart';
import 'runtime_contract.dart';

/// Runtime Adapter backed by the `pilot_runtime` package.
///
/// This first adapter slice verifies the app-side runtime handshake and exposes
/// Widget Tree capture through Flutter Pilot's existing Runtime Adapter
/// contract.
class PilotRuntimeAdapter implements RuntimeAdapter {
  /// Create an adapter backed by a checked `pilot_runtime` client.
  const PilotRuntimeAdapter({
    required PilotRuntimeClient client,
    required String projectRoot,
    String? targetDeviceId,
    FlutterScreenshotCapturer screenshotCapturer =
        const FlutterCliScreenshotCapturer(),
    Future<void> Function()? disposeClient,
  }) : _client = client,
       _projectRoot = projectRoot,
       _targetDeviceId = targetDeviceId,
       _screenshotCapturer = screenshotCapturer,
       _disposeClient = disposeClient;

  final PilotRuntimeClient _client;
  final String _projectRoot;
  final String? _targetDeviceId;
  final FlutterScreenshotCapturer _screenshotCapturer;
  final Future<void> Function()? _disposeClient;

  @override
  Future<void> initialize() async {
    try {
      await _client.initialize();
    } on PilotRuntimeInitializationException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.initialize,
        message: error.message,
        cause: error,
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _disposeClient?.call();
  }

  @override
  Future<List<FinderMatch>> resolveFinder(Finder finder) async {
    final List<PilotRuntimeFinderMatch> matches = await _client.resolveFinder(
      byText: finder.byText,
      byType: finder.byType,
      byKey: finder.byKey,
      byWidget: finder.byWidget,
    );
    return <FinderMatch>[
      for (final PilotRuntimeFinderMatch match in matches)
        FinderMatch(
          id: match.handle,
          debugLabel: _debugLabelFor(match),
          text: match.text,
          key: match.key,
          type: match.semanticType,
          bounds: match.bounds == null
              ? null
              : WidgetBounds(
                  left: match.bounds!.left,
                  top: match.bounds!.top,
                  width: match.bounds!.width,
                  height: match.bounds!.height,
                ),
        ),
    ];
  }

  @override
  Future<void> performTap(FinderMatch match) async {
    try {
      await _client.performTap(handle: match.id);
    } on PilotRuntimeActionException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.performTap,
        message: error.message,
        cause: error,
      );
    } catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.performTap,
        message: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> clearText(FinderMatch match) async {
    try {
      await _client.clearText(handle: match.id);
    } on PilotRuntimeActionException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.clearText,
        message: error.message,
        cause: error,
      );
    } catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.clearText,
        message: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> enterText(FinderMatch match, String text) async {
    try {
      await _client.enterText(handle: match.id, text: text);
    } on PilotRuntimeActionException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.enterText,
        message: error.message,
        cause: error,
      );
    } catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.enterText,
        message: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  }) async {
    try {
      await _client.performScroll(
        handle: match?.id,
        deltaX: deltaX,
        deltaY: deltaY,
      );
    } on PilotRuntimeActionException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.performScroll,
        message: error.message,
        cause: error,
      );
    } catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.performScroll,
        message: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<ScreenshotCapture> captureScreenshot() async {
    final String? targetDeviceId = _targetDeviceId;
    if (targetDeviceId == null || targetDeviceId.isEmpty) {
      throw const RuntimeOperationException(
        operation: RuntimeOperation.captureScreenshot,
        message:
            'Screenshot capture requires a selected Target Device. Pass --device so Flutter Pilot can call flutter screenshot -d.',
      );
    }
    try {
      final Uint8List bytes = await _screenshotCapturer.captureDeviceScreenshot(
        deviceId: targetDeviceId,
      );
      return ScreenshotCapture(bytes: bytes, mimeType: 'image/png');
    } on FlutterScreenshotException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.captureScreenshot,
        message: error.message,
        cause: error,
        rawOutput: error.diagnosticOutput,
      );
    }
  }

  @override
  Future<SnapshotCapture> captureSnapshot() {
    throw _notImplemented(RuntimeOperation.captureSnapshot);
  }

  @override
  Future<WidgetTreeCapture> captureWidgetTree() async {
    try {
      final Map<String, Object?> data = await _client.captureWidgetTree(
        projectRoot: _projectRoot,
      );
      return WidgetTreeCapture(data: data);
    } on PilotRuntimeWidgetTreeCaptureException catch (error) {
      throw RuntimeOperationException(
        operation: RuntimeOperation.captureWidgetTree,
        message: error.message,
        cause: error,
      );
    }
  }

  @override
  Future<LogsCapture> collectLogs() async {
    final Map<String, Object?> data = await _client.collectLogs();
    return LogsCapture(data: data);
  }

  RuntimeOperationException _notImplemented(RuntimeOperation operation) {
    return RuntimeOperationException(
      operation: operation,
      message: '${operation.name} is not implemented for pilot_runtime yet.',
    );
  }

  String? _debugLabelFor(PilotRuntimeFinderMatch match) {
    final List<String> parts = <String>[
      if (match.matchedWidgetType != null)
        'matchedWidgetType=${match.matchedWidgetType}',
      if (match.actionWidgetType != null) match.actionWidgetType!,
      if (match.semanticType != null) 'semanticType=${match.semanticType}',
      if (match.key != null) 'key="${match.key}"',
      if (match.text != null) 'text="${match.text}"',
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' ');
  }
}

/// Captures one Screenshot from a Flutter Target Device.
///
/// Implementations return encoded PNG bytes. The Runtime Adapter maps failures
/// into `RuntimeOperationException` so runner and report code can keep one
/// runtime failure shape.
abstract interface class FlutterScreenshotCapturer {
  /// Run a Flutter device screenshot for the selected Target Device.
  ///
  /// Args:
  /// `deviceId` is passed to `flutter screenshot -d`.
  ///
  /// Returns:
  /// Encoded PNG bytes from the screenshot file produced by Flutter.
  Future<Uint8List> captureDeviceScreenshot({required String deviceId});
}

/// Flutter CLI-backed Screenshot capture implementation.
///
/// It shells out to `flutter screenshot -d <device> --out <temp.png>`, reads the
/// PNG bytes, and deletes the temporary directory afterwards.
class FlutterCliScreenshotCapturer implements FlutterScreenshotCapturer {
  /// Create a Flutter CLI screenshot capturer.
  ///
  /// `processRunner` is injectable so tests can verify command construction
  /// without starting a real Flutter process.
  const FlutterCliScreenshotCapturer({
    this.processRunner = const IoFlutterScreenshotProcessRunner(),
  });

  final FlutterScreenshotProcessRunner processRunner;

  @override
  Future<Uint8List> captureDeviceScreenshot({required String deviceId}) async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'flutter_pilot_screenshot_',
    );
    final File outputFile = File('${tempDirectory.path}/screenshot.png');
    try {
      final FlutterScreenshotProcessResult result = await processRunner.run(
        'flutter',
        <String>['screenshot', '-d', deviceId, '--out', outputFile.path],
      );
      if (result.exitCode != 0) {
        throw FlutterScreenshotException(
          message:
              'Flutter screenshot failed for Target Device "$deviceId" with exit code ${result.exitCode}.',
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      }
      if (!outputFile.existsSync()) {
        throw FlutterScreenshotException(
          message:
              'Flutter screenshot did not create an output file for Target Device "$deviceId".',
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      }
      return Uint8List.fromList(outputFile.readAsBytesSync());
    } finally {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    }
  }
}

/// Process runner used by Flutter CLI screenshot capture.
abstract interface class FlutterScreenshotProcessRunner {
  /// Run `executable` with `arguments` and return captured output.
  Future<FlutterScreenshotProcessResult> run(
    String executable,
    List<String> arguments,
  );
}

/// `dart:io` process runner for Flutter screenshot commands.
class IoFlutterScreenshotProcessRunner
    implements FlutterScreenshotProcessRunner {
  /// Create the default process runner.
  const IoFlutterScreenshotProcessRunner();

  @override
  Future<FlutterScreenshotProcessResult> run(
    String executable,
    List<String> arguments,
  ) async {
    final ProcessResult result = await Process.run(executable, arguments);
    return FlutterScreenshotProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

/// Captured result from one Flutter screenshot process.
class FlutterScreenshotProcessResult {
  /// Create a completed screenshot process result.
  const FlutterScreenshotProcessResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Failure raised when `flutter screenshot` cannot produce a PNG file.
class FlutterScreenshotException implements Exception {
  /// Create a screenshot failure with command output for diagnostics.
  const FlutterScreenshotException({
    required this.message,
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final String message;
  final int exitCode;
  final String stdout;
  final String stderr;

  /// Combined command output suitable for runtime diagnostic records.
  String get diagnosticOutput {
    final List<String> parts = <String>[
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ];
    return parts.join('\n');
  }

  @override
  String toString() => message;
}
