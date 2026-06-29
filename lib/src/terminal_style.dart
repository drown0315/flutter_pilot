/// ANSI and capability helpers for terminal rendering.
///
/// The helper keeps styling concerns separate from progress wording so the CLI
/// can choose plain or interactive output without changing Scenario behavior.
class TerminalStyle {
  TerminalStyle._();

  /// Wrap [text] in an ANSI color sequence when styling is enabled.
  static String color(
    String text,
    TerminalColor color, {
    required bool enabled,
  }) {
    if (!enabled) {
      return text;
    }
    return '\u001b[${color.code}m$text\u001b[0m';
  }

  /// Wrap [text] in bold when styling is enabled.
  static String bold(String text, {required bool enabled}) {
    return enabled ? '\u001b[1m$text\u001b[0m' : text;
  }

  /// Wrap [text] in dim styling when styling is enabled.
  static String dim(String text, {required bool enabled}) {
    return enabled ? '\u001b[2m$text\u001b[0m' : text;
  }

  /// Remove ANSI escape sequences from [text].
  static String stripAnsi(String text) {
    return text.replaceAll(RegExp(r'\u001b\[[0-9;]*m'), '');
  }
}

/// ANSI colors used by terminal progress output.
enum TerminalColor {
  green(32),
  red(31),
  cyan(36);

  const TerminalColor(this.code);

  final int code;
}
