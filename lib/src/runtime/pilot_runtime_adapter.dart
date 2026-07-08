import 'package:pilot_runtime_client/pilot_runtime_client.dart';

import '../scenario.dart';
import 'runtime_contract.dart';

/// Runtime Adapter backed by the `pilot_runtime` package.
///
/// This first adapter slice verifies the app-side runtime handshake and exposes
/// Widget Tree capture through Flutter Pilot's existing Runtime Adapter
/// contract. User actions are implemented in later runtime slices.
class PilotRuntimeAdapter implements RuntimeAdapter {
  /// Create an adapter backed by a checked `pilot_runtime` client.
  const PilotRuntimeAdapter({
    required PilotRuntimeClient client,
    required String projectRoot,
    Future<void> Function()? disposeClient,
  }) : _client = client,
       _projectRoot = projectRoot,
       _disposeClient = disposeClient;

  final PilotRuntimeClient _client;
  final String _projectRoot;
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
  Future<List<FinderMatch>> resolveFinder(Finder finder) {
    throw _notImplemented(RuntimeOperation.resolveFinder);
  }

  @override
  Future<void> performTap(FinderMatch match) {
    throw _notImplemented(RuntimeOperation.performTap);
  }

  @override
  Future<void> replaceText(FinderMatch match, String text) {
    throw _notImplemented(RuntimeOperation.replaceText);
  }

  @override
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  }) {
    throw _notImplemented(RuntimeOperation.performScroll);
  }

  @override
  Future<ScreenshotCapture> captureScreenshot() {
    throw _notImplemented(RuntimeOperation.captureScreenshot);
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
  Future<LogsCapture> collectLogs() {
    throw _notImplemented(RuntimeOperation.collectLogs);
  }

  RuntimeOperationException _notImplemented(RuntimeOperation operation) {
    return RuntimeOperationException(
      operation: operation,
      message: '${operation.name} is not implemented for pilot_runtime yet.',
    );
  }
}
