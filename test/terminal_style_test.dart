import 'package:flutter_pilot/flutter_pilot.dart';
import 'package:test/test.dart';

/// Verifies ANSI styling helpers used by terminal progress rendering.
void main() {
  test('colors, bolds, dims, and strips ANSI text', () {
    final String colored = TerminalStyle.color(
      'ok',
      TerminalColor.green,
      enabled: true,
    );
    final String bold = TerminalStyle.bold('title', enabled: true);
    final String dim = TerminalStyle.dim('hint', enabled: true);

    expect(colored, contains('\u001b['));
    expect(bold, contains('\u001b['));
    expect(dim, contains('\u001b['));
    expect(TerminalStyle.stripAnsi(colored), 'ok');
    expect(TerminalStyle.stripAnsi(bold), 'title');
    expect(TerminalStyle.stripAnsi(dim), 'hint');
  });

  test('leaves text plain when styling is disabled', () {
    expect(
      TerminalStyle.color('ok', TerminalColor.green, enabled: false),
      'ok',
    );
    expect(TerminalStyle.bold('title', enabled: false), 'title');
    expect(TerminalStyle.dim('hint', enabled: false), 'hint');
  });
}
