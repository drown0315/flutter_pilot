import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'finder_resolver.dart';

/// Performs tap actions for Runtime Handles returned by Finder resolution.
///
/// The performer prefers Flutter semantics when a target exposes
/// `SemanticsAction.tap`. When no semantic tap action is available, it falls
/// back to a pointer tap at the target's global bounds center. Expected action
/// failures are returned as structured protocol payloads instead of VM Service
/// exceptions.
class PilotRuntimeTapPerformer {
  PilotRuntimeTapPerformer._();

  /// Tap one currently visible Runtime Handle.
  ///
  /// Args:
  /// - `handle`: Opaque Runtime Handle returned by Finder resolution.
  ///
  /// Returns a VM Service response describing either the tap path used or a
  /// structured failure with `ok`, `code`, and `message` fields.
  static Future<Map<String, Object?>> tap({required String handle}) async {
    final Element? element = PilotRuntimeFinderResolver.elementForHandle(
      handle,
    );
    if (element == null) {
      return _failure(
        code: 'notTappable',
        message:
            'Runtime Handle $handle does not identify a visible tap target.',
      );
    }

    final SemanticsNode? semanticsNode = element.renderObject?.debugSemantics;
    if (semanticsNode != null &&
        semanticsNode.getSemanticsData().hasAction(SemanticsAction.tap)) {
      semanticsNode.owner?.performAction(semanticsNode.id, SemanticsAction.tap);
      return <String, Object?>{'ok': true, 'method': 'semantic'};
    }

    final Offset? center = _centerFor(element);
    if (center == null) {
      return _failure(
        code: 'notTappable',
        message:
            'Runtime Handle $handle does not have usable bounds for pointer tap.',
      );
    }
    if (!_canReceivePointerTap(element)) {
      return _failure(
        code: 'notTappable',
        message: 'Runtime Handle $handle cannot be tapped.',
      );
    }

    final int pointer = DateTime.now().microsecondsSinceEpoch;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: center,
        buttons: kPrimaryButton,
      ),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: center),
    );
    return <String, Object?>{'ok': true, 'method': 'pointer'};
  }

  static Map<String, Object?> _failure({
    required String code,
    required String message,
  }) {
    return <String, Object?>{'ok': false, 'code': code, 'message': message};
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

  static bool _canReceivePointerTap(Element element) {
    final Widget widget = element.widget;
    if (widget is GestureDetector && widget.onTap != null) {
      return true;
    }
    if (widget is ButtonStyleButton && widget.enabled) {
      return true;
    }
    if (widget is IconButton && widget.onPressed != null) {
      return true;
    }
    if (widget is RawMaterialButton && widget.onPressed != null) {
      return true;
    }
    return false;
  }
}
