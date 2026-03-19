import 'dart:convert';

import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';

/// Immutable manifest entry describing a workflow definition.
class WorkflowManifestEntry {
  /// Creates a workflow manifest entry.
  const WorkflowManifestEntry({
    required this.id,
    required this.name,
    required this.kind,
    this.version,
    this.description,
    this.metadata,
    this.steps = const [],
    this.checkpoints = const [],
  });

  /// Stable workflow identifier.
  final String id;

  /// Workflow name.
  final String name;

  /// Workflow definition kind.
  final WorkflowDefinitionKind kind;

  /// Optional workflow version.
  final String? version;

  /// Optional workflow description.
  final String? description;

  /// Optional workflow metadata.
  final Map<String, Object?>? metadata;

  /// Declared flow steps.
  final List<WorkflowManifestFlowStep> steps;

  /// Declared script checkpoints.
  final List<WorkflowManifestCheckpoint> checkpoints;

  /// Human-friendly label for the declared nodes on this workflow.
  String get declaredNodeLabel =>
      kind == WorkflowDefinitionKind.script ? 'checkpoints' : 'steps';

  /// Serializes this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      'declaredNodeLabel': declaredNodeLabel,
      if (steps.isNotEmpty)
        'steps': steps.map((step) => step.toJson()).toList(growable: false),
      if (checkpoints.isNotEmpty)
        'checkpoints': checkpoints
            .map((checkpoint) => checkpoint.toJson())
            .toList(growable: false),
    };
  }
}

/// Immutable manifest entry describing a declared flow step.
class WorkflowManifestFlowStep {
  /// Creates a flow step manifest entry.
  const WorkflowManifestFlowStep({
    required this.id,
    required this.name,
    required this.position,
    required this.kind,
    required this.autoVersion,
    this.title,
    this.taskNames = const [],
    this.metadata,
  });

  /// Stable step identifier.
  final String id;

  /// Step name.
  final String name;

  /// Zero-based position in the workflow.
  final int position;

  /// Step kind.
  final WorkflowStepKind kind;

  /// Whether this step auto-versions checkpoints.
  final bool autoVersion;

  /// Optional title.
  final String? title;

  /// Associated task names.
  final List<String> taskNames;

  /// Optional step metadata.
  final Map<String, Object?>? metadata;

  /// Serializes this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'kind': kind.name,
      'autoVersion': autoVersion,
      if (title != null) 'title': title,
      if (taskNames.isNotEmpty) 'taskNames': taskNames,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Immutable manifest entry describing a declared script checkpoint.
class WorkflowManifestCheckpoint {
  /// Creates a script checkpoint manifest entry.
  const WorkflowManifestCheckpoint({
    required this.id,
    required this.name,
    required this.position,
    required this.kind,
    required this.autoVersion,
    this.title,
    this.taskNames = const [],
    this.metadata,
  });

  /// Stable checkpoint identifier.
  final String id;

  /// Checkpoint name.
  final String name;

  /// Zero-based position in the script declaration list.
  final int position;

  /// Checkpoint kind.
  final WorkflowStepKind kind;

  /// Whether this checkpoint auto-versions replays.
  final bool autoVersion;

  /// Optional title.
  final String? title;

  /// Associated task names.
  final List<String> taskNames;

  /// Optional checkpoint metadata.
  final Map<String, Object?>? metadata;

  /// Serializes this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'kind': kind.name,
      'autoVersion': autoVersion,
      if (title != null) 'title': title,
      if (taskNames.isNotEmpty) 'taskNames': taskNames,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Converts workflow definitions into typed manifest entries.
extension WorkflowManifestDefinition on WorkflowDefinition {
  /// Builds a manifest entry for this definition.
  WorkflowManifestEntry toManifestEntry() {
    final workflowId = stableId;
    final stepEntries = <WorkflowManifestFlowStep>[];
    final checkpointEntries = <WorkflowManifestCheckpoint>[];
    if (isScript) {
      for (var index = 0; index < checkpoints.length; index += 1) {
        final checkpoint = checkpoints[index];
        checkpointEntries.add(
          WorkflowManifestCheckpoint(
            id: _stableHexDigest('$workflowId:${checkpoint.name}:$index'),
            name: checkpoint.name,
            position: index,
            kind: checkpoint.kind,
            autoVersion: checkpoint.autoVersion,
            title: checkpoint.title,
            taskNames: checkpoint.taskNames,
            metadata: checkpoint.metadata,
          ),
        );
      }
    } else {
      for (var index = 0; index < steps.length; index += 1) {
        final step = steps[index];
        stepEntries.add(
          WorkflowManifestFlowStep(
            id: _stableHexDigest('$workflowId:${step.name}:$index'),
            name: step.name,
            position: index,
            kind: step.kind,
            autoVersion: step.autoVersion,
            title: step.title,
            taskNames: step.taskNames,
            metadata: step.metadata,
          ),
        );
      }
    }
    return WorkflowManifestEntry(
      id: workflowId,
      name: name,
      kind: isScript
          ? WorkflowDefinitionKind.script
          : WorkflowDefinitionKind.flow,
      version: version,
      description: description,
      metadata: metadata,
      steps: stepEntries,
      checkpoints: checkpointEntries,
    );
  }
}

String _stableHexDigest(String input) {
  final bytes = utf8.encode(input);
  var hash = 0xcbf29ce484222325;
  const prime = 0x00000100000001B3;
  for (final value in bytes) {
    hash ^= value;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
