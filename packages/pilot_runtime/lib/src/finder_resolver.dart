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
          text: evidence.diagnosticTextFor(byText),
          semanticType: evidence.diagnosticSemanticTypeFor(byType),
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

  /// Return whether one Element satisfies Finder visibility rules.
  static bool isVisibleElement(Element element) {
    return _isVisible(element);
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
    final bool hasWrapperConstraint = byKey != null || byWidget != null;
    final bool matchesText = hasStructuralConstraint
        ? evidence.hasText(byText)
        : evidence.ownText == byText;
    final bool matchesSemanticType = hasWrapperConstraint
        ? evidence.hasSemanticType(byType)
        : evidence.semanticType == byType;
    if (byText != null && !matchesText) {
      return false;
    }
    if (byType != null && !matchesSemanticType) {
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
    return _FinderEvidence(
      ownText: ownText,
      descendantTexts: _descendantTextsFor(element),
      semanticType: semanticType,
      descendantSemanticTypes: _descendantSemanticTypesFor(element),
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

  static List<String> _descendantTextsFor(Element element) {
    final List<String> texts = <String>[];
    element.visitChildren((Element child) {
      if (!_isVisible(child)) {
        return;
      }
      final String? text = _ownTextFor(child);
      if (text != null) {
        texts.add(text);
      }
      texts.addAll(_descendantTextsFor(child));
    });
    return texts;
  }

  static List<String> _descendantSemanticTypesFor(Element element) {
    final List<String> semanticTypes = <String>[];
    element.visitChildren((Element child) {
      if (!_isVisible(child)) {
        return;
      }
      final String? semanticType = _semanticTypeFor(child);
      if (semanticType != null) {
        semanticTypes.add(semanticType);
      }
      semanticTypes.addAll(_descendantSemanticTypesFor(child));
    });
    return semanticTypes;
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
    required this.descendantTexts,
    this.semanticType,
    required this.descendantSemanticTypes,
    this.valueKey,
    this.widgetType,
  });

  final String? ownText;
  final List<String> descendantTexts;
  final String? semanticType;
  final List<String> descendantSemanticTypes;
  final String? valueKey;
  final String? widgetType;

  bool hasText(String? text) {
    if (text == null) {
      return true;
    }
    return ownText == text || descendantTexts.contains(text);
  }

  bool hasSemanticType(String? type) {
    if (type == null) {
      return true;
    }
    return semanticType == type || descendantSemanticTypes.contains(type);
  }

  String? diagnosticTextFor(String? requestedText) {
    if (requestedText != null && hasText(requestedText)) {
      return requestedText;
    }
    if (ownText != null) {
      return ownText;
    }
    if (descendantTexts.isNotEmpty) {
      return descendantTexts.first;
    }
    return null;
  }

  String? diagnosticSemanticTypeFor(String? requestedType) {
    if (requestedType != null && hasSemanticType(requestedType)) {
      return requestedType;
    }
    if (semanticType != null) {
      return semanticType;
    }
    if (descendantSemanticTypes.isNotEmpty) {
      return descendantSemanticTypes.first;
    }
    return null;
  }
}
