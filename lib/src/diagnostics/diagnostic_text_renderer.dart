import 'diagnostic_reducer.dart';
import '../execution/scenario_runner.dart';

/// Renders printed diagnostics as terminal-friendly text.
///
/// The renderer is used when `test --print` is called without `--json`. It keeps
/// raw diagnostic payloads in `run_report.json`, but shows a compact view in the
/// terminal:
/// - Snapshot prints visible text and interactive widgets from the reducer
/// - Widget Tree prints a filtered hierarchy of useful widget types
/// - Errors prints runtime failures or a no-error message
///
/// Example:
/// A raw Widget Tree containing `_FocusInheritedScope`, `Semantics`, and
/// `SmokeApp` prints `SmokeApp` while omitting the framework wrappers.
class DiagnosticTextRenderer {
  DiagnosticTextRenderer._();

  /// Render diagnostics captured after a stopped Step.
  ///
  /// Args:
  /// `report` contains raw `printedDiagnostics` and the reduced
  /// `diagnosticSummary` produced from those raw payloads.
  ///
  /// Returns:
  /// Human-readable terminal text. If no diagnostics were printed, this returns
  /// an empty string so the CLI can skip diagnostic output entirely.
  static String render(ScenarioRunReport report) {
    if (report.printedDiagnostics.isEmpty) {
      return '';
    }

    final StringBuffer buffer = StringBuffer('Diagnostics\n');
    final DiagnosticSummary? summary = report.diagnosticSummary;
    for (final PrintedDiagnostic diagnostic in report.printedDiagnostics) {
      switch (diagnostic.type) {
        case PrintDiagnostic.snapshot:
          _writeSnapshot(buffer, summary);
        case PrintDiagnostic.widgetTree:
          _writeWidgetTree(buffer, diagnostic.data);
        case PrintDiagnostic.errors:
          _writeErrors(buffer, summary);
      }
    }
    buffer.writeln('Raw diagnostics are stored in run_report.json.');
    return buffer.toString().trimRight();
  }

  /// Write the Snapshot section from the reduced diagnostic summary.
  static void _writeSnapshot(StringBuffer buffer, DiagnosticSummary? summary) {
    buffer.writeln();
    buffer.writeln('Snapshot');
    _writeStringList(buffer, 'Visible text', summary?.visibleText ?? const []);
    if (summary == null || summary.interactiveWidgets.isEmpty) {
      buffer.writeln('Interactive widgets: none');
      return;
    }

    buffer.writeln('Interactive widgets:');
    for (final DiagnosticWidgetSummary widget in summary.interactiveWidgets) {
      buffer.writeln('- ${_formatWidgetSummary(widget)}');
    }
  }

  /// Write the Widget Tree section as a filtered hierarchy.
  static void _writeWidgetTree(StringBuffer buffer, Object data) {
    buffer.writeln();
    buffer.writeln('Widget Tree');
    final _WidgetTreeRenderState state = _WidgetTreeRenderState();
    _writeWidgetNode(buffer, data, state, 0);
    if (state.visibleNodes == 0) {
      buffer.writeln('(no useful widget nodes found)');
    }
    if (state.omittedNodes > 0) {
      buffer.writeln('... ${state.omittedNodes} framework/noisy nodes omitted');
    }
  }

  /// Write one useful Widget Tree node and visit its children.
  static void _writeWidgetNode(
    StringBuffer buffer,
    Object? node,
    _WidgetTreeRenderState state,
    int visibleDepth,
  ) {
    if (node is List) {
      for (final Object? child in node) {
        _writeWidgetNode(buffer, child, state, visibleDepth);
      }
      return;
    }

    if (node is! Map) {
      return;
    }

    final String? widgetType = _stringValue(node, 'widgetType');
    final bool useful = widgetType != null && _isUsefulWidgetType(widgetType);
    final int childDepth = useful ? visibleDepth + 1 : visibleDepth;
    if (useful) {
      buffer.writeln('${'  ' * visibleDepth}- ${_formatWidgetNode(node)}');
      state.visibleNodes++;
    } else if (widgetType != null) {
      state.omittedNodes++;
    }

    final Object? children = node['children'];
    if (children != null) {
      _writeWidgetNode(buffer, children, state, childDepth);
    }
  }

  /// Write runtime failures from the reduced diagnostic summary.
  static void _writeErrors(StringBuffer buffer, DiagnosticSummary? summary) {
    buffer.writeln();
    buffer.writeln('Errors');
    final List<String> failures = summary?.runtimeFailures ?? const <String>[];
    if (failures.isEmpty || _onlyNoErrorMessage(failures)) {
      buffer.writeln('No runtime errors found.');
      return;
    }
    for (final String failure in failures) {
      buffer.writeln('- $failure');
    }
  }

  /// Write one titled string list, or `none` when the list is empty.
  static void _writeStringList(
    StringBuffer buffer,
    String title,
    List<String> values,
  ) {
    if (values.isEmpty) {
      buffer.writeln('$title: none');
      return;
    }
    buffer.writeln('$title:');
    for (final String value in values) {
      buffer.writeln('- $value');
    }
  }

  /// Format a reduced interactive widget for terminal output.
  static String _formatWidgetSummary(DiagnosticWidgetSummary widget) {
    final List<String> parts = <String>[widget.type];
    if (widget.label != null) {
      parts.add('"${widget.label}"');
    }
    if (widget.text != null && widget.text != widget.label) {
      parts.add('value="${widget.text}"');
    }
    if (widget.enabled != null) {
      parts.add(widget.enabled! ? 'enabled' : 'disabled');
    }
    return parts.join(' ');
  }

  /// Format one raw Widget Tree node for terminal output.
  static String _formatWidgetNode(Map<Object?, Object?> node) {
    final String type = _stringValue(node, 'widgetType') ?? 'unknown';
    final String? label = _stringValue(node, 'label');
    final String? text = _stringValue(node, 'text');
    final String? value = _stringValue(node, 'value');
    final bool? enabled = _boolValue(node, 'enabled');
    final List<String> details = <String>[];
    if (label != null) {
      details.add('"$label"');
    }
    if (text != null && text != label) {
      details.add('"$text"');
    }
    if (value != null) {
      details.add('value="$value"');
    }
    if (enabled != null) {
      details.add(enabled ? 'enabled' : 'disabled');
    }
    return details.isEmpty ? type : '$type ${details.join(' ')}';
  }

  /// Return whether a Widget Tree node should be visible in terminal output.
  static bool _isUsefulWidgetType(String widgetType) {
    const Set<String> noisyTypes = <String>{
      'RootWidget',
      'View',
      'RawView',
      'MaterialApp',
      'MediaQuery',
      'FocusTraversalGroup',
      'Focus',
      'Semantics',
      'Actions',
      'Shortcuts',
      'ScrollConfiguration',
      'HeroControllerScope',
      'WidgetsApp',
      'RootRestorationScope',
      'UnmanagedRestorationScope',
      'RestorationScope',
      'SharedAppData',
      'DefaultTextEditingShortcuts',
    };
    return widgetType.isNotEmpty &&
        !noisyTypes.contains(widgetType) &&
        !widgetType.startsWith('_') &&
        !widgetType.startsWith('Render') &&
        !widgetType.startsWith('NotificationListener<');
  }

  /// Return whether errors contain only the toolkit's no-error explanation.
  static bool _onlyNoErrorMessage(List<String> failures) {
    return failures.length == 1 &&
        failures.single.startsWith('No errors found');
  }

  /// Return a trimmed string field from a JSON-like object.
  static String? _stringValue(Map<Object?, Object?> node, String key) {
    final Object? value = node[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Return a boolean field from a JSON-like object.
  static bool? _boolValue(Map<Object?, Object?> node, String key) {
    final Object? value = node[key];
    return value is bool ? value : null;
  }
}

class _WidgetTreeRenderState {
  int visibleNodes = 0;
  int omittedNodes = 0;
}
