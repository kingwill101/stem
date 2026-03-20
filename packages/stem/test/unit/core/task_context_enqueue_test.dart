import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _parentTaskIdKey = 'stem.parentTaskId';
const _rootTaskIdKey = 'stem.rootTaskId';
const _parentAttemptKey = 'stem.parentAttempt';

void main() {
  group('TaskContext.enqueue', () {
    test('exposes typed arg readers on the context', () async {
      final TaskExecutionContext context = TaskContext(
        id: 'parent-0',
        args: const {'invoiceId': 'inv-42'},
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );

      expect(context.requiredArg<String>('invoiceId'), equals('inv-42'));
      expect(context.argOr<String>('tenant', 'global'), equals('global'));
    });

    test('reports progress with JSON DTO payloads', () async {
      Object? progressData;
      final TaskExecutionContext context = TaskContext(
        id: 'parent-0b',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async => progressData = data,
      );

      await context.progressJson(50, const _ProgressUpdate(stage: 'warming'));

      expect(progressData, equals(const {'stage': 'warming'}));
    });

    test('propagates headers/meta and lineage by default', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-1',
        attempt: 2,
        headers: const {'x-trace-id': 'trace-1', 'x-tenant': 'acme'},
        meta: const {'tenant': 'acme', 'region': 'us'},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      final childId = await context.enqueue(
        'tasks.child',
        args: const {'id': 'child-1'},
      );

      expect(childId, equals('recorded-1'));
      final record = enqueuer.last!;
      expect(record.name, equals('tasks.child'));
      expect(record.args, equals({'id': 'child-1'}));
      expect(record.headers['x-trace-id'], equals('trace-1'));
      expect(record.headers['x-tenant'], equals('acme'));
      expect(record.meta['tenant'], equals('acme'));
      expect(record.meta['region'], equals('us'));
      expect(record.meta[_parentTaskIdKey], equals('parent-1'));
      expect(record.meta[_rootTaskIdKey], equals('parent-1'));
      expect(record.meta[_parentAttemptKey], equals(2));
    });

    test('addToParent=false disables lineage propagation', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-2',
        attempt: 1,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      await context.enqueue(
        'tasks.child',
        enqueueOptions: const TaskEnqueueOptions(addToParent: false),
      );

      final record = enqueuer.last!;
      expect(record.meta.containsKey(_parentTaskIdKey), isFalse);
      expect(record.meta.containsKey(_rootTaskIdKey), isFalse);
      expect(record.meta.containsKey(_parentAttemptKey), isFalse);
    });

    test('spawn forwards notBefore', () async {
      final enqueuer = _RecordingEnqueuer();
      final TaskExecutionContext context = TaskContext(
        id: 'parent-2b',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );
      final scheduledAt = DateTime.now().add(const Duration(minutes: 1));

      await context.spawn('tasks.child', notBefore: scheduledAt);

      expect(enqueuer.last?.notBefore, scheduledAt);
    });

    test('spawn delegates to enqueue semantics', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-3',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      await context.spawn('tasks.child', args: const {'value': 42});

      expect(enqueuer.records, hasLength(1));
      expect(enqueuer.records.single.name, equals('tasks.child'));
      expect(enqueuer.records.single.args, equals({'value': 42}));
    });

    test('enqueueValue encodes typed payloads through the supplied codec', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-3b',
        attempt: 1,
        headers: const {'x-trace-id': 'trace-2'},
        meta: const {'tenant': 'acme'},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      await context.enqueueValue(
        'tasks.child',
        const _InvitePayload(email: 'ops@example.com'),
        codec: const PayloadCodec<_InvitePayload>.json(
          decode: _InvitePayload.fromJson,
          typeName: '_InvitePayload',
        ),
      );

      final record = enqueuer.last!;
      expect(record.args, equals({'email': 'ops@example.com'}));
      expect(record.meta[_parentTaskIdKey], equals('parent-3b'));
      expect(record.meta[_parentAttemptKey], equals(1));
      expect(record.headers['x-trace-id'], equals('trace-2'));
    });

    test('merges headers/meta overrides with defaults', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-4',
        attempt: 0,
        headers: const {'x-trace-id': 'trace-1', 'x-tenant': 'acme'},
        meta: const {'tenant': 'acme', 'region': 'us'},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      await context.enqueue(
        'tasks.child',
        headers: const {'x-trace-id': 'trace-override'},
        meta: const {'region': 'eu'},
      );

      final record = enqueuer.last!;
      expect(record.headers['x-trace-id'], equals('trace-override'));
      expect(record.headers['x-tenant'], equals('acme'));
      expect(record.meta['tenant'], equals('acme'));
      expect(record.meta['region'], equals('eu'));
    });

    test('forwards enqueue options', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskContext(
        id: 'parent-5',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      const retryPolicy = TaskRetryPolicy(
        backoff: true,
        backoffMax: Duration(seconds: 30),
        defaultDelay: Duration(seconds: 3),
      );

      await context.enqueue(
        'tasks.child',
        enqueueOptions: TaskEnqueueOptions(
          countdown: const Duration(seconds: 5),
          eta: DateTime.utc(2026, 01, 03, 12),
          expires: DateTime.utc(2026, 01, 03, 12, 5),
          queue: 'critical',
          exchange: 'billing',
          routingKey: 'invoices',
          priority: 9,
          timeLimit: const Duration(seconds: 30),
          softTimeLimit: const Duration(seconds: 10),
          serializer: 'json',
          compression: 'gzip',
          ignoreResult: true,
          shadow: 'shadow.name',
          replyTo: 'reply.queue',
          taskId: 'custom-id-1',
          retry: true,
          retryPolicy: retryPolicy,
          publishConnection: const {'host': 'localhost'},
          producer: const {'confirm': true},
        ),
      );

      final record = enqueuer.last!;
      final options = record.enqueueOptions!;
      expect(options.countdown, equals(const Duration(seconds: 5)));
      expect(options.eta, equals(DateTime.utc(2026, 01, 03, 12)));
      expect(options.expires, equals(DateTime.utc(2026, 01, 03, 12, 5)));
      expect(options.queue, equals('critical'));
      expect(options.exchange, equals('billing'));
      expect(options.routingKey, equals('invoices'));
      expect(options.priority, equals(9));
      expect(options.timeLimit, equals(const Duration(seconds: 30)));
      expect(options.softTimeLimit, equals(const Duration(seconds: 10)));
      expect(options.serializer, equals('json'));
      expect(options.compression, equals('gzip'));
      expect(options.ignoreResult, isTrue);
      expect(options.shadow, equals('shadow.name'));
      expect(options.replyTo, equals('reply.queue'));
      expect(options.taskId, equals('custom-id-1'));
      expect(options.retry, isTrue);
      expect(options.retryPolicy, same(retryPolicy));
      expect(options.publishConnection, equals(const {'host': 'localhost'}));
      expect(options.producer, equals(const {'confirm': true}));
    });
  });

  group('TaskInvocationContext explicit task calls', () {
    test('supports explicit enqueue call overrides', () async {
      final enqueuer = _RecordingEnqueuer();

      final definition = TaskDefinition<_ExampleArgs, void>(
        name: 'tasks.typed',
        encodeArgs: (args) => {'value': args.value},
      );

      final call = definition.buildCall(
        const _ExampleArgs('hello'),
        options: const TaskOptions(queue: 'priority', priority: 7),
      );
      await enqueuer.enqueueCall(call);

      final record = enqueuer.last!;
      expect(record.name, equals('tasks.typed'));
      expect(record.args, equals({'value': 'hello'}));
      expect(record.options.queue, equals('priority'));
      expect(record.options.priority, equals(7));
    });
  });

  group('TaskContext workflows', () {
    test(
      'delegates typed child workflow starts to the configured caller',
      () async {
        final workflows = _RecordingWorkflowCaller();
        final context = TaskContext(
          id: 'parent-workflow-task',
          attempt: 0,
          headers: const {},
          meta: const {},
          heartbeat: () {},
          extendLease: (_) async {},
          progress: (_, {data}) async {},
          workflows: workflows,
        );
        final definition = WorkflowRef<Map<String, Object?>, String>(
          name: 'workflow.child',
          encodeParams: (params) => params,
        );

        final runId = await context.startWorkflowRef(
          definition,
          const {'value': 'child'},
        );
        final result = await context.waitForWorkflowRef(
          runId,
          definition,
        );

        expect(runId, 'run-1');
        expect(workflows.lastWorkflowName, 'workflow.child');
        expect(workflows.lastWorkflowParams, {'value': 'child'});
        expect(workflows.waitedRunId, 'run-1');
        expect(result?.value, 'child-result');
      },
    );

    test('throws when no workflow caller is configured', () {
      final context = TaskContext(
        id: 'no-workflows',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );
      final definition = WorkflowRef<Map<String, Object?>, String>(
        name: 'workflow.child',
        encodeParams: (params) => params,
      );

      expect(
        () => context.startWorkflowRef(definition, const {'value': 'child'}),
        throwsStateError,
      );
      expect(
        () => context.waitForWorkflowRef('run-1', definition),
        throwsStateError,
      );
    });

    test('builds child workflow starts directly from the context', () async {
      final workflows = _RecordingWorkflowCaller();
      final context = TaskContext(
        id: 'workflow-builder-task',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        workflows: workflows,
      );
      final definition = WorkflowRef<Map<String, Object?>, String>(
        name: 'workflow.child',
        encodeParams: (params) => params,
      );

      final call = definition.buildStart(
        params: const {'value': 'child'},
        parentRunId: 'parent-task',
      );
      final runId = await context.startWorkflowCall(call);
      final result = await call.definition.waitFor(context, runId);

      expect(workflows.lastWorkflowName, 'workflow.child');
      expect(workflows.lastWorkflowParams, {'value': 'child'});
      expect(workflows.lastParentRunId, 'parent-task');
      expect(workflows.waitedRunId, 'run-1');
      expect(result?.value, 'child-result');
    });
  });

  group('TaskContext workflow events', () {
    test('delegates typed workflow events to the configured emitter', () async {
      final workflowEvents = _RecordingWorkflowEventEmitter();
      final context = TaskContext(
        id: 'event-task',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        workflowEvents: workflowEvents,
      );
      const event = WorkflowEventRef<Map<String, Object?>>(
        topic: 'workflow.ready',
      );

      await context.emitValue('workflow.inline', const {'value': 'inline'});
      await context.emitEvent(event, const {'value': 'event'});

      expect(workflowEvents.topics, ['workflow.inline', 'workflow.ready']);
      expect(workflowEvents.payloads, [
        {'value': 'inline'},
        {'value': 'event'},
      ]);
    });

    test('throws when no workflow event emitter is configured', () {
      final context = TaskContext(
        id: 'no-workflow-events',
        attempt: 0,
        headers: const {},
        meta: const {},
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
      );

      expect(
        () => context.emitValue('workflow.ready', const {'value': true}),
        throwsStateError,
      );
    });
  });
}

class _ProgressUpdate {
  const _ProgressUpdate({required this.stage});

  final String stage;

  Map<String, dynamic> toJson() => {'stage': stage};
}

class _ExampleArgs {
  const _ExampleArgs(this.value);
  final String value;
}

class _RecordedEnqueue {
  _RecordedEnqueue({
    required this.name,
    required this.args,
    required this.headers,
    required this.meta,
    required this.options,
    required this.notBefore,
    required this.enqueueOptions,
  });

  final String name;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final TaskOptions options;
  final DateTime? notBefore;
  final TaskEnqueueOptions? enqueueOptions;
}

class _RecordingEnqueuer implements TaskEnqueuer {
  final List<_RecordedEnqueue> records = [];

  _RecordedEnqueue? get last => records.isEmpty ? null : records.last;

  @override
  Future<String> enqueue(
    String name, {
    Map<String, Object?> args = const {},
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) async {
    records.add(
      _RecordedEnqueue(
        name: name,
        args: Map<String, Object?>.from(args),
        headers: Map<String, String>.from(headers),
        meta: Map<String, Object?>.from(meta),
        options: options,
        notBefore: notBefore,
        enqueueOptions: enqueueOptions,
      ),
    );
    return 'recorded-${records.length}';
  }

  @override
  Future<String> enqueueCall<TArgs, TResult>(
    TaskCall<TArgs, TResult> call, {
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      call.name,
      args: call.encodeArgs(),
      headers: call.headers,
      options: call.resolveOptions(),
      notBefore: call.notBefore,
      meta: call.meta,
      enqueueOptions: enqueueOptions,
    );
  }

  @override
  Future<String> enqueueValue<T>(
    String name,
    T value, {
    PayloadCodec<T>? codec,
    Map<String, String> headers = const {},
    TaskOptions options = const TaskOptions(),
    DateTime? notBefore,
    Map<String, Object?> meta = const {},
    TaskEnqueueOptions? enqueueOptions,
  }) {
    return enqueue(
      name,
      args: _encodeTestTaskArgs(name, value, codec: codec),
      headers: headers,
      options: options,
      notBefore: notBefore,
      meta: meta,
      enqueueOptions: enqueueOptions,
    );
  }
}

Map<String, Object?> _encodeTestTaskArgs<T>(
  String name,
  T value, {
  PayloadCodec<T>? codec,
}) {
  final payload = codec == null ? value : codec.encode(value);
  if (payload is Map<String, Object?>) {
    return Map<String, Object?>.from(payload);
  }
  if (payload is Map) {
    return payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  throw StateError(
    'Task payload for $name must encode to Map<String, Object?>, got '
    '${payload.runtimeType}.',
  );
}

class _InvitePayload {
  const _InvitePayload({required this.email});

  factory _InvitePayload.fromJson(Map<String, dynamic> json) {
    return _InvitePayload(email: json['email']! as String);
  }

  final String email;

  Map<String, Object?> toJson() => {'email': email};
}

class _RecordingWorkflowCaller implements WorkflowCaller {
  String? lastWorkflowName;
  Map<String, Object?>? lastWorkflowParams;
  String? lastParentRunId;
  String? waitedRunId;

  @override
  Future<String> startWorkflowRef<TParams, TResult extends Object?>(
    WorkflowRef<TParams, TResult> definition,
    TParams params, {
    String? parentRunId,
    Duration? ttl,
    WorkflowCancellationPolicy? cancellationPolicy,
  }) async {
    lastWorkflowName = definition.name;
    lastWorkflowParams = definition.encodeParams(params);
    lastParentRunId = parentRunId;
    return 'run-1';
  }

  @override
  Future<String> startWorkflowCall<TParams, TResult extends Object?>(
    WorkflowStartCall<TParams, TResult> call,
  ) {
    return startWorkflowRef(
      call.definition,
      call.params,
      parentRunId: call.parentRunId,
      ttl: call.ttl,
      cancellationPolicy: call.cancellationPolicy,
    );
  }

  @override
  Future<WorkflowResult<TResult>?>
  waitForWorkflowRef<TParams, TResult extends Object?>(
    String runId,
    WorkflowRef<TParams, TResult> definition, {
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration? timeout,
  }) async {
    waitedRunId = runId;
    return WorkflowResult<TResult>(
      runId: runId,
      status: WorkflowStatus.completed,
      state: RunState(
        id: runId,
        workflow: definition.name,
        status: WorkflowStatus.completed,
        cursor: 0,
        params: const {},
        createdAt: DateTime.utc(2026),
        result: 'child-result',
      ),
      value: definition.decode('child-result'),
      rawResult: 'child-result',
    );
  }
}

class _RecordingWorkflowEventEmitter implements WorkflowEventEmitter {
  final List<String> topics = <String>[];
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<void> emitValue<T>(
    String topic,
    T value, {
    PayloadCodec<T>? codec,
  }) async {
    topics.add(topic);
    payloads.add(Map<String, Object?>.from(value! as Map));
  }

  @override
  Future<void> emitEvent<T>(WorkflowEventRef<T> event, T value) {
    return emitValue(event.topic, value, codec: event.codec);
  }
}
