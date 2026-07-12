import 'dart:typed_data';

import '../scenario/scenario.dart';

/// Runtime Target selected for one Scenario run.
///
/// The first version accepts a Flutter VM service URI from the CLI `--target`
/// option. The target is bound when creating the real runtime adapter, rather
/// than passed to every adapter method.
class RuntimeTarget {
  const RuntimeTarget({required this.vmServiceUri, this.deviceId});

  final Uri vmServiceUri;

  /// Target Device id used for Flutter CLI operations that require `-d`.
  ///
  /// The id comes from an explicit `--device` selection when present, or from
  /// Flutter machine output when `flutter run` reports the launched device.
  final String? deviceId;
}

/// Boundary used by the runner to operate on a Flutter Runtime Target.
///
/// Implementations map Flutter Pilot actions and capture requests to a concrete
/// runtime bridge such as `pilot_runtime`. The runner owns Scenario control flow;
/// the adapter owns runtime communication and returns Flutter Pilot model
/// objects.
abstract interface class RuntimeAdapter {
  /// Prepare the adapter before any Scenario step executes.
  ///
  /// Implementations may establish a connection, discover a session, or perform
  /// a no-op when no setup is needed. If initialization fails, the run should
  /// fail before executing any Step.
  Future<void> initialize();

  /// Release runtime resources after a run finishes or fails.
  ///
  /// Implementations should make cleanup best-effort. The runner decides
  /// whether cleanup failure becomes the primary run failure or a secondary
  /// diagnostic based on whether the run had already failed.
  Future<void> dispose();

  /// Wait for the current or next Flutter frame to finish.
  ///
  /// `timeout` bounds this synchronization attempt. Timing out is not a
  /// Runtime operation failure; callers may continue with condition polling.
  Future<void> waitForEndOfFrame({required Duration timeout});

  /// Return all widgets that satisfy a Flutter Pilot Finder.
  ///
  /// Args:
  /// `finder` contains the Finder constraints from a Scenario action. When
  /// several fields are present, all constraints must match.
  ///
  /// Returns:
  /// A complete list of Finder Matches. The runner applies cardinality rules:
  /// zero matches keep polling until the Step budget expires, one match
  /// executes, and multiple matches fail immediately.
  Future<List<FinderMatch>> resolveFinder(Finder finder);

  /// Tap the widget represented by a Finder Match from the current Step.
  Future<void> performTap(FinderMatch match);

  /// Clear text in the widget represented by a Finder Match.
  ///
  /// Args:
  /// `match` is the target produced by the Step's Finder resolution.
  ///
  /// The runner calls this once before entering the Scenario `type` text.
  Future<void> clearText(FinderMatch match);

  /// Enter text in the widget represented by a Finder Match.
  ///
  /// Args:
  /// `match` is the target produced by the Step's Finder resolution.
  /// `text` is the text fragment to enter. The Scenario runner sends one
  /// character at a time for `type` actions.
  Future<void> enterText(FinderMatch match, String text);

  /// Perform a drag gesture using Flutter Pilot scroll delta semantics.
  ///
  /// Args:
  /// `match` is an optional scroll target. When omitted, implementation support
  /// depends on the active Runtime Adapter implementation.
  /// `deltaX` and `deltaY` are logical-pixel drag deltas.
  Future<void> performScroll({
    FinderMatch? match,
    required double deltaX,
    required double deltaY,
  });

  /// Capture one screenshot image from the current Runtime Target.
  Future<ScreenshotCapture> captureScreenshot();

  /// Capture structured UI state for programmatic and agent consumption.
  Future<SnapshotCapture> captureSnapshot();

  /// Capture raw or near-raw Flutter widget hierarchy data.
  Future<WidgetTreeCapture> captureWidgetTree();

  /// Collect structured runtime logs, including runtime errors when available.
  Future<LogsCapture> collectLogs();
}

/// Widget result produced by resolving a Finder during one Step.
///
/// The `id` is an opaque Runtime Adapter reference. The runner may record it
/// and pass the `FinderMatch` back to the adapter, but must not parse the value
/// or assume it is stable after the current Step action.
class FinderMatch {
  const FinderMatch({
    required this.id,
    this.debugLabel,
    this.text,
    this.key,
    this.type,
    this.bounds,
  });

  final String id;
  final String? debugLabel;
  final String? text;
  final String? key;
  final String? type;
  final WidgetBounds? bounds;
}

/// Logical-pixel rectangle for a matched widget in the Flutter view.
///
/// Bounds are optional because each Runtime Adapter must confirm whether this
/// data is available and which coordinate space it uses.
class WidgetBounds {
  const WidgetBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Screenshot bytes captured from the Runtime Target.
///
/// `bytes` contains exactly one image. The adapter should prefer PNG and set
/// `mimeType` accordingly, while the contract keeps the MIME type explicit for
/// future formats.
class ScreenshotCapture {
  const ScreenshotCapture({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Decoded structured Snapshot data from the Runtime Target.
class SnapshotCapture {
  const SnapshotCapture({required this.data});

  final Object data;
}

/// Decoded raw or near-raw Widget Tree data from the Runtime Target.
class WidgetTreeCapture {
  const WidgetTreeCapture({required this.data});

  final Object data;
}

/// Decoded structured Logs data from the Runtime Target.
///
/// Runtime errors are represented inside this data when the runtime bridge
/// exposes them.
class LogsCapture {
  const LogsCapture({required this.data});

  final Object data;
}

/// Runtime operation names used when adapter calls fail.
///
/// The enum keeps failure reporting stable and lets runner/report code group
/// failures without comparing string literals.
enum RuntimeOperation {
  waitForEndOfFrame,
  resolveFinder,
  performTap,
  clearText,
  enterText,
  performScroll,
  captureScreenshot,
  captureSnapshot,
  captureWidgetTree,
  collectLogs,
  initialize,
  dispose,
}

/// Failure raised when a Runtime Adapter operation cannot complete.
///
/// `message` is the normalized Flutter Pilot error. `cause` and `rawOutput`
/// preserve lower-level details such as an API exception, CLI stderr, or raw
/// JSON for debug artifacts without making those details the stable user-facing
/// contract.
class RuntimeOperationException implements Exception {
  const RuntimeOperationException({
    required this.operation,
    required this.message,
    this.cause,
    this.rawOutput,
  });

  final RuntimeOperation operation;
  final String message;
  final Object? cause;
  final Object? rawOutput;

  @override
  String toString() {
    return 'RuntimeOperationException(${operation.name}): $message';
  }
}
