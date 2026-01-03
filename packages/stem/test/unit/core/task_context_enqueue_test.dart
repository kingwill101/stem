import 'dart:async';

import 'package:stem/stem.dart';
import 'package:test/test.dart';

const _parentTaskIdKey = 'stem.parentTaskId';
const _rootTaskIdKey = 'stem.rootTaskId';
const _parentAttemptKey = 'stem.parentAttempt';

void main() {
  group('TaskContext.enqueue', () {
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

      final retryPolicy = TaskRetryPolicy(
        backoff: true,
        backoffMax: const Duration(seconds: 30),
        jitter: true,
        defaultDelay: const Duration(seconds: 3),
      );

      await context.enqueue(
        'tasks.child',
        enqueueOptions: TaskEnqueueOptions(
          countdown: const Duration(seconds: 5),
          eta: DateTime.utc(2026, 01, 03, 12, 0, 0),
          expires: DateTime.utc(2026, 01, 03, 12, 5, 0),
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
      expect(options.eta, equals(DateTime.utc(2026, 01, 03, 12, 0, 0)));
      expect(options.expires, equals(DateTime.utc(2026, 01, 03, 12, 5, 0)));
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

  group('TaskInvocationContext builder', () {
    test('supports fluent enqueue builder API', () async {
      final enqueuer = _RecordingEnqueuer();
      final context = TaskInvocationContext.local(
        id: 'invocation-1',
        headers: const {},
        meta: const {},
        attempt: 0,
        heartbeat: () {},
        extendLease: (_) async {},
        progress: (_, {data}) async {},
        enqueuer: enqueuer,
      );

      final definition = TaskDefinition<_ExampleArgs, void>(
        name: 'tasks.typed',
        encodeArgs: (args) => {'value': args.value},
      );

      final builder = context.enqueueBuilder(
        definition: definition,
        args: const _ExampleArgs('hello'),
      );

      await builder.queue('priority').priority(7).enqueueWith(context);

      final record = enqueuer.last!;
      expect(record.name, equals('tasks.typed'));
      expect(record.args, equals({'value': 'hello'}));
      expect(record.options.queue, equals('priority'));
      expect(record.options.priority, equals(7));
    });
  });
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
    required this.enqueueOptions,
  });

  final String name;
  final Map<String, Object?> args;
  final Map<String, String> headers;
  final Map<String, Object?> meta;
  final TaskOptions options;
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
      meta: call.meta,
      enqueueOptions: enqueueOptions,
    );
  }
}
