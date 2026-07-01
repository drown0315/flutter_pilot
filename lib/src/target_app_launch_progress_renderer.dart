/// Renders Target App Launch Progress before Scenario Step progress begins.
///
/// The renderer is intentionally plain for the first launch-progress slice:
/// it writes deterministic stderr lines that explain Flutter Pilot is launching
/// the Target App Package and waiting for a Runtime Target.
library;

import 'dart:io';

import 'target_device.dart';

/// Clock function used to compute elapsed launch time in renderer tests.
typedef TargetAppLaunchClock = DateTime Function();

/// Launch choices displayed before Flutter Pilot waits for the Runtime Target.
///
/// The object contains only user-facing launch metadata. It does not control
/// process startup or Target Device resolution.
class TargetAppLaunchChoices {
  /// Creates display metadata for one Target App launch.
  const TargetAppLaunchChoices({
    this.targetDevice,
    this.selectionReason,
    this.flavor,
    this.target,
  });

  /// Resolved Target Device, or `null` when Flutter chooses its default.
  final TargetDevice? targetDevice;

  /// Reason explaining how `targetDevice` was selected.
  final TargetDeviceSelectionReason? selectionReason;

  /// Flutter flavor passed to `flutter run --flavor`, when provided.
  final String? flavor;

  /// Flutter entrypoint passed to `flutter run --target`, when provided.
  final String? target;
}

/// User-facing reason for Target Device selection.
sealed class TargetDeviceSelectionReason {
  /// Creates a Target Device selection reason.
  const TargetDeviceSelectionReason();

  /// Creates a reason for user-provided `--device` selection.
  const factory TargetDeviceSelectionReason.explicit({
    required String selector,
  }) = ExplicitTargetDeviceSelectionReason;

  /// Creates a reason for Scenario Recording-driven automatic selection.
  const factory TargetDeviceSelectionReason.autoSelectedForRecording() =
      AutoSelectedForRecordingTargetDeviceSelectionReason;
}

/// Reason used when the user supplied `--device`.
class ExplicitTargetDeviceSelectionReason extends TargetDeviceSelectionReason {
  /// Creates an explicit Target Device selection reason.
  const ExplicitTargetDeviceSelectionReason({required this.selector});

  /// Original `--device` selector provided by the user.
  final String selector;
}

/// Reason used when Scenario Recording selects the only recordable device.
class AutoSelectedForRecordingTargetDeviceSelectionReason
    extends TargetDeviceSelectionReason {
  /// Creates a Scenario Recording auto-selection reason.
  const AutoSelectedForRecordingTargetDeviceSelectionReason();
}

/// Progress event emitted while Flutter Pilot launches the Target App Package.
sealed class TargetAppLaunchProgressEvent {
  /// Creates a launch progress event with the launch start time.
  const TargetAppLaunchProgressEvent({
    required this.startedAt,
    this.choices = const TargetAppLaunchChoices(),
  });

  /// Time when Target App launch began.
  final DateTime startedAt;

  /// User-facing launch choices known before app startup.
  final TargetAppLaunchChoices choices;
}

/// Event emitted immediately before Flutter Pilot starts `flutter run`.
class TargetAppLaunchStartedEvent extends TargetAppLaunchProgressEvent {
  /// Creates a launch-started event.
  const TargetAppLaunchStartedEvent({required super.startedAt, super.choices});
}

/// Event emitted after Flutter Pilot has discovered the Runtime Target.
class TargetAppLaunchSucceededEvent extends TargetAppLaunchProgressEvent {
  /// Creates a launch-succeeded event.
  const TargetAppLaunchSucceededEvent({
    required super.startedAt,
    required this.finishedAt,
    super.choices,
  });

  /// Time when the Runtime Target became available.
  final DateTime finishedAt;
}

/// Event emitted when the Target App launch cannot provide a Runtime Target.
class TargetAppLaunchFailedEvent extends TargetAppLaunchProgressEvent {
  /// Creates a launch-failed event.
  const TargetAppLaunchFailedEvent({
    required super.startedAt,
    required this.failedAt,
    required this.message,
    this.stderrLines = const <String>[],
    super.choices,
  });

  /// Time when Flutter Pilot observed the launch failure.
  final DateTime failedAt;

  /// Human-readable failure message.
  final String message;

  /// Buffered Flutter stderr tail from the launcher.
  final List<String> stderrLines;
}

/// Target App Launch Progress renderer for plain and interactive terminals.
class TargetAppLaunchProgressRenderer {
  /// Creates a renderer that writes launch progress to `sink`.
  ///
  /// `clock` is used only when rendering an in-progress event, so tests can
  /// verify elapsed launch time without waiting in real time.
  TargetAppLaunchProgressRenderer({
    required this.sink,
    this.interactive = false,
    TargetAppLaunchClock? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Destination for human-readable launch progress, normally stderr.
  final IOSink sink;

  /// Whether launch progress should redraw a compact in-place panel.
  final bool interactive;

  final TargetAppLaunchClock _clock;
  bool _headerWritten = false;
  int _lastInteractiveLineCount = 0;

  /// Render one launch progress event as deterministic plain text.
  void render(TargetAppLaunchProgressEvent event) {
    if (interactive) {
      _renderInteractive(event);
      return;
    }
    _writeHeader();
    switch (event) {
      case TargetAppLaunchStartedEvent():
        _writeChoices(event.choices);
        sink.writeln(
          'Launching Target App Package... elapsed '
          '${_formatElapsed(_clock().difference(event.startedAt))}',
        );
      case TargetAppLaunchSucceededEvent(:final DateTime finishedAt):
        sink.writeln(
          'Target App launched in '
          '${_formatElapsed(finishedAt.difference(event.startedAt))}',
        );
      case TargetAppLaunchFailedEvent(
        :final DateTime failedAt,
        :final String message,
        :final List<String> stderrLines,
      ):
        sink.writeln(
          'Target App launch failed after '
          '${_formatElapsed(failedAt.difference(event.startedAt))}',
        );
        sink.writeln(message);
        if (stderrLines.isNotEmpty) {
          sink.writeln('Flutter stderr tail:');
          for (final String line in stderrLines) {
            sink.writeln(line);
          }
        }
    }
  }

  void _renderInteractive(TargetAppLaunchProgressEvent event) {
    switch (event) {
      case TargetAppLaunchStartedEvent():
        _redrawInteractiveBlock(<String>[
          '> Target App Launch',
          ..._choiceLines(event.choices),
          '⏳ Waiting for Runtime Target... elapsed '
              '${_formatElapsed(_clock().difference(event.startedAt))}',
        ]);
      case TargetAppLaunchSucceededEvent(:final DateTime finishedAt):
        _clearInteractiveBlock();
        _writeHeader();
        sink.writeln(
          'Target App launched in '
          '${_formatElapsed(finishedAt.difference(event.startedAt))}',
        );
      case TargetAppLaunchFailedEvent(
        :final DateTime failedAt,
        :final String message,
        :final List<String> stderrLines,
      ):
        _clearInteractiveBlock();
        _writeHeader();
        sink.writeln(
          'Target App launch failed after '
          '${_formatElapsed(failedAt.difference(event.startedAt))}',
        );
        sink.writeln(message);
        if (stderrLines.isNotEmpty) {
          sink.writeln('Flutter stderr tail:');
          for (final String line in stderrLines) {
            sink.writeln(line);
          }
        }
    }
  }

  void _redrawInteractiveBlock(List<String> lines) {
    _clearInteractiveBlock();
    for (final String line in lines) {
      sink.writeln(line);
    }
    _lastInteractiveLineCount = lines.length;
  }

  void _clearInteractiveBlock() {
    if (_lastInteractiveLineCount == 0) {
      return;
    }
    sink.write('\u001b[${_lastInteractiveLineCount}A');
    sink.write('\u001b[J');
    _lastInteractiveLineCount = 0;
  }

  void _writeChoices(TargetAppLaunchChoices choices) {
    for (final String line in _choiceLines(choices)) {
      sink.writeln(line);
    }
  }

  List<String> _choiceLines(TargetAppLaunchChoices choices) {
    final List<String> lines = <String>[];
    final TargetDevice? targetDevice = choices.targetDevice;
    if (targetDevice != null) {
      lines.add(
        'Target Device: ${targetDevice.id} '
        '(${targetDevice.name}, ${targetDevice.targetPlatform}, '
        '${targetDevice.sdk})',
      );
    } else {
      lines.add('Target Device: Flutter default');
    }
    final TargetDeviceSelectionReason? selectionReason =
        choices.selectionReason;
    switch (selectionReason) {
      case ExplicitTargetDeviceSelectionReason(:final String selector):
        lines.add('Selection: --device $selector');
      case AutoSelectedForRecordingTargetDeviceSelectionReason():
        lines.add('Selection: auto-selected for recording');
      case null:
        break;
    }
    final String? flavor = choices.flavor;
    if (flavor != null) {
      lines.add('Flavor: $flavor');
    }
    final String? target = choices.target;
    if (target != null) {
      lines.add('Entrypoint: $target');
    }
    return lines;
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
