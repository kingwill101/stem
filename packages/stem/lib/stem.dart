/// Distributed task queue and worker framework for Dart.
///
/// Stem is a robust, production-ready background job system designed to
/// orchestrate complex asynchronous workflows across multiple processes
/// and machines.
///
/// ## Key Concepts
///
/// *   **[Stem]**: The main entry point for producers to enqueue tasks.
/// *   **[Broker]**: The transport layer that manages task delivery (e.g.,
///     Redis, SQS, In-Memory).
/// *   **[Worker]**: The runtime that consumes tasks and executes them in
///     isolates or inline.
/// *   **[ResultBackend]**: Persists task status and results for later
///     retrieval and coordination.
/// *   **[Beat]**: A distributed scheduler for recurring tasks using cron or
///     interval specs.
///
/// ## Features
///
/// *   **Typed Task Definitions**: Guarantee type safety for arguments and
///     results using [TaskDefinition].
/// *   **Observability**: First-class support for OpenTelemetry tracing,
///     metrics, and structured logging.
/// *   **Reliability**: Automatic retries with backoff, heartbeats, lease
///     management, and idempotent claims.
/// *   **Scalability**: Managed isolate pools with automatic recycling and
///     dynamic autoscaling.
/// *   **Coordination**: High-level workflows like Chords, Groups, and Chains,
///     plus unique task enforcement.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:stem/stem.dart';
///
/// void main() async {
///   // 1. Define a typed task
///   final addDefinition = TaskDefinition<Map<String, int>, int>(
///     name: 'add_task',
///     encodeArgs: (args) => args,
///   );
///
///   // 2. Setup the registry and handler
///   final registry = SimpleTaskRegistry()
///     ..register(FunctionTaskHandler(
///       name: 'add_task',
///       entrypoint: (context, args) async {
///         return (args['a'] as int) + (args['b'] as int);
///       },
///     ));
///
///   // 3. Initialize Stem with a broker (e.g., In-Memory for testing)
///   final stem = Stem(
///     broker: InMemoryBroker(),
///     registry: registry,
///   );
///
///   // 4. Enqueue work and wait for the result
///   final taskId = await addDefinition.call({
///     'a': 10,
///     'b': 20,
///   }).enqueueWith(stem);
///   final result = await stem.waitForTask<int>(taskId);
///
///   print('Sum is: ${result?.value}'); // Sum is: 30
/// }
/// ```
library;

import 'package:stem/src/core/contracts.dart';
import 'package:stem/src/core/stem.dart';
import 'package:stem/src/scheduler/beat.dart';
import 'package:stem/src/worker/worker.dart';

export 'src/backend/encoding_result_backend.dart';
export 'src/backend/in_memory_backend.dart';
export 'src/bootstrap/factories.dart';
export 'src/bootstrap/stem_app.dart';
export 'src/bootstrap/stem_client.dart';
export 'src/bootstrap/stem_stack.dart';
export 'src/bootstrap/workflow_app.dart';
export 'src/brokers/in_memory_broker.dart';
export 'src/canvas/canvas.dart';
export 'src/control/control_messages.dart';
export 'src/control/file_revoke_store.dart';
export 'src/control/in_memory_revoke_store.dart';
export 'src/control/revoke_store.dart';
export 'src/core/chord_metadata.dart';
export 'src/core/config.dart';
export 'src/core/contracts.dart';
export 'src/core/encoder_keys.dart';
export 'src/core/envelope.dart';
export 'src/core/function_task_handler.dart';
export 'src/core/retry.dart';
export 'src/core/stem.dart';
export 'src/core/task_invocation.dart';
export 'src/core/task_payload_encoder.dart';
export 'src/core/task_result.dart';
export 'src/core/unique_task_coordinator.dart';
export 'src/observability/config.dart';
export 'src/observability/heartbeat.dart';
export 'src/observability/heartbeat_transport.dart';
export 'src/observability/logging.dart';
export 'src/observability/metrics.dart';
export 'src/observability/snapshots.dart';
export 'src/observability/tracing.dart';
export 'src/routing/routing_config.dart';
export 'src/routing/routing_registry.dart';
export 'src/scheduler/beat.dart';
export 'src/scheduler/in_memory_lock_store.dart';
export 'src/scheduler/in_memory_schedule_store.dart';
export 'src/scheduler/schedule_calculator.dart';
export 'src/scheduler/schedule_spec.dart';
export 'src/security/signing.dart';
export 'src/security/tls.dart';
export 'src/signals/emitter.dart';
export 'src/signals/middleware.dart';
export 'src/signals/payloads.dart';
export 'src/signals/signal.dart';
export 'src/signals/stem_signals.dart';
export 'src/testing/fake_stem.dart';
export 'src/worker/worker.dart';
export 'src/worker/worker_config.dart';
export 'src/workflow/workflow.dart';
