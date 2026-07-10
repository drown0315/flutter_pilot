/// Base type for all actions that a Scenario step can perform.
///
/// Each concrete subclass represents one YAML action key. A `ScenarioStep`
/// contains exactly one `StepAction`.
///
/// Example:
/// A YAML step with `tap:` becomes `TapAction`.
sealed class StepAction {
  const StepAction();

  /// Convert this action to the JSON shape stored in Scenario artifacts.
  Map<String, Object?> toJson();
}

/// Typed representation of one Scenario YAML file.
///
/// It contains:
/// - a stable Scenario name
/// - an optional human description
/// - optional Scenario Recording metadata
/// - ordered steps to replay against a Flutter app
///
/// Example:
/// `Scenario(name: 'login_error', steps: [...])`
class Scenario {
  const Scenario({
    required this.name,
    this.description,
    this.recording,
    required this.steps,
  });

  final String name;
  final String? description;
  final ScenarioRecording? recording;
  final List<ScenarioStep> steps;

  /// Return a Scenario that includes steps through `stepNumber`.
  ///
  /// Args:
  /// `stepNumber` is the 1-based stop point accepted by CLI `--until`.
  ///
  /// Returns:
  /// A Scenario with the same metadata and only the steps that should execute.
  ///
  /// Throws:
  /// `RangeError` when `stepNumber` is outside the Scenario step range.
  Scenario sliceThroughStepNumber(int stepNumber) {
    RangeError.checkValueInInterval(stepNumber, 1, steps.length, 'stepNumber');
    return Scenario(
      name: name,
      description: description,
      recording: recording,
      steps: steps.take(stepNumber).toList(growable: false),
    );
  }

  /// Return a Scenario that includes steps through the Step named `label`.
  ///
  /// Args:
  /// `label` is an already-validated Step label accepted by CLI `--until`.
  ///
  /// Returns:
  /// A Scenario with the same metadata and only the steps that should execute.
  ///
  /// Throws:
  /// `ArgumentError` when no Step has `label`.
  Scenario sliceThroughStepLabel(String label) {
    final int stepIndex = steps.indexWhere(
      (ScenarioStep step) => step.label == label,
    );
    if (stepIndex == -1) {
      throw ArgumentError.value(label, 'label', 'No Step has this label.');
    }
    return sliceThroughStepNumber(stepIndex + 1);
  }

  /// Convert this Scenario to the JSON shape stored in Scenario artifacts.
  ///
  /// Returns:
  /// A JSON-compatible map with Scenario name, optional description, optional
  /// recording metadata, and ordered Step records.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      if (description != null) 'description': description,
      if (recording != null) 'recording': recording!.toJson(),
      'steps': <Object?>[for (final ScenarioStep step in steps) step.toJson()],
    };
  }
}

/// Scenario-level device video recording configuration.
///
/// It is optional Scenario metadata, not a Step action. When present with
/// `enabled: true`, a Scenario Run should create one Recording Session for the
/// full run duration.
class ScenarioRecording {
  const ScenarioRecording({required this.enabled});

  final bool enabled;

  /// Convert this Scenario Recording metadata to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{'enabled': enabled};
  }
}

/// One ordered Scenario step.
///
/// It contains:
/// - `index`: the 1-based step number used by `--until`
/// - `label`: an optional unique slug for named stopping points
/// - `action`: the single action to execute for this step
/// - `source`: optional file origin metadata when parsed through `parseFile`
///
/// Example:
/// `ScenarioStep(index: 1, label: 'submit_login', action: TapAction(...))`
class ScenarioStep {
  const ScenarioStep({
    required this.index,
    this.label,
    this.source,
    required this.action,
  });

  final int index;
  final String? label;
  final StepSource? source;
  final StepAction action;

  /// Convert this Step to the JSON shape stored in Scenario artifacts.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'index': index,
      if (label != null) 'label': label,
      if (source != null) 'source': source!.toJson(),
      'action': action.toJson(),
    };
  }
}

/// One Step Include edge that contributed an expanded Step.
///
/// It contains:
/// - the included file identity used by tooling
/// - the display path written in the include entry when practical
/// - the YAML path of the include field inside the Entry Scenario or library
///
/// Example:
/// `IncludeSource(displayPath: 'flows/login.yaml', includePath:
/// 'steps[1].include', fileIdentity: '/repo/flows/login.yaml')`
class IncludeSource {
  const IncludeSource({
    required this.fileIdentity,
    required this.displayPath,
    required this.includePath,
  });

  final String fileIdentity;
  final String displayPath;
  final String includePath;

  /// Convert this Include Source metadata to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fileIdentity': fileIdentity,
      'displayPath': displayPath,
      'includePath': includePath,
    };
  }
}

/// File origin metadata for an expanded Scenario Step.
///
/// It contains:
/// - `fileIdentity`: canonical file identity when available
/// - `displayPath`: user-facing file path for reports
/// - `yamlPath`: path of the Step inside its source file
/// - `includeChain`: Step Includes from the Entry Scenario to this Step
///
/// Example:
/// A Step from `shared/login.yaml` included by `steps[1].include` records that
/// include in `includeChain` while keeping the Step executable as a flat Step.
class StepSource {
  const StepSource({
    required this.fileIdentity,
    required this.displayPath,
    required this.yamlPath,
    required this.includeChain,
  });

  final String fileIdentity;
  final String displayPath;
  final String yamlPath;
  final List<IncludeSource> includeChain;

  /// Convert this Step Source metadata to JSON.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'fileIdentity': fileIdentity,
      'displayPath': displayPath,
      'yamlPath': yamlPath,
      'includeChain': <Object?>[
        for (final IncludeSource include in includeChain) include.toJson(),
      ],
    };
  }
}

/// Rule set for finding widgets before an action runs.
///
/// It can contain any combination of:
/// - `byText`: exact visible text
/// - `byType`: Semantic Node Type from the Runtime Target
/// - `byKey`: `ValueKey<String>` value
/// - `byWidget`: exact Dart widget runtime type display name
///
/// Example:
/// `Finder(byText: 'Log in', byType: 'button')` means both rules must match.
class Finder {
  const Finder({this.byText, this.byType, this.byKey, this.byWidget});

  final String? byText;
  final String? byType;
  final String? byKey;
  final String? byWidget;

  bool get isEmpty =>
      byText == null && byType == null && byKey == null && byWidget == null;

  /// Convert this Finder to JSON constraints.
  ///
  /// Returns:
  /// A map containing only the Finder fields that are present.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (byText != null) 'byText': byText,
      if (byType != null) 'byType': byType,
      if (byKey != null) 'byKey': byKey,
      if (byWidget != null) 'byWidget': byWidget,
    };
  }
}

/// Tap action targeting exactly one widget matched by its Finder.
class TapAction extends StepAction {
  const TapAction({required this.finder});

  final Finder finder;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{'tap': finder.toJson()};
  }
}

/// Text-entry action that clears and re-enters the target widget's text.
class TypeAction extends StepAction {
  const TypeAction({required this.finder, required this.text});

  final Finder finder;
  final String text;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': <String, Object?>{...finder.toJson(), 'text': text},
    };
  }
}

/// Drag gesture action using Flutter gesture delta semantics.
///
/// `finder` is optional. When absent, the future runner should use the primary
/// scrollable. `deltaX` and `deltaY` describe the drag movement, so
/// `deltaY: -500` means drag upward.
class ScrollAction extends StepAction {
  const ScrollAction({this.finder, required this.deltaX, required this.deltaY});

  final Finder? finder;
  final double deltaX;
  final double deltaY;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scroll': <String, Object?>{
        if (finder != null) ...finder!.toJson(),
        'deltaX': deltaX,
        'deltaY': deltaY,
      },
    };
  }
}

/// Wait action that succeeds when its Finder has one unique match.
class WaitForAction extends StepAction {
  const WaitForAction({required this.finder, required this.timeoutMs});

  final Finder finder;
  final int timeoutMs;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'waitFor': <String, Object?>{...finder.toJson(), 'timeoutMs': timeoutMs},
    };
  }
}

/// Diagnostic capture action.
///
/// Each boolean controls one artifact family:
/// - `screenshot`: visual image artifact
/// - `snapshot`: legacy structured UI state, always false for Scenario YAML
/// - `widgetTree`: structured Widget Tree for programs and agents
/// - `logs`: structured runtime logs, including runtime errors when available
class CaptureAction extends StepAction {
  const CaptureAction({
    required this.screenshot,
    required this.snapshot,
    required this.widgetTree,
    required this.logs,
  });

  final bool screenshot;
  final bool snapshot;
  final bool widgetTree;
  final bool logs;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capture': <String, Object?>{
        'screenshot': screenshot,
        'widgetTree': widgetTree,
        'logs': logs,
      },
    };
  }
}
