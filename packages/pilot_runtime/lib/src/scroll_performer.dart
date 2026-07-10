import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'finder_resolver.dart';

/// Performs scroll actions for targeted and primary scrollables.
///
/// The performer uses pointer drag gestures with Flutter logical-pixel deltas.
/// It does not use semantic scroll actions, so Scenario `deltaX` and `deltaY`
/// map directly to the drag movement sent to Flutter's gesture binding.
class PilotRuntimeScrollPerformer {
  PilotRuntimeScrollPerformer._();

  static int _nextPointer = 1;

  /// Drag a targeted scrollable or the primary visible scrollable.
  ///
  /// Args:
  /// - `handle`: Optional Runtime Handle. When present, the handle must identify
  ///   a visible scrollable or a widget subtree that contains one scrollable.
  /// - `deltaX`: Horizontal drag distance in logical pixels.
  /// - `deltaY`: Vertical drag distance in logical pixels.
  ///
  /// Returns a structured VM Service response. Missing, ambiguous, or
  /// non-scrollable targets return `ok: false` instead of throwing.
  static Future<Map<String, Object?>> scroll({
    String? handle,
    required double deltaX,
    required double deltaY,
  }) async {
    final Element? scrollableElement = handle == null
        ? _primaryScrollable()
        : _scrollableForHandle(handle);
    if (scrollableElement == null) {
      return handle == null
          ? _failure(
              code: 'primaryScrollableUnavailable',
              message:
                  'Primary scrollable is missing or ambiguous for '
                  'untargeted scroll.',
            )
          : _failure(
              code: 'notScrollable',
              message: 'Runtime Handle $handle does not identify a scrollable.',
            );
    }

    final Offset? center = _centerFor(scrollableElement);
    if (center == null) {
      return _failure(
        code: handle == null ? 'primaryScrollableUnavailable' : 'notScrollable',
        message: handle == null
            ? 'Primary scrollable does not have usable bounds.'
            : 'Runtime Handle $handle does not have usable scroll bounds.',
      );
    }

    final int pointer = _nextPointer++;
    GestureBinding.instance.handlePointerEvent(
      PointerAddedEvent(pointer: pointer, position: center),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: center,
        buttons: kPrimaryButton,
      ),
    );
    final Offset firstDelta = Offset(deltaX, deltaY) / 2.0;
    final Offset secondDelta = Offset(deltaX, deltaY) - firstDelta;
    _movePointer(pointer: pointer, from: center, delta: firstDelta);
    _movePointer(
      pointer: pointer,
      from: center + firstDelta,
      delta: secondDelta,
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: center + Offset(deltaX, deltaY),
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerRemovedEvent(
        pointer: pointer,
        position: center + Offset(deltaX, deltaY),
      ),
    );
    return <String, Object?>{'ok': true, 'method': 'pointer'};
  }

  static void _movePointer({
    required int pointer,
    required Offset from,
    required Offset delta,
  }) {
    GestureBinding.instance.handlePointerEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: from + delta,
        delta: delta,
        buttons: kPrimaryButton,
      ),
    );
  }

  static Element? _scrollableForHandle(String handle) {
    final Element? element = PilotRuntimeFinderResolver.elementForHandle(
      handle,
    );
    if (element == null) {
      return null;
    }
    if (PilotRuntimeFinderResolver.isVisibleElement(element) &&
        element.widget is Scrollable) {
      return element;
    }
    final List<Element> scrollables = <Element>[];
    element.visitChildren((Element child) {
      _collectScrollablesInSubtree(child, scrollables);
    });
    if (scrollables.length != 1) {
      return null;
    }
    return scrollables.single;
  }

  static void _collectScrollablesInSubtree(
    Element element,
    List<Element> scrollables,
  ) {
    if (!PilotRuntimeFinderResolver.isVisibleElement(element)) {
      return;
    }
    if (element.widget is Scrollable) {
      scrollables.add(element);
    }
    element.visitChildren((Element child) {
      _collectScrollablesInSubtree(child, scrollables);
    });
  }

  static Element? _primaryScrollable() {
    final List<Element> scrollables = <Element>[];
    PilotRuntimeFinderResolver.visitVisibleElements((Element element) {
      if (_isPrimaryScrollableCandidate(element)) {
        scrollables.add(element);
      }
    });
    if (scrollables.length != 1) {
      return null;
    }
    return scrollables.single;
  }

  static bool _isPrimaryScrollableCandidate(Element element) {
    if (element.widget is! Scrollable) {
      return false;
    }
    return !_hasAncestorWidget<EditableText>(element);
  }

  static Offset? _centerFor(Element element) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    if (renderObject.size.isEmpty) {
      return null;
    }
    return renderObject.localToGlobal(renderObject.size.center(Offset.zero));
  }

  static Map<String, Object?> _failure({
    required String code,
    required String message,
  }) {
    return <String, Object?>{'ok': false, 'code': code, 'message': message};
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
