/// Converts Flutter Inspector summary diagnostics into Widget Tree v1 JSON.
///
/// The normalizer preserves only fields proven by calibration:
/// - display `description`
/// - `widgetRuntimeType`
/// - Inspector `valueId` renamed to `inspectorValueId`
/// - optional `createdByLocalProject`
/// - optional `textPreview`
/// - recursive `children`
class PilotRuntimeWidgetTreeNormalizer {
  PilotRuntimeWidgetTreeNormalizer._();

  /// Normalize one Inspector summary tree response.
  ///
  /// Args:
  /// - `root`: Decoded root diagnostics node returned by
  ///   `ext.flutter.inspector.getRootWidgetTree`.
  ///
  /// Returns a JSON-compatible Widget Tree v1 map with `schema`, `source`, and
  /// `root`. Throws `FormatException` when a required node field is missing or
  /// has the wrong type.
  static Map<String, Object?> normalize(Map<String, Object?> root) {
    return <String, Object?>{
      'schema': 'flutter_pilot.widget_tree.v1',
      'source': 'flutter_inspector_summary_tree',
      'root': _normalizeNode(root, 'root'),
    };
  }

  /// Normalize one Inspector diagnostics node and its descendants.
  ///
  /// Args:
  /// - `node`: Decoded Inspector node to convert.
  /// - `path`: Human-readable path used in validation errors.
  ///
  /// Returns a node map with required normalized fields and always-present
  /// `children`. Throws `FormatException` when a required field is absent or an
  /// optional field has the wrong type.
  static Map<String, Object?> _normalizeNode(
    Map<String, Object?> node,
    String path,
  ) {
    final String widgetRuntimeType = _requiredString(
      node,
      'widgetRuntimeType',
      path,
    );
    final String description = path == 'root'
        ? _rootDescription(node, widgetRuntimeType)
        : _requiredString(node, 'description', path);
    final String inspectorValueId = _requiredString(node, 'valueId', path);

    final Map<String, Object?> normalized = <String, Object?>{
      'description': description,
      'widgetRuntimeType': widgetRuntimeType,
      'inspectorValueId': inspectorValueId,
    };

    final Object? createdByLocalProject = node['createdByLocalProject'];
    if (createdByLocalProject != null) {
      if (createdByLocalProject is! bool) {
        throw FormatException(
          '$path.createdByLocalProject must be a boolean when present.',
        );
      }
      normalized['createdByLocalProject'] = createdByLocalProject;
    }

    final Object? textPreview = node['textPreview'];
    if (textPreview != null) {
      if (textPreview is! String) {
        throw FormatException(
          '$path.textPreview must be a string when present.',
        );
      }
      normalized['textPreview'] = textPreview;
    }

    normalized['children'] = _normalizeChildren(node, path);
    return normalized;
  }

  /// Read one required string field from an Inspector node.
  ///
  /// Args:
  /// - `node`: Inspector node that should contain the field.
  /// - `field`: Field name to read, such as `description` or `valueId`.
  /// - `path`: Node path included in the failure message.
  ///
  /// Returns the non-empty string value. Throws `FormatException` when the
  /// field is missing, empty, or not a string.
  static String _requiredString(
    Map<String, Object?> node,
    String field,
    String path,
  ) {
    final Object? value = node[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('$path.$field must be a non-empty string.');
    }
    return value;
  }

  /// Return the root node description, accepting Android Inspector omissions.
  ///
  /// Some real debug Runtime Targets return a root summary node without a
  /// usable `description`. The root still has `widgetRuntimeType`, so use that
  /// as the display label while preserving strict validation for child nodes.
  static String _rootDescription(
    Map<String, Object?> node,
    String widgetRuntimeType,
  ) {
    final Object? value = node['description'];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return widgetRuntimeType;
  }

  /// Normalize an Inspector node's child list.
  ///
  /// Args:
  /// - `node`: Inspector node whose `children` field may be absent.
  /// - `path`: Node path included in child validation errors.
  ///
  /// Returns a list of normalized child nodes. Missing `children` returns an
  /// empty list so consumers can traverse one stable shape.
  static List<Object?> _normalizeChildren(
    Map<String, Object?> node,
    String path,
  ) {
    final Object? rawChildren = node['children'];
    if (rawChildren == null) {
      return <Object?>[];
    }
    if (rawChildren is! List<Object?>) {
      throw FormatException('$path.children must be a list when present.');
    }

    final List<Object?> children = <Object?>[];
    for (int index = 0; index < rawChildren.length; index += 1) {
      final Object? child = rawChildren[index];
      if (child is! Map<String, Object?>) {
        throw FormatException('$path.children[$index] must be an object.');
      }
      children.add(_normalizeNode(child, '$path.children[$index]'));
    }
    return children;
  }
}
