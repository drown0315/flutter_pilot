/// Base type for all actions that a Scenario step can perform.
///
/// Each concrete subclass represents one YAML action key. A `ScenarioStep`
/// contains exactly one `StepAction`.
///
/// Example:
/// A YAML step with `tap:` becomes `TapAction`.
sealed class StepAction {
  const StepAction();
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
}

/// Scenario-level device video recording configuration.
///
/// It is optional Scenario metadata, not a Step action. When present with
/// `enabled: true`, a Scenario Run should create one Recording Session for the
/// full run duration.
class ScenarioRecording {
  const ScenarioRecording({required this.enabled});

  final bool enabled;
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
}

/// Rule set for finding widgets before an action runs.
///
/// It can contain any combination of:
/// - `byText`: exact visible text
/// - `byType`: semantic Snapshot node type from `mcp_flutter`
///
/// Example:
/// `Finder(byText: 'Log in', byType: 'button')` means both rules must match.
class Finder {
  const Finder({this.byText, this.byType});

  final String? byText;
  final String? byType;

  bool get isEmpty => byText == null && byType == null;
}

/// Tap action targeting exactly one widget matched by its Finder.
class TapAction extends StepAction {
  const TapAction({required this.finder});

  final Finder finder;
}

/// Text-entry action that replaces the target widget's existing text.
class TypeAction extends StepAction {
  const TypeAction({required this.finder, required this.text});

  final Finder finder;
  final String text;
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
}

/// Wait action that succeeds when its Finder has one unique match.
class WaitForAction extends StepAction {
  const WaitForAction({required this.finder, required this.timeoutMs});

  final Finder finder;
  final int timeoutMs;
}

/// Diagnostic capture action.
///
/// Each boolean controls one artifact family:
/// - `screenshot`: visual image artifact
/// - `snapshot`: legacy structured UI state, no longer accepted in Scenario YAML
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
}
