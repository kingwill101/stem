import 'package:stem/src/core/payload_codec.dart';
import 'package:stem/src/workflow/core/workflow_checkpoint.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';

/// High-level workflow facade that allows scripts to be authored as a single
/// async function using `step`, `sleep`, and `awaitEvent` helpers.
///
/// In script workflows, the `run` function is the execution plan. Declared
/// checkpoints are optional metadata used for tooling, manifests, and
/// dashboards.
class WorkflowScript<T extends Object?> {
  /// Creates a workflow script definition.
  WorkflowScript({
    required String name,
    required WorkflowScriptBody<T> run,
    Iterable<WorkflowCheckpoint> checkpoints = const [],
    String? version,
    String? description,
    Map<String, Object?>? metadata,
    PayloadCodec<T>? resultCodec,
  }) : definition = WorkflowDefinition<T>.script(
         name: name,
         run: run,
         checkpoints: checkpoints,
         version: version,
         description: description,
         metadata: metadata,
         resultCodec: resultCodec,
       );

  /// The constructed workflow definition.
  final WorkflowDefinition<T> definition;
}
