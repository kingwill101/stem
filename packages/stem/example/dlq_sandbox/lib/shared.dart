import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

const _queueName = 'default';
const _taskName = 'billing.invoice.process';

SimpleTaskRegistry buildRegistry() {
  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: _taskName,
        options: const TaskOptions(
          queue: _queueName,
          maxRetries: 2,
          visibilityTimeout: Duration(seconds: 60),
        ),
        entrypoint: _invoiceEntrypoint,
      ),
    );
  return registry;
}

Stem buildStem({
  required Broker broker,
  required TaskRegistry registry,
  ResultBackend? backend,
}) {
  return Stem(
    broker: broker,
    registry: registry,
    backend: backend,
  );
}

Future<RedisStreamsBroker> connectBroker(String uri) =>
    RedisStreamsBroker.connect(uri);

Future<RedisResultBackend> connectBackend(String uri) =>
    RedisResultBackend.connect(uri);

List<SignalSubscription> attachSignalLogging() {
  final subs = <SignalSubscription>[];
  subs.add(StemSignals.taskFailed.connect((payload, _) {
    stdout.writeln(
      '[signal][task_failed] id=${payload.envelope.id} '
      'attempt=${payload.attempt} reason=${payload.error}',
    );
  }));
  subs.add(StemSignals.taskRevoked.connect((payload, _) {
    stdout.writeln(
      '[signal][task_revoked] id=${payload.envelope.id} reason=revoked',
    );
  }));
  subs.add(StemSignals.taskRetry.connect((payload, _) {
    stdout.writeln(
      '[signal][task_retry] id=${payload.envelope.id} next=${payload.nextRetryAt.toIso8601String()}',
    );
  }));
  subs.add(StemSignals.taskSucceeded.connect((payload, _) {
    stdout.writeln(
      '[signal][task_succeeded] id=${payload.envelope.id} payload=${jsonEncode(payload.result)}',
    );
  }));
  return subs;
}

FutureOr<void> _invoiceEntrypoint(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final invoiceId = args['invoiceId'];
  final attempt = context.attempt;
  final replayCount = (context.meta['replayCount'] as num?)?.toInt() ?? 0;
  stdout.writeln(
    '[worker][start] invoice=$invoiceId attempt=$attempt replayCount=$replayCount',
  );

  if (replayCount == 0) {
    stdout.writeln(
      '[worker][fail] invoice=$invoiceId missing downstream dependency. Dead-lettering...',
    );
    throw StateError('Downstream accounting service unavailable');
  }

  context.heartbeat();
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await context
      .progress(0.5, data: {'invoiceId': invoiceId, 'stage': 'replay'});
  await Future<void>.delayed(const Duration(milliseconds: 200));
  stdout.writeln('[worker][success] invoice=$invoiceId replayed successfully');
}

String queueName() => _queueName;

String taskName() => _taskName;
