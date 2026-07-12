import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'finder_resolver.dart';

/// Performs scroll actions for targeted and automatically selected scrollables.
///
/// The performer uses pointer drag gestures with Flutter logical-pixel deltas.
/// It does not use semantic scroll actions, so Scenario `deltaX` and `deltaY`
/// map directly to the drag movement sent to Flutter's gesture binding.
class PilotRuntimeScrollPerformer {
  PilotRuntimeScrollPerformer._();

  static int _nextPointer = 1;

  /// Drag a targeted scrollable or the unique outermost visible scrollable.
  ///
  /// Args:
  /// - `handle`: Optional Runtime Handle. When present, the handle must identify
  ///   a visible scrollable or a widget subtree that contains one scrollable.
  /// - `deltaX`: Horizontal drag distance in logical pixels.
  /// - `deltaY`: Vertical drag distance in logical pixels.
  ///   The larger absolute delta selects the scroll axis; ties are vertical.
  ///
  /// Without a handle, selection ignores nested scrollables on the chosen axis
  /// and fails when multiple outermost candidates remain. Returns a structured
  /// VM Service response. Missing, ambiguous, or non-scrollable targets return
  /// `ok: false` instead of throwing.
  static Future<Map<String, Object?>> scroll({
    String? handle,
    required double deltaX,
    required double deltaY,
  }) async {
    final Axis dragAxis = deltaY.abs() >= deltaX.abs()
        ? Axis.vertical
        : Axis.horizontal;
    final Element? scrollableElement = handle == null
        ? _primaryScrollable(dragAxis)
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

    final Offset? dragStart = _dragStartFor(scrollableElement, dragAxis);
    if (dragStart == null) {
      return _failure(
        code: handle == null ? 'primaryScrollableUnavailable' : 'notScrollable',
        message: handle == null
            ? 'Primary scrollable does not have usable bounds.'
            : 'Runtime Handle $handle does not have usable scroll bounds.',
      );
    }

    final int pointer = _nextPointer++;
    GestureBinding.instance.handlePointerEvent(
      PointerAddedEvent(pointer: pointer, position: dragStart),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: dragStart,
        buttons: kPrimaryButton,
      ),
    );
    final Offset firstDelta = Offset(deltaX, deltaY) / 2.0;
    final Offset secondDelta = Offset(deltaX, deltaY) - firstDelta;
    _movePointer(pointer: pointer, from: dragStart, delta: firstDelta);
    _movePointer(
      pointer: pointer,
      from: dragStart + firstDelta,
      delta: secondDelta,
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: dragStart + Offset(deltaX, deltaY),
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerRemovedEvent(
        pointer: pointer,
        position: dragStart + Offset(deltaX, deltaY),
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
    if (element.widget is Scrollable) {
      return element;
    }
    Element? scrollable;
    element.visitChildren((Element child) {
      scrollable ??= _firstScrollableInSubtree(child);
    });
    return scrollable;
  }

  static Element? _firstScrollableInSubtree(Element element) {
    if (element.widget is Scrollable) {
      return element;
    }
    Element? scrollable;
    element.visitChildren((Element child) {
      scrollable ??= _firstScrollableInSubtree(child);
    });
    return scrollable;
  }

  static Element? _primaryScrollable(Axis dragAxis) {
    final List<Element> scrollables = <Element>[];
    PilotRuntimeFinderResolver.visitVisibleElements((Element element) {
      final Widget widget = element.widget;
      if (widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == dragAxis) {
        scrollables.add(element);
      }
    });
    final Set<Element> candidates = Set<Element>.identity()
      ..addAll(scrollables);
    final List<Element> outermostScrollables = scrollables
        .where((Element element) {
          bool hasScrollableAncestor = false;
          element.visitAncestorElements((Element ancestor) {
            if (candidates.contains(ancestor)) {
              hasScrollableAncestor = true;
              return false;
            }
            return true;
          });
          return !hasScrollableAncestor;
        })
        .toList(growable: false);
    if (outermostScrollables.length != 1) {
      return null;
    }
    return outermostScrollables.single;
  }

  static Offset? _dragStartFor(Element element, Axis dragAxis) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    if (renderObject.size.isEmpty) {
      return null;
    }
    final Rect bounds =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final List<Rect> nestedScrollableBounds = <Rect>[];
    element.visitChildren((Element child) {
      _collectScrollableBounds(child, dragAxis, nestedScrollableBounds);
    });
    final List<Offset> candidates = <Offset>[
      bounds.center,
      Offset(bounds.center.dx, bounds.top + bounds.height * 0.25),
      Offset(bounds.center.dx, bounds.top + bounds.height * 0.75),
      Offset(bounds.left + bounds.width * 0.25, bounds.center.dy),
      Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
    ];
    for (final Offset candidate in candidates) {
      if (!nestedScrollableBounds.any(
        (Rect nested) => nested.contains(candidate),
      )) {
        return candidate;
      }
    }
    return null;
  }

  static void _collectScrollableBounds(
    Element element,
    Axis dragAxis,
    List<Rect> bounds,
  ) {
    final RenderObject? renderObject = element.renderObject;
    final Widget widget = element.widget;
    if (widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == dragAxis &&
        renderObject is RenderBox &&
        renderObject.hasSize &&
        !renderObject.size.isEmpty) {
      bounds.add(renderObject.localToGlobal(Offset.zero) & renderObject.size);
    }
    element.visitChildren((Element child) {
      _collectScrollableBounds(child, dragAxis, bounds);
    });
  }

  static Map<String, Object?> _failure({
    required String code,
    required String message,
  }) {
    return <String, Object?>{'ok': false, 'code': code, 'message': message};
  }
}
