import 'dart:convert';

import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';

/// Distinguishes between declared flow steps and script checkpoints.
enum WorkflowManifestStepRole {
  /// Step that belongs to a declarative flow execution plan.
  flowStep,

  /// Checkpoint declared by a script workflow for tooling/introspection.
  scriptCheckpoint,
}

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

  /// Declared flow steps or script checkpoints.
  final List<WorkflowManifestStep> steps;

  /// Human-friendly label for the declared nodes on this workflow.
  String get stepCollectionLabel =>
      kind == WorkflowDefinitionKind.script ? 'checkpoints' : 'steps';

  /// Alias for [steps] when treating script nodes as checkpoints.
  List<WorkflowManifestStep> get checkpoints => steps;

  /// Serializes this entry to a JSON-compatible map.
  Map<String, Object?> toJson() {
    final serializedSteps = steps
        .map((step) => step.toJson())
        .toList(growable: false);
    return {
      'id': id,
      'name': name,
      'kind': kind.name,
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      'stepCollectionLabel': stepCollectionLabel,
      'steps': serializedSteps,
      if (kind == WorkflowDefinitionKind.script) 'checkpoints': serializedSteps,
    };
  }
}

/// Immutable manifest entry describing a workflow step or script checkpoint.
class WorkflowManifestStep {
  /// Creates a workflow step manifest entry.
  const WorkflowManifestStep({
    required this.id,
    required this.name,
    required this.position,
    required this.role,
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

  /// Whether this node is part of a flow plan or a script checkpoint list.
  final WorkflowManifestStepRole role;

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
      'role': role.name,
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
    final stepEntries = <WorkflowManifestStep>[];
    for (var index = 0; index < steps.length; index += 1) {
      final step = steps[index];
      stepEntries.add(
        WorkflowManifestStep(
          id: _stableHexDigest('$workflowId:${step.name}:$index'),
          name: step.name,
          position: index,
          role: isScript
              ? WorkflowManifestStepRole.scriptCheckpoint
              : WorkflowManifestStepRole.flowStep,
          kind: step.kind,
          autoVersion: step.autoVersion,
          title: step.title,
          taskNames: step.taskNames,
          metadata: step.metadata,
        ),
      );
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
