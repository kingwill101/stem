/// Experimental facade, intentionally not exported by package:stem.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:stem/stem.dart';

export 'package:stem/stem.dart' show PayloadCodec, PayloadCodecRegistry;

void _reportCleanupError(Object error, StackTrace stack) {
  developer.log(
    'Cleanup failed while preserving an earlier WorkflowHost error.',
    name: 'workflow_host_prototype',
    level: 1000,
    error: error,
    stackTrace: stack,
  );
}

// Shared by startup (failure-only cleanup) and the always-cleaned run scope.
Future<T> _withCleanup<T>(
  Future<T> Function() body,
  Future<void> Function() cleanup, {
  bool cleanupOnSuccess = true,
}) async {
  late T value;
  try {
    value = await body();
  } catch (_) {
    try {
      await cleanup();
    } catch (cleanupError, cleanupStack) {
      _reportCleanupError(cleanupError, cleanupStack);
    }
    rethrow;
  }
  // With no primary error, cleanup failure is the scope's failure.
  if (cleanupOnSuccess) await cleanup();
  return value;
}

/// Registration boundary for heterogeneous typed definitions.
abstract interface class HostedDefinition {
  String get name;
  WorkflowDefinition bind(PayloadCodecRegistry codecs);
}

/// An ordinary async function lowered to the existing script runtime.
final class HostedWorkflow<I, R> implements HostedDefinition {
  HostedWorkflow({
    required this.name,
    this.inputCodec,
    this.resultCodec,
    required this.run,
  });

  @override
  final String name;
  final Codec<I, Object?>? inputCodec;
  final Codec<R, Object?>? resultCodec;
  final Future<R> Function(LocalWorkflow context, I input) run;

  @override
  WorkflowDefinition<R> bind(PayloadCodecRegistry codecs) {
    final input = inputCodec ?? codecs.codecFor<I>();
    final output = resultCodec ?? codecs.codecFor<R>();
    return WorkflowScript<R>(
      name: name,
      resultCodec: output,
      run: (context) => run(
        LocalWorkflow._(context, codecs),
        input.decode(context.params['input']),
      ),
    ).definition;
  }
}

/// Named, local checkpoint operations; not remotely routed activities.
final class LocalWorkflow {
  LocalWorkflow._(this._context, this._codecs);
  final WorkflowScriptContext _context;
  final PayloadCodecRegistry _codecs;

  String get runId => _context.runId;

  /// Encodes checkpoint values explicitly so DTOs survive replay.
  Future<T> step<T>(
    String name,
    FutureOr<T> Function() body, {
    Codec<T, Object?>? codec,
  }) async {
    final selected = codec ?? _codecs.codecFor<T>();
    final payload = await _context.step<Object?>(
      name,
      (_) async => {'value': selected.encode(await body())},
    );
    return selected.decode((payload as Map)['value']);
  }
}

/// A typed result future and the underlying workflow run identifier.
final class HostedRun<R> {
  HostedRun._(this.id, this.result);
  final String id;
  final Future<R> result;
}

/// A terminal workflow outcome other than successful completion.
final class HostedWorkflowFailure implements Exception {
  HostedWorkflowFailure(this.runId, this.status, this.error);
  final String runId;
  final WorkflowStatus status;
  final Object? error;

  @override
  String toString() => 'Workflow $runId ended as ${status.name}: $error';
}

/// Owns one existing in-memory app, runtime, and worker.
///
/// Closing rejects new work and ends outstanding result observations, then
/// delegates worker/resource shutdown to the existing app.
final class WorkflowHost {
  WorkflowHost._(
    this._app,
    this._definitions,
    this._codecs,
    this.resultTimeout,
  );

  final StemWorkflowApp _app;
  final Set<HostedDefinition> _definitions;
  final PayloadCodecRegistry _codecs;
  final Duration? resultTimeout;
  final Set<Future<void>> _pending = {};
  Future<void>? _closing;

  bool get isClosed => _closing != null;

  static Future<WorkflowHost> inMemory({
    required Iterable<HostedDefinition> workflows,
    PayloadCodecRegistry? codecs,
    Duration? resultTimeout,
  }) async {
    if (resultTimeout != null && resultTimeout <= Duration.zero) {
      throw ArgumentError.value(
        resultTimeout,
        'resultTimeout',
        'Must be positive',
      );
    }
    final definitions = workflows.toSet();
    final registry = (codecs ?? PayloadCodecRegistry()).snapshot();
    final names = <String>{};
    for (final workflow in definitions) {
      if (!names.add(workflow.name)) {
        throw ArgumentError('Duplicate workflow: ${workflow.name}');
      }
    }
    // Resolve codecs before creating any resources. Each host owns its lowered
    // definitions, so reusing the source definition cannot leak another host's
    // serialization configuration into this one.
    final bound = definitions
        .map((workflow) => workflow.bind(registry))
        .toList();
    final app = await StemWorkflowApp.inMemory(workflows: bound);
    return _withCleanup(
      () async {
        await app.start();
        return WorkflowHost._(app, definitions, registry, resultTimeout);
      },
      app.close,
      cleanupOnSuccess: false,
    );
  }

  /// Creates a host and always closes it after [body], including on errors.
  ///
  /// If both [body] and cleanup fail, preserves the body error and stack,
  /// reporting the cleanup error through `dart:developer` logging. Startup
  /// follows the same rule. Cleanup failure after a successful body propagates.
  static Future<T> run<T>({
    required Iterable<HostedDefinition> workflows,
    required Future<T> Function(WorkflowHost host) body,
    PayloadCodecRegistry? codecs,
    Duration? resultTimeout,
  }) async {
    final host = await inMemory(
      workflows: workflows,
      codecs: codecs,
      resultTimeout: resultTimeout,
    );
    return _withCleanup(() => body(host), host.close);
  }

  Future<R> execute<I, R>(HostedWorkflow<I, R> workflow, I input) async {
    final run = await submit(workflow, input);
    return run.result;
  }

  Future<HostedRun<R>> submit<I, R>(HostedWorkflow<I, R> workflow, I input) {
    if (isClosed) {
      return Future.error(StateError('WorkflowHost is closing or closed.'));
    }
    if (!_definitions.contains(workflow)) {
      return Future.error(ArgumentError('Workflow is not registered on host.'));
    }
    final submitted = _submit(workflow, input);
    // Observe failures immediately, even if a caller reads its handle later.
    // The original result future retains its error for the caller.
    late final Future<void> settled;
    settled = submitted
        .then((run) async {
          await run.result;
        })
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _pending.remove(settled));
    _pending.add(settled);
    return submitted;
  }

  Future<HostedRun<R>> _submit<I, R>(
    HostedWorkflow<I, R> workflow,
    I input,
  ) async {
    final id = await _app.startWorkflow(
      workflow.name,
      params: {
        'input': (workflow.inputCodec ?? _codecs.codecFor<I>()).encode(input),
      },
    );
    return HostedRun._(id, _result(workflow, id));
  }

  Future<R> _result<I, R>(HostedWorkflow<I, R> workflow, String id) async {
    final elapsed = Stopwatch()..start();
    while (!isClosed) {
      // Short, existing runtime observation windows let close stop observing
      // without leaving an uncancellable waitForCompletion polling forever.
      final result = await _app.waitForCompletion<Object?>(
        id,
        timeout: const Duration(milliseconds: 100),
      );
      // Close wins over any outcome returned by an in-flight observation.
      if (isClosed) break;
      if (result == null) {
        throw StateError('Workflow $id disappeared from the store.');
      }
      if (result.isCompleted) {
        return (workflow.resultCodec ?? _codecs.codecFor<R>()).decode(
          result.rawResult,
        );
      }
      if (result.state.isTerminal) {
        throw HostedWorkflowFailure(id, result.status, result.state.lastError);
      }
      final timeout = resultTimeout;
      if (timeout != null && elapsed.elapsed >= timeout) {
        throw TimeoutException(
          'Workflow $id observation timed out; status=${result.status.name}, '
          'lastError=${result.state.lastError}. The run was not cancelled.',
          timeout,
        );
      }
    }
    throw StateError('WorkflowHost closed while observing workflow $id.');
  }

  Future<void> close() => _closing ??= _drainAndClose();

  Future<void> _drainAndClose() async {
    try {
      await Future.wait(_pending.toList());
    } finally {
      await _app.close();
    }
  }
}
