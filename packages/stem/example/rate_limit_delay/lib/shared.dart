import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

import 'rate_limiter.dart';

const _taskName = 'demo.throttled.render';

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: _taskName,
        options: const TaskOptions(
          queue: 'throttled',
          maxRetries: 0,
          visibilityTimeout: Duration(seconds: 60),
          rateLimit: '3/s',
        ),
        entrypoint: _renderEntrypoint,
      ),
    );
  return registry;
}

RoutingRegistry buildRoutingRegistry() {
  final config = RoutingConfig.fromJson({
    'default_queue': 'throttled',
    'queues': {
      'throttled': {
        'priority_range': [1, 5],
      },
    },
  });
  return RoutingRegistry(config);
}

Stem buildStem({
  required Broker broker,
  required TaskRegistry registry,
  ResultBackend? backend,
  RoutingRegistry? routing,
}) {
  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
    routing: routing,
  );
}

Future<RedisStreamsBroker> connectBroker(String uri) =>
    RedisStreamsBroker.connect(uri);

Future<RedisResultBackend> connectBackend(String uri) =>
    RedisResultBackend.connect(uri);

Future<RedisFixedWindowRateLimiter> connectRateLimiter(String uri) =>
    RedisFixedWindowRateLimiter.connect(uri);

List<SignalSubscription> attachSignalLogging() {
  final subscriptions = <SignalSubscription>[];
  subscriptions.add(
    StemSignals.taskReceived.connect((payload, _) {
      stdout.writeln(
        '[signal][received] task=${payload.envelope.name} id=${payload.envelope.id}',
      );
    }),
  );
  subscriptions.add(
    StemSignals.taskRetry.connect((payload, _) {
      stdout.writeln(
        '[signal][retry] task=${payload.envelope.name} retry=${payload.attempt} next=${payload.nextRetryAt.toIso8601String()}',
      );
    }),
  );
  return subscriptions;
}

FutureOr<void> _renderEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final job = args['job'] ?? 'unknown';
  final intendedStart = args['scheduledFor'] as String?;
  final requestedPriority = args['requestedPriority'];
  final appliedPriority = context.meta['appliedPriority'];
  final rateLimited = context.meta['rateLimited'] == true;
  final now = DateTime.now();

  stdout.writeln(
    '[worker][start] job=$job attempt=${context.attempt} '
    'requestedPriority=$requestedPriority appliedPriority=$appliedPriority '
    'rateLimited=$rateLimited started=${now.toIso8601String()} '
    'scheduledFor=${intendedStart ?? 'immediate'}',
  );

  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 250));
  await context.progress(
    0.5,
    data: {'job': job, 'stage': 'halfway'},
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));

  final elapsed = DateTime.now().difference(now);
  stdout.writeln(
    '[worker][done] job=$job elapsed=${elapsed.inMilliseconds}ms '
    'meta=${jsonEncode(context.meta)}',
  );
}

String taskName() => _taskName;
