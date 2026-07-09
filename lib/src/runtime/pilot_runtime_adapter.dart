import 'package:pilot_runtime/pilot_runtime.dart';

import '../scenario.dart';
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
