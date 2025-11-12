import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

import '../support/inline_task_handler.dart';

void main() {
  test('worker recovers from failure and reprocesses task', () async {
    final environment = await _ChaosEnvironment.create();
    addTearDown(environment.dispose);

    final broker = environment.broker;
    final backend = environment.backend;

    final succeeded = Completer<void>();

    final registry = SimpleTaskRegistry()
      ..register(
        InlineTaskHandler<void>(
          name: 'chaos.resilience',
          onCall: (context, _) async {
            if (context.attempt == 0) {
              throw StateError('simulated crash');
            }
            if (!succeeded.isCompleted) {
              succeeded.complete();
            }
          },
          options: const TaskOptions(maxRetries: 2),
        ),
      );

    final stem = Stem(broker: broker, registry: registry, backend: backend);
    final worker = Worker(
      broker: broker,
      registry: registry,
      backend: backend,
      consumerName: 'chaos-worker',
      heartbeatTransport: const NoopHeartbeatTransport(),
      retryStrategy: ExponentialJitterRetryStrategy(
        base: const Duration(milliseconds: 200),
        max: const Duration(seconds: 1),
      ),
    );

    await worker.start();
    final taskId = await stem.enqueue('chaos.resilience');

    await succeeded.future.timeout(const Duration(seconds: 15));
    final finalStatus = await _waitForSucceededStatus(backend, taskId);

    expect(finalStatus.state, equals(TaskState.succeeded));

    await worker.shutdown();
  }, tags: const ['chaos']);
}

Future<TaskStatus> _waitForSucceededStatus(
  ResultBackend backend,
  String taskId, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final status = await backend.get(taskId);
    if (status != null && status.state == TaskState.succeeded) {
      return status;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw TimeoutException('Timed out waiting for $taskId to succeed');
}

class _ChaosEnvironment {
  _ChaosEnvironment({
    required this.broker,
    required this.backend,
    required this.dispose,
  });

  final Broker broker;
  final ResultBackend backend;
  final Future<void> Function() dispose;

  static Future<_ChaosEnvironment> create() async {
    final redisUrl = Platform.environment['STEM_CHAOS_REDIS_URL'];
    if (redisUrl != null && redisUrl.isNotEmpty) {
      final namespace =
          'stem-chaos-test-${DateTime.now().millisecondsSinceEpoch}';
      final broker = await RedisStreamsBroker.connect(
        redisUrl,
        namespace: namespace,
        blockTime: const Duration(seconds: 1),
      );
      final backend = await RedisResultBackend.connect(
        redisUrl,
        namespace: namespace,
      );
      return _ChaosEnvironment(
        broker: broker,
        backend: backend,
        dispose: () async {
          await broker.close();
          await backend.close();
        },
      );
    }

    final broker = InMemoryBroker();
    final backend = InMemoryResultBackend();
    return _ChaosEnvironment(
      broker: broker,
      backend: backend,
      dispose: () async {
        broker.dispose();
      },
    );
  }
}
