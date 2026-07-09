import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'pilot_runtime_client.dart';

/// Resolves Flutter Pilot Finders against the live app-side Element tree.
///
/// The resolver treats `byType` as a Semantic Node Type rather than a Dart
/// widget class. It returns every visible Finder Match and leaves strict
/// cardinality decisions to the Flutter Pilot runner.
class PilotRuntimeFinderResolver {
  PilotRuntimeFinderResolver._();

  /// Resolve one Finder against the current root Element.
  ///
  /// Args:
  /// - `byText`: Exact visible text constraint.
  /// - `byType`: Semantic Node Type constraint. Multiple constraints use AND
  ///   semantics.
  /// - `byKey`: `ValueKey<String>` constraint.
  ///
  /// Returns a VM Service response object with a `matches` list. Each match
  /// contains an opaque Runtime Handle and available diagnostics.
  static Map<String, Object?> resolve({
    String? byText,
    String? byType,
    String? byKey,
    String? byWidget,
  }) {
    final Element? rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return <String, Object?>{'matches': <Object?>[]};
    }

    final List<PilotRuntimeFinderMatch> matches = <PilotRuntimeFinderMatch>[];
    _visitVisibleElements(rootElement, (Element element) {
      final _FinderEvidence evidence = _evidenceFor(element);
      if (!_matchesRequest(
        byText: byText,
        byType: byType,
        byKey: byKey,
        byWidget: byWidget,
        evidence: evidence,
      )) {
        return;
      }
      matches.add(
        PilotRuntimeFinderMatch(
          handle: handleForElement(element),
          text: evidence.textForDiagnostics,
          semanticType: evidence.semanticType,
          key: evidence.valueKey,
          matchedWidgetType: evidence.widgetType,
          actionWidgetType: element.widget.runtimeType.toString(),
          bounds: _boundsFor(element),
        ),
      );
    });

    return <String, Object?>{
      'matches': <Object?>[
        for (final PilotRuntimeFinderMatch match in matches) match.toJson(),
      ],
    };
  }

  /// Return the opaque Runtime Handle used for one Element.
  static String handleForElement(Element element) {
    return 'element-${identityHashCode(element)}';
  }

  /// Find the currently visible Element represented by an opaque handle.
  ///
  /// Runtime Handles are only valid for immediate action after Finder
  /// resolution. The lookup traverses the current visible Element tree and
  /// returns `null` when the handle is stale or malformed.
  static Element? elementForHandle(String handle) {
    final Element? rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return null;
    }

    Element? match;
    _visitVisibleElements(rootElement, (Element element) {
      if (match == null && handleForElement(element) == handle) {
        match = element;
      }
    });
    return match;
  }

  /// Visit every currently visible Element in the app tree.
  ///
  /// Runtime action performers use this to preserve the same visible-target
  /// rules as Finder resolution when they need to locate related widgets, such
  /// as the primary scrollable for an untargeted Scroll Action.
  static void visitVisibleElements(void Function(Element element) visitor) {
    final Element? rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return;
    }
    _visitVisibleElements(rootElement, visitor);
  }

  static void _visitVisibleElements(
    Element element,
    void Function(Element element) visitor,
  ) {
    if (!_isVisible(element)) {
      return;
    }

    visitor(element);
    element.visitChildren((Element child) {
      _visitVisibleElements(child, visitor);
    });
  }

  static bool _matchesRequest({
    required String? byText,
    required String? byType,
    required String? byKey,
    required String? byWidget,
    required _FinderEvidence evidence,
  }) {
    final bool hasStructuralConstraint =
        byType != null || byKey != null || byWidget != null;
    final String? comparableText = hasStructuralConstraint
        ? evidence.textForDiagnostics
        : evidence.ownText;
    if (byText != null && comparableText != byText) {
      return false;
    }
    if (byType != null && evidence.semanticType != byType) {
      return false;
    }
    if (byKey != null && evidence.valueKey != byKey) {
      return false;
    }
    if (byWidget != null && evidence.widgetType != byWidget) {
      return false;
    }
    return byText != null ||
        byType != null ||
        byKey != null ||
        byWidget != null;
  }

  static _FinderEvidence _evidenceFor(Element element) {
    final String? ownText = _ownTextFor(element);
    final String? semanticType = _semanticTypeFor(element);
    final String? descendantText = _descendantTextFor(element);
    return _FinderEvidence(
      ownText: ownText,
      descendantText: descendantText,
      semanticType: semanticType,
      valueKey: _valueKeyFor(element),
      widgetType: element.widget.runtimeType.toString(),
    );
  }

  static String? _valueKeyFor(Element element) {
    final Key? key = element.widget.key;
    if (key is ValueKey<String>) {
      return key.value;
    }
    return null;
  }

  static String? _ownTextFor(Element element) {
    final Widget widget = element.widget;
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText && _hasAncestorWidget<Text>(element)) {
      return null;
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    return null;
  }

  static String? _descendantTextFor(Element element) {
    String? matchedText;
    element.visitChildren((Element child) {
      matchedText ??= _ownTextFor(child);
      matchedText ??= _descendantTextFor(child);
    });
    return matchedText;
  }

  static String? _semanticTypeFor(Element element) {
    final Widget widget = element.widget;
    if (widget is TextField) {
      return 'textField';
    }
    if (widget is EditableText) {
      if (_hasAncestorWidget<TextField>(element)) {
        return null;
      }
      return 'textField';
    }
    if (widget is ButtonStyleButton ||
        widget is IconButton ||
        widget is RawMaterialButton) {
      return 'button';
    }
    if (widget is Text || widget is RichText) {
      return 'text';
    }
    if (widget is Scrollable) {
      return 'scrollable';
    }
    if (widget is Semantics) {
      if (_hasAncestorWidget<ButtonStyleButton>(element) ||
          _hasAncestorWidget<IconButton>(element) ||
          _hasAncestorWidget<RawMaterialButton>(element) ||
          _hasAncestorWidget<EditableText>(element) ||
          _hasAncestorWidget<TextField>(element)) {
        return null;
      }
      if (widget.properties.header == true) {
        return 'header';
      }
      if (widget.properties.button == true) {
        return 'button';
      }
      if (widget.properties.textField == true) {
        return 'textField';
      }
      if (widget.properties.hidden == true) {
        return null;
      }
    }
    return null;
  }

  static bool _isVisible(Element element) {
    final Widget widget = element.widget;
    if (widget is Offstage && widget.offstage) {
      return false;
    }
    if (widget is Visibility && !widget.visible && !widget.maintainSize) {
      return false;
    }
    if (widget is Opacity && widget.opacity <= 0) {
      return false;
    }
    if (widget is Semantics && widget.properties.hidden == true) {
      return false;
    }

    final RenderObject? renderObject = element.renderObject;
    if (renderObject == null || !renderObject.attached) {
      return false;
    }
    if (renderObject is RenderOffstage && renderObject.offstage) {
      return false;
    }
    if (renderObject is RenderBox) {
      if (!renderObject.hasSize || renderObject.size.isEmpty) {
        return false;
      }
    }
    return true;
  }

  static PilotRuntimeBounds? _boundsFor(Element element) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final Offset topLeft = renderObject.localToGlobal(Offset.zero);
    return PilotRuntimeBounds(
      left: topLeft.dx,
      top: topLeft.dy,
      width: renderObject.size.width,
      height: renderObject.size.height,
    );
  }

  static bool _hasAncestorWidget<T extends Widget>(Element element) {
    bool found = false;
    element.visitAncestorElements((Element ancestor) {
      if (ancestor.widget is T) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }
}

class _FinderEvidence {
  const _FinderEvidence({
    this.ownText,
    this.descendantText,
    this.semanticType,
    this.valueKey,
    this.widgetType,
  });

  final String? ownText;
  final String? descendantText;
  final String? semanticType;
  final String? valueKey;
  final String? widgetType;

  String? get textForDiagnostics => ownText ?? descendantText;
}
