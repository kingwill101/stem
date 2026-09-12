import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:stem/src/bootstrap/workflow_app.dart';
import 'package:stem/src/core/payload_codec_registry.dart';
import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/core/workflow_event_ref.dart';
import 'package:stem/src/workflow/core/workflow_status.dart';
import 'package:stem/src/workflow/host/hosted_workflow.dart';
import 'package:stem/src/workflow/runtime/workflow_views.dart';

/// Owns or borrows an existing workflow app, without adding another engine.
///
/// [create] and [inMemory] start and own their apps. [attach] never starts or
/// closes the borrowed app. Closing stops local observation, not durable runs.
final class WorkflowHost {
  WorkflowHost._(
    this._app,
    this._definitions,
    this._codecs,
    this.resultTimeout,
    this.pollInterval, {
    required bool ownsApp,
  }) : _ownsApp = ownsApp;

  final StemWorkflowApp _app;
  final Map<String, HostedDefinition> _definitions;
  final PayloadCodecRegistry _codecs;
  final bool _ownsApp;
  final Set<Future<void>> _admitted = {};
  final Map<String, _RunObservation> _observations = {};
  Future<void>? _closing;
  bool _closed = false;

  /// Observation deadline from first result access, not an execution limit.
  final Duration? resultTimeout;

  /// Interval between shared store reads for active snapshot subscriptions.
  final Duration pollInterval;

  /// Whether close has begun and new operations are rejected.
  bool get isClosed => _closed;

  /// Creates, starts, and owns an app supplied by [createApp].
  ///
  /// The factory must register the supplied bound definitions unchanged and
  /// clean up if it throws before returning an app. Startup failure closes a
  /// returned app, preserving the startup error if cleanup also fails.
  static Future<WorkflowHost> create({
    required Future<StemWorkflowApp> Function(List<WorkflowDefinition>)
    createApp,
    required Iterable<HostedDefinition> workflows,
    PayloadCodecRegistry? codecs,
    Duration? resultTimeout,
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    _validateDurations(resultTimeout, pollInterval);
    final registry = (codecs ?? PayloadCodecRegistry()).snapshot();
    final entries = _index(workflows);
    final bound = List<WorkflowDefinition>.unmodifiable(
      entries.values.map((definition) => definition.bind(registry)),
    );
    final app = await createApp(bound);
    try {
      for (final definition in bound) {
        if (!identical(
          app.runtime.registry.lookup(definition.name),
          definition,
        )) {
          throw ArgumentError(
            'The app factory must register ${definition.name} unchanged.',
          );
        }
      }
      await app.start();
      return WorkflowHost._(
        app,
        entries,
        registry,
        resultTimeout,
        pollInterval,
        ownsApp: true,
      );
    } on Object catch (error, stack) {
      try {
        await app.close();
      } on Object catch (cleanupError, cleanupStack) {
        developer.log(
          'WorkflowHost startup cleanup failed.',
          name: 'stem.workflow.host',
          error: cleanupError,
          stackTrace: cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Creates and starts an owned in-memory workflow app.
  static Future<WorkflowHost> inMemory({
    required Iterable<HostedDefinition> workflows,
    PayloadCodecRegistry? codecs,
    Duration? resultTimeout,
    Duration pollInterval = const Duration(milliseconds: 100),
  }) => create(
    workflows: workflows,
    codecs: codecs,
    resultTimeout: resultTimeout,
    pollInterval: pollInterval,
    createApp: (definitions) =>
        StemWorkflowApp.inMemory(workflows: definitions),
  );

  /// Borrows an app without starting, stopping, or modifying its registry.
  ///
  /// The caller must register these hosted definitions with equivalent codecs.
  /// Definition IDs are checked, but bodies and codec behavior cannot be
  /// inferred from a manifest.
  static Future<WorkflowHost> attach({
    required StemWorkflowApp app,
    required Iterable<HostedDefinition> workflows,
    PayloadCodecRegistry? codecs,
    Duration? resultTimeout,
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    _validateDurations(resultTimeout, pollInterval);
    final registry = (codecs ?? PayloadCodecRegistry()).snapshot();
    final entries = _index(workflows);
    for (final definition in entries.values) {
      final bound = definition.bind(registry);
      final existing = app.runtime.registry.lookup(bound.name);
      if (existing == null || existing.stableId != bound.stableId) {
        throw ArgumentError('Attached app does not register ${bound.name}.');
      }
    }
    return WorkflowHost._(
      app,
      entries,
      registry,
      resultTimeout,
      pollInterval,
      ownsApp: false,
    );
  }

  /// Persists and enqueues a new run using the registered input codec.
  Future<HostedRun<R>> submit<I, R>(HostedWorkflow<I, R> workflow, I input) =>
      _operation(() async {
        final registered = _registered(workflow);
        final codec = registered.inputCodec ?? _codecs.codecFor<I>();
        final id = await _app.startWorkflow(
          registered.name,
          params: {'input': codec.encode(input)},
        );
        return _handle(registered, id);
      });

  /// Submits a workflow and observes its typed terminal result.
  Future<R> execute<I, R>(HostedWorkflow<I, R> workflow, I input) async =>
      (await submit(workflow, input)).result;

  /// Reattaches to a persisted run without submitting another execution.
  ///
  /// Fresh equivalent definitions are accepted; registered callbacks and codecs
  /// remain authoritative. Names and both generic types must match.
  Future<HostedRun<R>> observe<I, R>(
    HostedWorkflow<I, R> workflow,
    String id,
  ) => _operation(() async {
    final registered = _registered(workflow);
    await _read(id, registered.name);
    return _handle(registered, id);
  });

  HostedWorkflow<I, R> _registered<I, R>(HostedWorkflow<I, R> workflow) {
    final registered = _definitions[workflow.name];
    if (registered is! HostedWorkflow<I, R> ||
        registered.runtimeType != workflow.runtimeType) {
      throw ArgumentError(
        'Workflow ${workflow.name} is not registered with these input/result types.',
      );
    }
    return registered;
  }

  HostedRun<R> _handle<I, R>(HostedWorkflow<I, R> workflow, String id) =>
      HostedRun._(
        this,
        id,
        workflow.name,
        workflow.resultCodec ?? _codecs.codecFor<R>(),
      );

  /// Emits on a topic, potentially resuming multiple matching runs.
  ///
  /// This is not run-targeted dispatch. The existing map-based event transport
  /// applies; no host-specific event envelope is added. The explicit event
  /// codec or host registry codec encodes the typed value, including null.
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) =>
      _operation(() {
        final codec = event.codec ?? _codecs.codecFor<T>();
        return _app.emitValue(event.topic, codec.encode(value));
      });

  Future<WorkflowRunView> _read(String id, String workflow) async {
    final view = await _app.viewRun(id);
    if (view == null || view.workflow != workflow) {
      throw StateError('Run $id does not exist as workflow $workflow.');
    }
    return view;
  }

  Future<WorkflowRunView> _status(String id, String workflow) =>
      _operation(() => _read(id, workflow));

  Future<void> _cancel(String id, String workflow) => _operation(() async {
    await _read(id, workflow);
    await _app.runtime.cancelWorkflow(id);
  });

  Stream<WorkflowRunView> _watch(String id, String workflow) => Stream.multi(
    (listener) {
      if (_closed) {
        listener.addError(StateError('WorkflowHost is closed.'));
        unawaited(listener.close());
        return;
      }
      _observations
          .putIfAbsent(
            id,
            () => _RunObservation(this, id, workflow),
          )
          .listen(listener);
    },
  );

  Future<R> _result<R>(
    String id,
    String workflow,
    Codec<R, Object?> codec,
  ) async {
    _ensureOpen();
    final outcome = Completer<WorkflowRunView>();
    final elapsed = Stopwatch()..start();
    final timeout = resultTimeout;
    void timedOut() {
      if (!outcome.isCompleted) {
        outcome.completeError(
          TimeoutException(
            'Workflow $id observation timed out; the run was not cancelled.',
            timeout,
          ),
        );
      }
    }

    final timer = timeout == null ? null : Timer(timeout, timedOut);
    final subscription = _watch(id, workflow).listen(
      (view) {
        if (outcome.isCompleted) return;
        if (_closed) {
          outcome.completeError(StateError('WorkflowHost is closed.'));
        } else if (timeout != null && elapsed.elapsed >= timeout) {
          timedOut();
        } else if (_terminal(view)) {
          outcome.complete(view);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!outcome.isCompleted) outcome.completeError(error, stack);
      },
      onDone: () {
        if (!outcome.isCompleted) {
          outcome.completeError(
            StateError('WorkflowHost closed while observing workflow $id.'),
          );
        }
      },
    );
    try {
      final view = await outcome.future;
      _ensureOpen();
      if (view.status != WorkflowStatus.completed) {
        throw HostedWorkflowFailure(id, view.status, view.lastError);
      }
      return codec.decode(view.result);
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  Future<T> _operation<T>(Future<T> Function() body) {
    _ensureOpen();
    final operation = Future<T>.sync(body);
    late final Future<void> settled;
    settled = operation
        .then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        )
        .whenComplete(() => _admitted.remove(settled));
    _admitted.add(settled);
    return operation;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('WorkflowHost is closed.');
  }

  /// Stops observations and joins admitted operations before owned cleanup.
  ///
  /// Does not cancel runs or forcibly interrupt Dart bodies.
  /// Joining pending writes may exceed an observation deadline.
  /// Repeated calls are idempotent.
  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    for (final observation in _observations.values.toList()) {
      observation.close();
    }
    return _closing = _drain();
  }

  Future<void> _drain() async {
    await Future.wait(_admitted.toList());
    if (_ownsApp) await _app.close();
  }

  static Map<String, HostedDefinition> _index(
    Iterable<HostedDefinition> definitions,
  ) {
    final result = <String, HostedDefinition>{};
    for (final definition in definitions) {
      if (definition.name.trim().isEmpty ||
          result.containsKey(definition.name)) {
        throw ArgumentError(
          'Empty or duplicate workflow name: ${definition.name}',
        );
      }
      result[definition.name] = definition;
    }
    return Map.unmodifiable(result);
  }

  static void _validateDurations(Duration? timeout, Duration interval) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'resultTimeout', 'Must be positive.');
    }
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'pollInterval', 'Must be positive.');
    }
  }
}

bool _terminal(WorkflowRunView view) =>
    view.status == WorkflowStatus.completed ||
    view.status == WorkflowStatus.failed ||
    view.status == WorkflowStatus.cancelled;

// One polling loop per actively observed run, shared across subscriptions.
class _RunObservation {
  _RunObservation(this.host, this.id, this.workflow);
  final WorkflowHost host;
  final String id;
  final String workflow;
  final Set<MultiStreamController<WorkflowRunView>> listeners = {};
  WorkflowRunView? latest;
  bool polling = false;
  bool stopped = false;
  Timer? _timer;
  Completer<void>? _wake;

  void listen(MultiStreamController<WorkflowRunView> listener) {
    listeners.add(listener);
    listener.onCancel = () {
      listeners.remove(listener);
      if (listeners.isEmpty) _wakeUp();
    };
    listener.onResume = () {
      if (latest != null && !stopped) listener.add(latest!);
    };
    if (latest != null) listener.add(latest!);
    if (!polling) unawaited(_poll());
  }

  Future<void> _poll() async {
    polling = true;
    try {
      while (!host.isClosed && !stopped && listeners.isNotEmpty) {
        final view = await host._operation(() => host._read(id, workflow));
        if (host.isClosed || stopped) break;
        if (latest == null ||
            !const DeepCollectionEquality().equals(
              latest!.toJson(),
              view.toJson(),
            )) {
          latest = view;
          for (final listener in listeners.toList()) {
            if (!listener.isPaused || _terminal(view)) listener.add(view);
          }
        }
        if (_terminal(view)) {
          close();
          break;
        }
        if (listeners.isEmpty) break;
        final wake = Completer<void>();
        _wake = wake;
        _timer = Timer(host.pollInterval, _wakeUp);
        await wake.future;
      }
    } on Object catch (error, stack) {
      if (!host.isClosed && !stopped) {
        for (final listener in listeners.toList()) {
          listener.addError(error, stack);
        }
      }
      close();
    } finally {
      polling = false;
      if (listeners.isEmpty && identical(host._observations[id], this)) {
        host._observations.remove(id);
      }
    }
  }

  void _wakeUp() {
    _timer?.cancel();
    _timer = null;
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  void close() {
    if (stopped) return;
    stopped = true;
    _wakeUp();
    for (final listener in listeners.toList()) {
      unawaited(listener.close());
    }
    listeners.clear();
    if (identical(host._observations[id], this)) {
      host._observations.remove(id);
    }
  }
}

/// A typed handle attached to one persisted run.
final class HostedRun<R> {
  HostedRun._(this._host, this.id, this.workflow, this._codec);
  final WorkflowHost _host;
  final Codec<R, Object?> _codec;
  Future<R>? _result;

  /// Persisted identifier, usable with [WorkflowHost.observe] after restart.
  final String id;

  /// Registered workflow name.
  final String workflow;

  /// Lazily observes and caches the terminal outcome for this handle.
  ///
  /// Its timeout starts on first access. Reattach to observe after a timeout.
  /// Errors remain available without an unhandled background error.
  Future<R> get result {
    if (_result == null) {
      final result = _host._result(id, workflow, _codec);
      unawaited(
        result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      _result = result;
    }
    return _result!;
  }

  /// Reads the current persisted snapshot.
  Future<WorkflowRunView> status() => _host._status(id, workflow);

  /// Observes snapshots, not a replayable lifecycle history.
  ///
  /// Concurrent subscriptions share polling. Paused subscriptions may skip
  /// intermediate snapshots. Terminal state or host closure ends observation.
  Stream<WorkflowRunView> watch() => _host._watch(id, workflow);

  /// Requests durable cancellation without forcibly interrupting Dart code.
  Future<void> cancel() => _host._cancel(id, workflow);
}

/// A persisted terminal outcome other than successful completion.
final class HostedWorkflowFailure implements Exception {
  /// Describes a failed or cancelled run.
  HostedWorkflowFailure(this.runId, this.status, this.error);

  /// Persisted run identifier.
  final String runId;

  /// Terminal workflow status.
  final WorkflowStatus status;

  /// Persisted failure details, if available.
  final Object? error;

  @override
  String toString() => 'Workflow $runId ended as ${status.name}: $error';
}
