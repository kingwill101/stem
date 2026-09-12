import 'dart:async';
import 'dart:convert';

import 'package:stem/src/core/payload_codec_registry.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_script_context.dart';
import 'package:stem/src/workflow/host/hosted_result.dart';

/// Registration boundary for heterogeneous typed hosted workflows.
abstract interface class HostedDefinition {
  /// Stable workflow name used for registration and persisted runs.
  String get name;

  /// Lowers this definition to the existing script runtime.
  WorkflowDefinition bind(PayloadCodecRegistry codecs);
}

/// An immutable async Dart workflow lowered to the existing script runtime.
///
/// Re-register executable definitions when reopening a persistent host.
/// Names and checkpoint order must remain compatible with persisted runs.
final class HostedWorkflow<I, R> implements HostedDefinition {
  /// Creates a typed hosted workflow.
  const HostedWorkflow({
    required this.name,
    required this.run,
    this.inputCodec,
    this.resultCodec,
  });

  @override
  final String name;

  /// Input codec, or the host registry's codec for [I].
  final Codec<I, Object?>? inputCodec;

  /// Result codec, or the host registry's codec for [R].
  final Codec<R, Object?>? resultCodec;

  /// Workflow body. Side effects belong inside named checkpoints.
  final FutureOr<R> Function(HostedWorkflowContext context, I input) run;

  @override
  WorkflowDefinition<Map<String, Object?>> bind(PayloadCodecRegistry codecs) {
    final registry = codecs.snapshot();
    final input = inputCodec ?? registry.codecFor<I>();
    final result = resultCodec ?? registry.codecFor<R>();
    // WorkflowDefinition.encodeResult intentionally preserves a raw null for
    // legacy definitions. Return a non-null host envelope so the selected
    // codec is still called for nullable terminal values.
    //
    // This is a new hosted-run format; there are no released hosted runs that
    // need decoding without this envelope.
    Future<Map<String, Object?>> hostedBody(
      WorkflowScriptContext context,
    ) async {
      return encodeHostedResult(
        result.encode(
          await run(
            HostedWorkflowContext._(context, registry),
            input.decode(context.params['input']),
          ),
        ),
      );
    }

    return WorkflowDefinition<Map<String, Object?>>.script(
      name: name,
      run: hostedBody,
    );
  }
}

/// Typed named checkpoints and durable waits, not remotely routed activities.
final class HostedWorkflowContext {
  HostedWorkflowContext._(this._script, this._codecs);

  final WorkflowScriptContext _script;
  final PayloadCodecRegistry _codecs;

  /// Persisted run identifier.
  String get runId => _script.runId;

  /// Registered workflow name.
  String get workflow => _script.workflow;

  /// Executes or replays a named checkpoint with an explicit value envelope.
  ///
  /// The envelope preserves encoded null values on checkpoint replay.
  Future<T> step<T>(
    String name,
    FutureOr<T> Function() body, {
    Codec<T, Object?>? codec,
  }) async {
    final selected = codec ?? _codecs.codecFor<T>();
    final stored = await _script.step<Object?>(
      name,
      (_) async => <String, Object?>{'value': selected.encode(await body())},
    );
    return selected.decode(_valueEnvelope(stored, name));
  }

  /// Suspends once at a named checkpoint, then continues when resumed.
  Future<void> sleep(String name, Duration duration) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'Must not be negative.');
    }
    await _script.step<Object?>(name, (context) async {
      if (context is WorkflowScriptResumeDetails &&
          (context as WorkflowScriptResumeDetails).isResuming) {
        return <String, Object?>{'value': null};
      }
      await context.sleep(duration, data: const {'value': null});
      return <String, Object?>{'value': null};
    });
  }

  /// Waits at a named checkpoint for an existing typed event topic.
  ///
  /// Event codecs must encode to a string-keyed map. The raw map is
  /// checkpointed before decoding; codecs may decode it to a nullable value.
  /// No host-specific envelope is added to the event transport.
  ///
  /// Deadline expiry throws [TimeoutException]. If the workflow catches it,
  /// subsequent replay throws the same timeout rather than registering again.
  /// Timeout detection uses runtime control metadata, never user payload keys.
  Future<T> awaitEvent<T>(
    String name,
    WorkflowEventRef<T> event, {
    DateTime? deadline,
  }) async {
    final selected = event.codec ?? _codecs.codecFor<T>();
    final stored = await _script.step<Object?>(name, (context) async {
      if (context is! WorkflowScriptResumeDetails) {
        throw UnsupportedError(
          'Hosted event waits require runtime resume details.',
        );
      }
      final details = context as WorkflowScriptResumeDetails;
      final resume = context.takeResumeData();
      if (details.isEventTimeout) {
        return <String, Object?>{'timedOut': true};
      }
      if (details.isResuming) {
        if (resume is! Map<String, Object?>) {
          throw StateError(
            'Event ${event.topic} resumed without a map payload.',
          );
        }
        return <String, Object?>{'value': resume};
      }
      await context.awaitEvent(event.topic, deadline: deadline);
      return <String, Object?>{'value': null};
    });
    if (stored is Map && stored['timedOut'] == true) {
      throw TimeoutException('Event ${event.topic} deadline expired.');
    }
    return selected.decode(_valueEnvelope(stored, name));
  }

  static Object? _valueEnvelope(Object? stored, String name) {
    if (stored is! Map || !stored.containsKey('value')) {
      throw StateError(
        'Checkpoint "$name" returned an invalid value envelope.',
      );
    }
    return stored['value'];
  }
}
