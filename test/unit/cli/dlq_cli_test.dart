import 'dart:async';

import 'package:test/test.dart';
import 'package:stem/src/cli/cli_runner.dart';
import 'package:stem/stem.dart';

void main() {
  group('stem dlq cli', () {
    late InMemoryBroker broker;
    late InMemoryResultBackend backend;

    setUp(() {
      broker = InMemoryBroker();
      backend = InMemoryResultBackend();
    });

    tearDown(() {
      broker.dispose();
    });

    test('lists dead letter entries', () async {
      await _seedDeadLetter(broker, backend: backend, reason: 'boom');

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final exitCode = await runStemCli(
        ['dlq', 'list', '--queue', 'default'],
        out: stdoutBuffer,
        err: stderrBuffer,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(exitCode, 0);
      final output = stdoutBuffer.toString();
      expect(output, contains('tasks.sample'));
      expect(output, contains('boom'));
    });

    test('replays entries with confirmation', () async {
      final id = await _seedDeadLetter(
        broker,
        backend: backend,
        reason: 'retry',
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final exitCode = await runStemCli(
        ['dlq', 'replay', '--queue', 'default', '--yes'],
        out: stdoutBuffer,
        err: stderrBuffer,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(exitCode, 0, reason: stderrBuffer.toString());
      expect(stdoutBuffer.toString(), contains('Replayed'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final page = await broker.listDeadLetters('default');
      expect(page.entries, isEmpty);

      final status = await backend.get(id);
      expect(status, isNotNull);
      expect(status!.meta['replayCount'], equals(1));
      expect(status.meta['lastReplayReason'], equals('retry'));
    });

    test('dry-run leaves entries untouched', () async {
      await _seedDeadLetter(broker, backend: backend, reason: 'preview');

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final exitCode = await runStemCli(
        ['dlq', 'replay', '--queue', 'default', '--dry-run'],
        out: stdoutBuffer,
        err: stderrBuffer,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(exitCode, 0, reason: stderrBuffer.toString());

      final page = await broker.listDeadLetters('default');
      expect(page.entries, isNotEmpty);
    });

    test('purge removes entries', () async {
      await _seedDeadLetter(broker, backend: backend, reason: 'purge-me');

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final exitCode = await runStemCli(
        ['dlq', 'purge', '--queue', 'default', '--yes'],
        out: stdoutBuffer,
        err: stderrBuffer,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: backend,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {},
        ),
      );

      expect(exitCode, 0, reason: stderrBuffer.toString());
      final page = await broker.listDeadLetters('default');
      expect(page.entries, isEmpty);
    });
  });
}

Future<String> _seedDeadLetter(
  InMemoryBroker broker, {
  InMemoryResultBackend? backend,
  String reason = 'error',
}) async {
  final envelope = Envelope(name: 'tasks.sample', args: const {});
  await broker.publish(envelope);
  final delivery =
      await broker.consume(RoutingSubscription.singleQueue('default')).first;
  await backend?.set(
    envelope.id,
    TaskState.failed,
    attempt: envelope.attempt,
    meta: const {},
  );
  await broker.deadLetter(delivery, reason: reason, meta: {'reason': reason});
  return envelope.id;
}
