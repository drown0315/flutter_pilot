/// Renders Target App Launch Progress before Scenario Step progress begins.
///
/// The renderer is intentionally plain for the first launch-progress slice:
/// it writes deterministic stderr lines that explain Flutter Pilot is launching
/// the Target App Package and waiting for a Runtime Target.
library;

import 'dart:io';

/// Clock function used to compute elapsed launch time in renderer tests.
typedef TargetAppLaunchClock = DateTime Function();

/// Progress event emitted while Flutter Pilot launches the Target App Package.
sealed class TargetAppLaunchProgressEvent {
  /// Creates a launch progress event with the launch start time.
  const TargetAppLaunchProgressEvent({required this.startedAt});

  /// Time when Target App launch began.
  final DateTime startedAt;
}

/// Event emitted immediately before Flutter Pilot starts `flutter run`.
class TargetAppLaunchStartedEvent extends TargetAppLaunchProgressEvent {
  /// Creates a launch-started event.
  const TargetAppLaunchStartedEvent({required super.startedAt});
}

/// Event emitted after Flutter Pilot has discovered the Runtime Target.
class TargetAppLaunchSucceededEvent extends TargetAppLaunchProgressEvent {
  /// Creates a launch-succeeded event.
  const TargetAppLaunchSucceededEvent({
    required super.startedAt,
    required this.finishedAt,
  });

  /// Time when the Runtime Target became available.
  final DateTime finishedAt;
}

/// Plain-text Target App Launch Progress renderer.
class TargetAppLaunchProgressRenderer {
  /// Creates a renderer that writes launch progress to `sink`.
  ///
  /// `clock` is used only when rendering an in-progress event, so tests can
  /// verify elapsed launch time without waiting in real time.
  TargetAppLaunchProgressRenderer({
    required this.sink,
    TargetAppLaunchClock? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Destination for human-readable launch progress, normally stderr.
  final IOSink sink;

  final TargetAppLaunchClock _clock;
  bool _headerWritten = false;

  /// Render one launch progress event as deterministic plain text.
  void render(TargetAppLaunchProgressEvent event) {
    _writeHeader();
    switch (event) {
      case TargetAppLaunchStartedEvent():
        sink.writeln(
          'Launching Target App Package... elapsed '
          '${_formatElapsed(_clock().difference(event.startedAt))}',
        );
      case TargetAppLaunchSucceededEvent(:final DateTime finishedAt):
        sink.writeln(
          'Target App launched in '
          '${_formatElapsed(finishedAt.difference(event.startedAt))}',
        );
    }
  }

  void _writeHeader() {
    if (_headerWritten) {
      return;
    }
    sink.writeln('> Target App Launch');
    _headerWritten = true;
  }

  String _formatElapsed(Duration duration) {
    final int seconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    return '${seconds}s';
  }
}
