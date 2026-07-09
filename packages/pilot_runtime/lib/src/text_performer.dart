import 'package:flutter/material.dart';

import 'finder_resolver.dart';

/// Performs editable text actions for Runtime Handles returned by Finder resolution.
///
/// The performer edits Flutter text controllers directly for deterministic
/// Scenario replay. It does not simulate platform keyboards or IME behavior.
class PilotRuntimeTextPerformer {
  PilotRuntimeTextPerformer._();

  /// Clear the current text for one editable Runtime Handle.
  ///
  /// Returns a structured VM Service response. Non-editable, stale, or
  /// malformed handles return `ok: false` instead of throwing.
  static Future<Map<String, Object?>> clearText({
    required String handle,
  }) async {
    final EditableTextState? state = _editableStateFor(handle);
    if (state == null) {
      return _failure(handle);
    }
    state.updateEditingValue(TextEditingValue.empty);
    return <String, Object?>{'ok': true};
  }

  /// Append text to one editable Runtime Handle.
  ///
  /// `text` is the exact fragment received from Flutter Pilot. The Scenario
  /// runner sends one character at a time for `type` actions.
  static Future<Map<String, Object?>> enterText({
    required String handle,
    required String text,
  }) async {
    final EditableTextState? state = _editableStateFor(handle);
    if (state == null) {
      return _failure(handle);
    }
    final TextEditingValue currentValue = state.textEditingValue;
    final String nextText = currentValue.text + text;
    state.updateEditingValue(
      TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      ),
    );
    return <String, Object?>{'ok': true};
  }

  static EditableTextState? _editableStateFor(String handle) {
    final Element? element = PilotRuntimeFinderResolver.elementForHandle(
      handle,
    );
    if (element == null) {
      return null;
    }
    final List<EditableTextState> states = <EditableTextState>[];
    _collectEditableStates(element, states);
    if (states.length != 1) {
      return null;
    }
    return states.single;
  }

  static void _collectEditableStates(
    Element element,
    List<EditableTextState> states,
  ) {
    if (!PilotRuntimeFinderResolver.isVisibleElement(element)) {
      return;
    }
    if (element is StatefulElement && element.state is EditableTextState) {
      final EditableTextState state = element.state as EditableTextState;
      if (_isEditable(state)) {
        states.add(state);
      }
      return;
    }
    element.visitChildren((Element child) {
      _collectEditableStates(child, states);
    });
  }

  static bool _isEditable(EditableTextState state) {
    return !state.widget.readOnly;
  }

  static Map<String, Object?> _failure(String handle) {
    return <String, Object?>{
      'ok': false,
      'code': 'notEditableText',
      'message': 'Runtime Handle $handle does not identify editable text.',
    };
  }
}
