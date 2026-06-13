/// Reduces raw runtime diagnostics into compact agent-facing summaries.
///
/// The reducer accepts decoded JSON-compatible payloads from Snapshot, Widget
/// Tree, and Logs captures. The first version keeps the output intentionally
/// small by extracting stable user-facing fields and dropping implementation
/// details such as render object names, constraints, diagnostics dumps, and
/// opaque runtime identifiers.
///
/// Example:
/// A Snapshot node with `type: button`, `text: Pay now`, and `enabled: true`
/// becomes one `DiagnosticWidgetSummary`, while fields such as `renderObject`
/// and `debugCreator` are ignored.
class DiagnosticReducer {
  DiagnosticReducer._();

  /// Convert raw diagnostic payloads into a compact summary.
  ///
  /// This method:
  /// 1. walks every map and list inside the provided payloads
  /// 2. extracts stable UI facts from Snapshot and Widget Tree nodes
  /// 3. extracts useful log messages, runtime failures, and package stack frames
  /// 4. returns empty lists for categories that are absent from the inputs
  ///
  /// Args:
  /// `snapshot` is semantic UI state from the Runtime Adapter. Missing or
  /// non-map/list data is ignored.
  /// `widgetTree` is raw Flutter hierarchy data. It is optional because Widget
  /// Tree capture is disabled by default.
  /// `logs` is structured runtime log data, including runtime errors when the
  /// adapter exposes them.
  ///
  /// Returns:
  /// A stable summary that keeps visible text, interactive widgets,
  /// route-like context, runtime failures, log messages, and likely suspects.
  /// Non-map/list payloads are ignored rather than treated as malformed input.
  static DiagnosticSummary reduce({
    Object? snapshot,
    Object? widgetTree,
    Object? logs,
  }) {
    final _DiagnosticAccumulator accumulator = _DiagnosticAccumulator();
    _visitDiagnosticNode(snapshot, accumulator);
    _visitDiagnosticNode(widgetTree, accumulator);
    _visitDiagnosticNode(logs, accumulator);
    return accumulator.toSummary();
  }

  /// Visit one decoded JSON node and collect stable diagnostic fields.
  ///
  /// Maps are inspected as candidate diagnostic records before their values are
  /// visited. Lists are traversed in order. Scalar values are ignored because
  /// the reducer needs field names such as `text`, `route`, or `message` to
  /// decide whether a value is useful.
  static void _visitDiagnosticNode(
    Object? node,
    _DiagnosticAccumulator accumulator,
  ) {
    if (node is Map) {
      accumulator.addNode(node);
      for (final Object? value in node.values) {
        _visitDiagnosticNode(value, accumulator);
      }
      return;
    }

    if (node is List) {
      for (final Object? value in node) {
        _visitDiagnosticNode(value, accumulator);
      }
    }
  }
}

/// Agent-facing summary extracted from raw runtime diagnostics.
///
/// It contains the small set of UI and runtime facts most useful for debugging:
/// visible text, interactive widgets, route-like context, runtime failures, log
/// messages, and likely suspect widget types or labels.
///
/// Example:
/// A failed checkout run can report visible text such as `Email`, an
/// interactive `button` labeled `Pay now`, route `/checkout`, and a runtime
/// failure from Flutter logs without including raw render tree details.
class DiagnosticSummary {
  const DiagnosticSummary({
    required this.visibleText,
    required this.interactiveWidgets,
    required this.routes,
    required this.runtimeFailures,
    required this.logs,
    required this.likelySuspects,
  });

  /// User-facing strings visible in the captured UI state.
  ///
  /// Values come from fields such as `visibleText`, `text`, and `label`.
  /// Hidden nodes with `visible: false` are ignored.
  final List<String> visibleText;

  /// Compact descriptions of widgets that a user can act on.
  ///
  /// The current rules recognize semantic types such as `button`,
  /// `textField`, `checkbox`, `switch`, `slider`, and `scrollable`, plus
  /// matching app-specific widget type names.
  final List<DiagnosticWidgetSummary> interactiveWidgets;

  /// Route-like context found in Snapshot or Widget Tree payloads.
  ///
  /// Values come from `route` or `routeName` fields and preserve first-seen
  /// order without duplicates.
  final List<String> routes;

  /// Runtime failures extracted from Logs payloads.
  ///
  /// Values come from error-level log entries, entries with an `error` field,
  /// or messages that look like Flutter failures such as exceptions or layout
  /// overflows.
  final List<String> runtimeFailures;

  /// Useful non-debug log messages.
  ///
  /// `debug` and `trace` messages are dropped to keep the summary focused.
  final List<String> logs;

  /// Likely source locations or app widget names related to the state.
  ///
  /// Values come from app-level `widgetType` names and package stack frames.
  final List<String> likelySuspects;

  /// Convert the summary into JSON-compatible output for reports and CLI use.
  ///
  /// `visibleText` and `interactiveWidgets` are always present so consumers can
  /// rely on those keys. Other categories are omitted when empty to keep
  /// `run_report.json` compact.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'visibleText': visibleText,
      'interactiveWidgets': <Object?>[
        for (final DiagnosticWidgetSummary widget in interactiveWidgets)
          widget.toJson(),
      ],
      if (routes.isNotEmpty) 'routes': routes,
      if (runtimeFailures.isNotEmpty) 'runtimeFailures': runtimeFailures,
      if (logs.isNotEmpty) 'logs': logs,
      if (likelySuspects.isNotEmpty) 'likelySuspects': likelySuspects,
    };
  }
}

/// Compact description of an interactive widget in diagnostic output.
///
/// The summary keeps user-facing fields only. Opaque runtime ids and noisy
/// implementation details are intentionally excluded.
///
/// Example:
/// A raw text field node with `type: textField`, `label: Email`, `value:
/// bad@example.com`, and `enabled: true` becomes a widget summary with those
/// four user-facing fields.
class DiagnosticWidgetSummary {
  const DiagnosticWidgetSummary({
    required this.type,
    this.label,
    this.text,
    this.enabled,
  });

  /// Semantic Snapshot type or app widget type that identifies the control.
  final String type;

  /// User-facing label associated with the control, when available.
  final String? label;

  /// Visible text or current value associated with the control, when available.
  final String? text;

  /// Whether the control is enabled, when the Runtime Adapter exposes it.
  final bool? enabled;

  /// Convert this widget summary into JSON-compatible output.
  ///
  /// Missing optional fields are omitted so the object only contains facts the
  /// runtime actually exposed.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type,
      if (label != null) 'label': label,
      if (text != null) 'text': text,
      if (enabled != null) 'enabled': enabled,
    };
  }
}

class _DiagnosticAccumulator {
  final List<String> _visibleText = <String>[];
  final List<DiagnosticWidgetSummary> _interactiveWidgets =
      <DiagnosticWidgetSummary>[];
  final List<String> _routes = <String>[];
  final List<String> _runtimeFailures = <String>[];
  final List<String> _logs = <String>[];
  final List<String> _likelySuspects = <String>[];

  /// Inspect one JSON object and apply every extraction rule to it.
  ///
  /// A single node can contribute to several summary categories. For example,
  /// a visible enabled button can add visible text and one interactive widget.
  void addNode(Map<Object?, Object?> node) {
    _addRoute(node);
    _addVisibleText(node);
    _addInteractiveWidget(node);
    _addLikelySuspect(node);
    _addLogOrFailure(node);
    _addStackSuspects(node);
  }

  /// Build the immutable summary after all diagnostic payloads are visited.
  DiagnosticSummary toSummary() {
    return DiagnosticSummary(
      visibleText: List<String>.unmodifiable(_visibleText),
      interactiveWidgets: List<DiagnosticWidgetSummary>.unmodifiable(
        _interactiveWidgets,
      ),
      routes: List<String>.unmodifiable(_routes),
      runtimeFailures: List<String>.unmodifiable(_runtimeFailures),
      logs: List<String>.unmodifiable(_logs),
      likelySuspects: List<String>.unmodifiable(_likelySuspects),
    );
  }

  /// Add route-like context from a Snapshot or Widget Tree node.
  ///
  /// `route` covers semantic Snapshot payloads, while `routeName` covers raw
  /// Widget Tree payloads. Missing or empty values are ignored.
  void _addRoute(Map<Object?, Object?> node) {
    final String? route =
        _stringValue(node, 'route') ?? _stringValue(node, 'routeName');
    if (route == null || route.isEmpty) {
      return;
    }
    _addUnique(_routes, route);
  }

  /// Add user-facing text from a visible diagnostic node.
  ///
  /// The reducer accepts both aggregate `visibleText: [...]` payloads and
  /// per-node `text` or `label` fields. It intentionally does not add `value`
  /// here because field values are more useful inside `interactiveWidgets`.
  void _addVisibleText(Map<Object?, Object?> node) {
    final bool visible = _boolValue(node, 'visible') ?? true;
    if (!visible) {
      return;
    }

    _addStringListValues(node, 'visibleText', _visibleText);
    final String? label = _stringValue(node, 'label');
    final String? text = _stringValue(node, 'text');
    for (final String? candidate in <String?>[text, label]) {
      if (candidate != null && candidate.isNotEmpty) {
        _addUnique(_visibleText, candidate);
      }
    }
  }

  /// Add one compact widget summary when the node represents an interactive UI.
  ///
  /// The reducer keeps `type`, `label`, current `value`/`text`, and `enabled`
  /// only. Runtime ids, render objects, constraints, and diagnostics dumps are
  /// ignored.
  void _addInteractiveWidget(Map<Object?, Object?> node) {
    final String? type =
        _stringValue(node, 'type') ?? _stringValue(node, 'widgetType');
    if (type == null || !_isInteractiveType(type)) {
      return;
    }

    final String? label = _stringValue(node, 'label');
    final String? text =
        _stringValue(node, 'value') ?? _stringValue(node, 'text');
    _interactiveWidgets.add(
      DiagnosticWidgetSummary(
        type: type,
        label: label,
        text: text,
        enabled: _boolValue(node, 'enabled'),
      ),
    );
  }

  /// Add an app-level widget type as a possible source suspect.
  ///
  /// Framework container widgets such as `Scaffold` and private or render
  /// implementation types are filtered out because they rarely point an agent
  /// to useful app code.
  void _addLikelySuspect(Map<Object?, Object?> node) {
    final String? widgetType = _stringValue(node, 'widgetType');
    if (widgetType == null || !_isLikelySuspect(widgetType)) {
      return;
    }
    _addUnique(_likelySuspects, widgetType);
  }

  /// Add a log message or runtime failure from one log-like object.
  ///
  /// Entries with an `error` field combine `message` and `error` into one
  /// failure. Error/fatal levels and Flutter-looking failure messages also
  /// become runtime failures. Debug and trace messages are dropped.
  void _addLogOrFailure(Map<Object?, Object?> node) {
    final String? message = _stringValue(node, 'message');
    final String? error = _stringValue(node, 'error');
    final String? level = _stringValue(node, 'level')?.toLowerCase();
    if (message == null || message.isEmpty) {
      return;
    }

    if (error != null && error.isNotEmpty) {
      _addUnique(_runtimeFailures, '$message: $error');
      return;
    }

    if (level == 'error' || level == 'fatal' || _looksLikeFailure(message)) {
      _addUnique(_runtimeFailures, message);
      return;
    }

    if (level != 'debug' && level != 'trace') {
      _addUnique(_logs, message);
    }
  }

  /// Add package source locations from a stack trace.
  ///
  /// The returned suspects are compact `package:...` frame locations. The raw
  /// stack trace text is not copied into the summary.
  void _addStackSuspects(Map<Object?, Object?> node) {
    final String? stackTrace = _stringValue(node, 'stackTrace');
    if (stackTrace == null || stackTrace.isEmpty) {
      return;
    }

    final RegExp packageFrame = RegExp(r'package:[^\s)]+');
    for (final RegExpMatch match in packageFrame.allMatches(stackTrace)) {
      final String? frame = match.group(0);
      if (frame != null) {
        _addUnique(_likelySuspects, frame);
      }
    }
  }

  /// Return whether a type name represents an interactive UI target.
  ///
  /// Exact lowercase semantic types cover common Snapshot roles. Substring
  /// matches keep app-specific names such as `PrimaryButton` or
  /// `EmailTextField` useful before the adapter exposes stronger typed data.
  bool _isInteractiveType(String type) {
    final String normalized = type.toLowerCase();
    return normalized == 'button' ||
        normalized == 'textfield' ||
        normalized == 'checkbox' ||
        normalized == 'switch' ||
        normalized == 'slider' ||
        normalized == 'scrollable' ||
        normalized.contains('button') ||
        normalized.contains('textfield') ||
        normalized.contains('gesture');
  }

  /// Return whether a Widget Tree type is useful as a likely suspect.
  ///
  /// Common framework containers are skipped, private implementation classes
  /// are skipped, and render object names are skipped. Other widget type names
  /// are kept as possible app-level source hints.
  bool _isLikelySuspect(String widgetType) {
    const Set<String> frameworkWidgets = <String>{
      'MaterialApp',
      'Navigator',
      'Scaffold',
      'Column',
      'Row',
      'Padding',
      'Center',
      'Container',
      'Text',
    };
    return !frameworkWidgets.contains(widgetType) &&
        !widgetType.startsWith('_') &&
        !widgetType.startsWith('Render');
  }

  /// Return whether a log message should be treated as a runtime failure.
  ///
  /// This catches failure-shaped messages in `errors` arrays that may not carry
  /// an explicit level, such as Flutter layout overflow messages.
  bool _looksLikeFailure(String message) {
    final String normalized = message.toLowerCase();
    return normalized.contains('exception') ||
        normalized.contains('error') ||
        normalized.contains('failed') ||
        normalized.contains('overflowed');
  }

  /// Return a trimmed string field from a JSON-like object.
  ///
  /// Non-string, missing, and null values return `null` because the reducer does
  /// not coerce numbers or booleans into user-facing diagnostic text.
  String? _stringValue(Map<Object?, Object?> node, String key) {
    final Object? value = node[key];
    return value is String ? value.trim() : null;
  }

  /// Return a boolean field from a JSON-like object.
  ///
  /// Non-boolean, missing, and null values return `null`.
  bool? _boolValue(Map<Object?, Object?> node, String key) {
    final Object? value = node[key];
    return value is bool ? value : null;
  }

  /// Add string items from a list-valued field to a target summary list.
  ///
  /// Missing fields, non-list values, non-string items, and blank strings are
  /// ignored. Duplicate strings are suppressed by `_addUnique`.
  void _addStringListValues(
    Map<Object?, Object?> node,
    String key,
    List<String> target,
  ) {
    final Object? value = node[key];
    if (value is! List) {
      return;
    }

    for (final Object? item in value) {
      if (item is String && item.trim().isNotEmpty) {
        _addUnique(target, item.trim());
      }
    }
  }

  /// Add a string once while preserving first-seen order.
  void _addUnique(List<String> values, String value) {
    if (!values.contains(value)) {
      values.add(value);
    }
  }
}
