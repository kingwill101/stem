/// Declarative workflow definitions and builders.
///
/// This library provides the [WorkflowDefinition] class, which is used to
/// describe the structure of a workflow, and builders for creating them
/// in a fluent style.
///
/// ## Workflow Kinds
///
/// Stem supports two primary ways to define workflows:
///
/// 1. **Flow**: A list of discrete `FlowStep`s that execute in order. This is
///    the most common model and is easily visualized.
/// 2. **Script**: A procedural Dart function that uses `context.step` to
///    create durable checkpoints around individual pieces of work. This allows
///    for complex branching logic and loops using standard Dart control flow.
///
/// ## Versioning and Metadata
///
/// Each definition can have a `version`, `description`, and arbitrary
/// `metadata`. The `WorkflowRuntime` uses these to track execution and
/// assist with introspection.
///
/// ## Examples
///
/// ### Flow Workflow
/// ```dart
/// final flow = WorkflowDefinition.flow(
///   name: 'process_order',
///   build: (builder) {
///     builder.step('validate_order');
///     builder.step('charge_customer');
///     builder.step('ship_items');
///   },
/// );
/// ```
///
/// ### Script Workflow
/// ```dart
/// final script = WorkflowDefinition.script(
///   name: 'process_order',
///   run: (context) async {
///     await context.step('validate_order', ...);
///     if (isPremium) {
///       await context.step('apply_discount', ...);
///     }
///     await context.step('charge_customer', ...);
///   },
/// );
/// ```
///
/// See also:
/// - `WorkflowRuntime` for the execution engine.
/// - [FlowStep] for the building blocks of flows.
library;

import 'dart:async';
import 'dart:convert';

import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/flow.dart' show Flow;
import 'package:stem/src/workflow/core/flow_context.dart';
import 'package:stem/src/workflow/core/flow_step.dart';
import 'package:stem/src/workflow/core/workflow_checkpoint.dart';
import 'package:stem/src/workflow/core/workflow_ref.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';
import 'package:stem/src/workflow/workflow.dart' show Flow;
import 'package:stem/stem.dart' show Flow;

/// Declarative workflow definition built via [FlowBuilder].
typedef WorkflowScriptBody<T extends Object?> =
    FutureOr<T> Function(WorkflowScriptContext context);

/// Identifies whether a workflow is step-based or script-based.
enum WorkflowDefinitionKind {
  /// Workflow composed of discrete flow steps.
  flow,

  /// Workflow executed via a script body.
  script,
}

/// Declarative workflow definition built via [FlowBuilder] or a higher-level
/// script facade. Flow definitions capture an ordered execution plan. Script
/// definitions capture a script body plus optional checkpoint metadata used for
/// introspection and tooling.
class WorkflowDefinition<T extends Object?> {
  /// Internal constructor used by builders and script facades.
  WorkflowDefinition._({
    required this.name,
    required WorkflowDefinitionKind kind,
    required List<FlowStep> steps,
    List<WorkflowCheckpoint> checkpoints = const [],
    List<WorkflowEdge> edges = const [],
    this.version,
    this.description,
    Map<String, Object?>? metadata,
    this.scriptBody,
    Object? Function(Object? value)? resultEncoder,
    Object? Function(Object? payload)? resultDecoder,
  }) : _kind = kind,
       _steps = steps,
       _checkpoints = checkpoints,
       _edges = edges,
       _resultEncoder = resultEncoder,
       _resultDecoder = resultDecoder,
       metadata = metadata == null ? null : Map.unmodifiable(metadata);

  /// Rehydrates a workflow definition from serialized JSON.
  factory WorkflowDefinition.fromJson(Map<String, Object?> json) {
    final kind = _kindFromJson(json['kind']);
    final stepsJson = (json['steps'] as List?) ?? const [];
    final steps = kind == WorkflowDefinitionKind.flow
        ? stepsJson
              .whereType<Map<String, Object?>>()
              .map(FlowStep.fromJson)
              .toList()
        : <FlowStep>[];
    final checkpointsJson = (json['checkpoints'] as List?) ?? stepsJson;
    final checkpoints = kind == WorkflowDefinitionKind.script
        ? checkpointsJson
              .whereType<Map<String, Object?>>()
              .map(WorkflowCheckpoint.fromJson)
              .toList()
        : <WorkflowCheckpoint>[];
    final edgesJson = (json['edges'] as List?) ?? const [];
    final edges = edgesJson
        .whereType<Map<String, Object?>>()
        .map(WorkflowEdge.fromJson)
        .toList();
    if (kind == WorkflowDefinitionKind.script) {
      return WorkflowDefinition._(
        name: json['name']?.toString() ?? '',
        kind: kind,
        steps: steps,
        checkpoints: checkpoints,
        edges: edges,
        version: json['version']?.toString(),
        description: json['description']?.toString(),
        metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
      );
    }
    return WorkflowDefinition._(
      name: json['name']?.toString() ?? '',
      kind: kind,
      steps: steps,
      checkpoints: checkpoints,
      edges: edges,
      version: json['version']?.toString(),
      description: json['description']?.toString(),
      metadata: (json['metadata'] as Map?)?.cast<String, Object?>(),
    );
  }

  /// Creates a flow-based workflow definition.
  factory WorkflowDefinition.flow({
    required String name,
    required void Function(FlowBuilder builder) build,
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    PayloadCodec<T>? resultCodec,
  }) {
    final steps = <FlowStep>[];
    build(FlowBuilder(steps));
    final edges = <WorkflowEdge>[];
    for (var i = 0; i < steps.length - 1; i += 1) {
      edges.add(WorkflowEdge(from: steps[i].name, to: steps[i + 1].name));
    }
    Object? Function(Object?)? resultEncoder;
    Object? Function(Object?)? resultDecoder;
    if (resultCodec != null) {
      resultEncoder = (Object? value) {
        return resultCodec.encodeDynamic(value);
      };
      resultDecoder = (Object? payload) {
        return resultCodec.decodeDynamic(payload);
      };
    }
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.flow,
      steps: steps,
      edges: edges,
      version: version,
      description: description,
      metadata: metadata,
      resultEncoder: resultEncoder,
      resultDecoder: resultDecoder,
    );
  }

  /// Creates a script-based workflow definition.
  factory WorkflowDefinition.script({
    required String name,
    required WorkflowScriptBody<T> run,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    PayloadCodec<T>? resultCodec,
  }) {
    Object? Function(Object?)? resultEncoder;
    Object? Function(Object?)? resultDecoder;
    if (resultCodec != null) {
      resultEncoder = (Object? value) {
        return resultCodec.encodeDynamic(value);
      };
      resultDecoder = (Object? payload) {
        return resultCodec.decodeDynamic(payload);
      };
    }
    return WorkflowDefinition._(
      name: name,
      kind: WorkflowDefinitionKind.script,
      steps: const <FlowStep>[],
      checkpoints: List<WorkflowCheckpoint>.unmodifiable(checkpoints),
      version: version,
      description: description,
      metadata: metadata,
      scriptBody: run,
      resultEncoder: resultEncoder,
      resultDecoder: resultDecoder,
    );
  }

  /// Workflow name used for registration and scheduling.
  final String name;
  final WorkflowDefinitionKind _kind;
  final List<FlowStep> _steps;
  final List<WorkflowCheckpoint> _checkpoints;
  final List<WorkflowEdge> _edges;

  /// Optional version identifier for the workflow definition.
  final String? version;

  /// Optional human-friendly description of the workflow definition.
  final String? description;

  /// Optional metadata associated with this workflow definition.
  final Map<String, Object?>? metadata;

  /// Optional script body when using the script facade.
  final WorkflowScriptBody<T>? scriptBody;

  final Object? Function(Object? value)? _resultEncoder;
  final Object? Function(Object? payload)? _resultDecoder;

  /// Ordered list of steps for flow-based workflows.
  List<FlowStep> get steps => List.unmodifiable(_steps);

  /// Declared checkpoints for script-based workflows.
  List<WorkflowCheckpoint> get checkpoints => List.unmodifiable(_checkpoints);

  /// Directed edges describing the workflow graph.
  List<WorkflowEdge> get edges => List.unmodifiable(_edges);

  /// Whether this definition represents a script-based workflow.
  bool get isScript => _kind == WorkflowDefinitionKind.script;

  /// Looks up a declared flow step by its base name.
  FlowStep? stepByName(String name) {
    for (final step in _steps) {
      if (step.name == name) {
        return step;
      }
    }
    return null;
  }

  /// Looks up declared script checkpoint metadata by its base name.
  WorkflowCheckpoint? checkpointByName(String name) {
    for (final checkpoint in _checkpoints) {
      if (checkpoint.name == name) {
        return checkpoint;
      }
    }
    return null;
  }

  /// Encodes a final workflow result before it is persisted.
  Object? encodeResult(Object? value) {
    if (value == null) return null;
    final encoder = _resultEncoder;
    if (encoder == null) return value;
    return encoder(value);
  }

  /// Decodes a persisted final workflow result.
  Object? decodeResult(Object? payload) {
    if (payload == null) return null;
    final decoder = _resultDecoder;
    if (decoder == null) return payload;
    return decoder(payload);
  }

  /// Builds a typed [WorkflowRef] from this definition without repeating the
  /// registered workflow name.
  WorkflowRef<TParams, T> ref<TParams>({
    required Map<String, Object?> Function(TParams params) encodeParams,
  }) {
    return WorkflowRef<TParams, T>(
      name: name,
      encodeParams: encodeParams,
      decodeResult: (payload) => decodeResult(payload) as T,
    );
  }

  /// Builds a typed [WorkflowRef] backed by a DTO [paramsCodec].
  WorkflowRef<TParams, T> refWithCodec<TParams>({
    required PayloadCodec<TParams> paramsCodec,
  }) {
    return WorkflowRef<TParams, T>.withPayloadCodec(
      name: name,
      paramsCodec: paramsCodec,
      decodeResult: (payload) => decodeResult(payload) as T,
    );
  }

  /// Builds a typed [WorkflowRef] for DTO params that already expose
  /// `toJson()` and `Type.fromJson(...)`.
  WorkflowRef<TParams, T> refWithJsonCodec<TParams>({
    required TParams Function(Map<String, Object?> payload) decodeParams,
    String? paramsTypeName,
  }) {
    return WorkflowRef<TParams, T>.withJsonCodec(
      name: name,
      decodeParams: decodeParams,
      decodeResult: (payload) => decodeResult(payload) as T,
      paramsTypeName: paramsTypeName,
    );
  }

  /// Builds a typed [NoArgsWorkflowRef] from this definition.
  NoArgsWorkflowRef<T> ref0() {
    return NoArgsWorkflowRef<T>(
      name: name,
      decodeResult: (payload) => decodeResult(payload) as T,
    );
  }

  /// Stable identifier derived from immutable workflow definition fields.
  String get stableId {
    final basis = StringBuffer()
      ..write(name)
      ..write('|')
      ..write(_kind.name)
      ..write('|')
      ..write(version ?? '')
      ..write('|');
    if (isScript) {
      for (final checkpoint in _checkpoints) {
        basis
          ..write(checkpoint.name)
          ..write(':')
          ..write(checkpoint.kind.name)
          ..write(':')
          ..write(checkpoint.autoVersion ? '1' : '0')
          ..write('|');
      }
    } else {
      for (final step in _steps) {
        basis
          ..write(step.name)
          ..write(':')
          ..write(step.kind.name)
          ..write(':')
          ..write(step.autoVersion ? '1' : '0')
          ..write('|');
      }
    }
    return _stableHexDigest(basis.toString());
  }

  /// Serialize the workflow definition for introspection.
  Map<String, Object?> toJson() {
    final serializedSteps = <Map<String, Object?>>[];
    for (var i = 0; i < _steps.length; i += 1) {
      final step = _steps[i].toJson();
      step['position'] = i;
      serializedSteps.add(step);
    }
    final serializedCheckpoints = <Map<String, Object?>>[];
    for (var i = 0; i < _checkpoints.length; i += 1) {
      final checkpoint = _checkpoints[i].toJson();
      checkpoint['position'] = i;
      serializedCheckpoints.add(checkpoint);
    }
    return {
      'name': name,
      'kind': isScript ? 'script' : 'flow',
      if (version != null) 'version': version,
      if (description != null) 'description': description,
      if (metadata != null) 'metadata': metadata,
      if (_steps.isNotEmpty) 'steps': serializedSteps,
      if (_checkpoints.isNotEmpty) 'checkpoints': serializedCheckpoints,
      'edges': _edges.map((edge) => edge.toJson()).toList(),
    };
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

/// Describes a directed edge between workflow steps.
class WorkflowEdge {
  /// Creates a workflow edge from [from] to [to].
  const WorkflowEdge({
    required this.from,
    required this.to,
    this.condition,
  });

  /// Rehydrates an edge from serialized JSON.
  factory WorkflowEdge.fromJson(Map<String, Object?> json) {
    return WorkflowEdge(
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      condition: json['condition']?.toString(),
    );
  }

  /// Originating step identifier.
  final String from;

  /// Destination step identifier.
  final String to;

  /// Optional condition or label for the transition.
  final String? condition;

  /// Serialize edge metadata for workflow introspection.
  Map<String, Object?> toJson() {
    return {
      'from': from,
      'to': to,
      if (condition != null) 'condition': condition,
    };
  }
}

WorkflowDefinitionKind _kindFromJson(Object? value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) return WorkflowDefinitionKind.flow;
  return WorkflowDefinitionKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => WorkflowDefinitionKind.flow,
  );
}

/// Builder used by [Flow] to capture workflow steps in declaration order.
class FlowBuilder {
  /// Creates a builder that appends steps to the provided list.
  FlowBuilder(this._steps);

  final List<FlowStep> _steps;

  /// Adds a step to the workflow.
  ///
  /// [name] must be unique within the flow. The [handler] is replayed from the
  /// beginning whenever the run resumes from a suspension, so it should be
  /// idempotent and leverage [FlowContext] helpers (persisted step results,
  /// resume data) to make forward progress.
  ///
  /// When [autoVersion] is `true`, the runtime stores checkpoints using a
  /// `name#iteration` convention so each execution is tracked separately and
  /// the handler receives the iteration number via [FlowContext.iteration].
  void step<T extends Object?>(
    String name,
    FutureOr<T> Function(FlowContext context) handler, {
    bool autoVersion = false,
    String? title,
    WorkflowStepKind kind = WorkflowStepKind.task,
    Iterable<String> taskNames = const [],
    Map<String, Object?>? metadata,
    PayloadCodec<T>? valueCodec,
  }) {
    _steps.add(
      valueCodec == null
          ? FlowStep(
              name: name,
              handler: handler,
              autoVersion: autoVersion,
              title: title,
              kind: kind,
              taskNames: taskNames,
              metadata: metadata,
            )
          : FlowStep.typed<T>(
              name: name,
              handler: handler,
              valueCodec: valueCodec,
              autoVersion: autoVersion,
              title: title,
              kind: kind,
              taskNames: taskNames,
              metadata: metadata,
            ),
    );
  }
}
