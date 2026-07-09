import 'dart:typed_data';

import 'package:flutter_pilot/flutter_pilot.dart';

/// In-memory Runtime Adapter for runner and contract tests.
///
/// It lets tests configure Finder results and capture payloads without a live
/// Flutter app. Every method records a `FakeRuntimeEvent` so tests can assert
/// the public behavior that the runner requested.
class FakeRuntimeAdapter implements RuntimeAdapter {
  FakeRuntimeAdapter({
    Map<String, List<FinderMatch>>? finderResults,
    Map<String, List<List<FinderMatch>>>? finderResultSequences,
    ScreenshotCapture? screenshot,
    SnapshotCapture? snapshot,
    WidgetTreeCapture? widgetTree,
    LogsCapture? logs,
    Map<RuntimeOperation, RuntimeOperationException>? failures,
  }) : finderResults = finderResults ?? <String, List<FinderMatch>>{},
       finderResultSequences =
           finderResultSequences ?? <String, List<List<FinderMatch>>>{},
       failures = failures ?? <RuntimeOperation, RuntimeOperationException>{},
       screenshot =
           screenshot ??
           ScreenshotCapture(
             bytes: Uint8List.fromList(<int>[]),
             mimeType: 'image/png',
           ),
       snapshot = snapshot ?? const SnapshotCapture(data: <String, Object?>{}),
       widgetTree =
           widgetTree ?? const WidgetTreeCapture(data: <String, Object?>{}),
       logs = logs ?? const LogsCapture(data: <String, Object?>{});

  final Map<String, List<FinderMatch>> finderResults;

  /// Ordered Finder results returned one per `resolveFinder` call.
  ///
  /// This lets runner tests model time-sensitive behavior, such as a widget
  /// appearing after a `waitFor` poll. After the sequence is exhausted, the fake
  /// falls back to `finderResults`.
  final Map<String, List<List<FinderMatch>>> finderResultSequences;

  final ScreenshotCapture screenshot;
  final SnapshotCapture snapshot;
  final WidgetTreeCapture widgetTree;
  final LogsCapture logs;
  final Map<RuntimeOperation, RuntimeOperationException> failures;
  final List<FakeRuntimeEvent> events = <FakeRuntimeEvent>[];
  final Map<String, int> _finderSequenceOffsets = <String, int>{};

  @override
  Future<void> initialize() async {
    _throwIfConfigured(RuntimeOperation.initialize);
    events.add(const FakeRuntimeEvent(operation: RuntimeOperation.initialize));
  }

  @override
  Future<void> dispose() async {
    _throwIfConfigured(RuntimeOperation.dispose);
    events.add(const FakeRuntimeEvent(operation: RuntimeOperation.dispose));
  }

  @override
  Future<List<FinderMatch>> resolveFinder(Finder finder) async {
    _throwIfConfigured(RuntimeOperation.resolveFinder);
    events.add(
      FakeRuntimeEvent(
        operation: RuntimeOperation.resolveFinder,
        finder: finder,
      ),
    );
    final String finderKey = _finderKey(finder);
    final List<List<FinderMatch>>? sequence = finderResultSequences[finderKey];
    final int sequenceOffset = _finderSequenceOffsets[finderKey] ?? 0;
    if (sequence != null && sequenceOffset < sequence.length) {
      _finderSequenceOffsets[finderKey] = sequenceOffset + 1;
      return sequence[sequenceOffset];
    }
    return finderResults[finderKey] ?? const <FinderMatch>[];
  }

  @override
  Future<void> performTap(FinderMatch match) async {
    _throwIfConfigured(RuntimeOperation.performTap);
    events.add(
      FakeRuntimeEvent(operation: RuntimeOperation.performTap, match: match),
    );
  }

  @override
  Future<void> replaceText(FinderMatch match, String text) async {
    _throwIfConfigured(RuntimeOperation.replaceText);
    events.add(
      FakeRuntimeEvent(
        operation: RuntimeOperation.replaceText,
        match: match,
        text: text,
      ),
    );
  }

  @override
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  }) async {
    _throwIfConfigured(RuntimeOperation.performScroll);
    events.add(
      FakeRuntimeEvent(
        operation: RuntimeOperation.performScroll,
        match: match,
        deltaX: deltaX,
        deltaY: deltaY,
      ),
    );
  }

  @override
  Future<ScreenshotCapture> captureScreenshot() async {
    _throwIfConfigured(RuntimeOperation.captureScreenshot);
    events.add(
      const FakeRuntimeEvent(operation: RuntimeOperation.captureScreenshot),
    );
    return screenshot;
  }

  @override
  Future<SnapshotCapture> captureSnapshot() async {
    _throwIfConfigured(RuntimeOperation.captureSnapshot);
    events.add(
      const FakeRuntimeEvent(operation: RuntimeOperation.captureSnapshot),
    );
    return snapshot;
  }

  @override
  Future<WidgetTreeCapture> captureWidgetTree() async {
    _throwIfConfigured(RuntimeOperation.captureWidgetTree);
    events.add(
      const FakeRuntimeEvent(operation: RuntimeOperation.captureWidgetTree),
    );
    return widgetTree;
  }

  @override
  Future<LogsCapture> collectLogs() async {
    _throwIfConfigured(RuntimeOperation.collectLogs);
    events.add(const FakeRuntimeEvent(operation: RuntimeOperation.collectLogs));
    return logs;
  }

  /// Throw the configured Runtime failure for `operation`, if one exists.
  void _throwIfConfigured(RuntimeOperation operation) {
    final RuntimeOperationException? failure = failures[operation];
    if (failure != null) {
      throw failure;
    }
  }

  /// Convert a Finder into the test map key used by `finderResults`.
  ///
  /// A single-field Finder uses that value directly for compact tests. Combined
  /// Finders use a stable field-prefixed representation.
  String _finderKey(Finder finder) {
    final List<String> parts = <String>[
      if (finder.byText != null) 'byText=${finder.byText}',
      if (finder.byType != null) 'byType=${finder.byType}',
      if (finder.byKey != null) 'byKey=${finder.byKey}',
      if (finder.byWidget != null) 'byWidget=${finder.byWidget}',
    ];
    if (parts.length == 1) {
      return parts.single.split('=').last;
    }
    return parts.join('&');
  }
}

/// One method call recorded by `FakeRuntimeAdapter`.
///
/// Optional fields carry the public arguments passed to adapter operations,
/// allowing runner tests to assert behavior without mocking private methods.
class FakeRuntimeEvent {
  const FakeRuntimeEvent({
    required this.operation,
    this.finder,
    this.match,
    this.text,
    this.deltaX,
    this.deltaY,
  });

  final RuntimeOperation operation;
  final Finder? finder;
  final FinderMatch? match;
  final String? text;
  final double? deltaX;
  final double? deltaY;
}
