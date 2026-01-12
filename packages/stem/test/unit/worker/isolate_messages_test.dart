import 'dart:isolate';

import 'package:stem/src/worker/isolate_messages.dart';
import 'package:test/test.dart';

Future<SendPort> _spawnWorker() async {
  final handshake = ReceivePort();
  await Isolate.spawn(taskWorkerIsolate, handshake.sendPort);
  final commandPort = await handshake.first as SendPort;
  handshake.close();
  return commandPort;
}

void main() {
  test('taskWorkerIsolate returns success response', () async {
    final commandPort = await _spawnWorker();
    addTearDown(() => commandPort.send(const TaskWorkerShutdown()));

    final reply = ReceivePort();
    final control = ReceivePort();
    addTearDown(reply.close);
    addTearDown(control.close);

    commandPort.send(
      TaskRunRequest(
        id: 'task-1',
        entrypoint: (context, args) async => 'ok',
        args: const {},
        headers: const {},
        meta: const {},
        attempt: 0,
        controlPort: control.sendPort,
        replyPort: reply.sendPort,
      ),
    );

    final response = await reply.first;
    expect(response, isA<TaskRunSuccess>());
    expect((response as TaskRunSuccess).result, 'ok');
  });

  test('taskWorkerIsolate returns retry response', () async {
    final commandPort = await _spawnWorker();
    addTearDown(() => commandPort.send(const TaskWorkerShutdown()));

    final reply = ReceivePort();
    final control = ReceivePort();
    addTearDown(reply.close);
    addTearDown(control.close);

    commandPort.send(
      TaskRunRequest(
        id: 'task-2',
        entrypoint: (context, args) => context.retry(
          countdown: const Duration(seconds: 1),
          maxRetries: 3,
        ),
        args: const {},
        headers: const {},
        meta: const {},
        attempt: 0,
        controlPort: control.sendPort,
        replyPort: reply.sendPort,
      ),
    );

    final response = await reply.first;
    expect(response, isA<TaskRunRetry>());
    expect((response as TaskRunRetry).countdownMs, 1000);
    expect(response.maxRetries, 3);
  });

  test('taskWorkerIsolate returns failure response', () async {
    final commandPort = await _spawnWorker();
    addTearDown(() => commandPort.send(const TaskWorkerShutdown()));

    final reply = ReceivePort();
    final control = ReceivePort();
    addTearDown(reply.close);
    addTearDown(control.close);

    commandPort.send(
      TaskRunRequest(
        id: 'task-3',
        entrypoint: (context, args) {
          throw StateError('boom');
        },
        args: const {},
        headers: const {},
        meta: const {},
        attempt: 0,
        controlPort: control.sendPort,
        replyPort: reply.sendPort,
      ),
    );

    final response = await reply.first;
    expect(response, isA<TaskRunFailure>());
    expect((response as TaskRunFailure).errorType, contains('StateError'));
  });
}
