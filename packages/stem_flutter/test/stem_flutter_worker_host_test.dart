import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:stem_flutter/stem_flutter.dart';

Future<void> _readyWorkerEntry(SendPort sendPort) async {
  final commands = ReceivePort();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  sendPort.send(
    StemFlutterWorkerSignal.ready(
      commandPort: commands.sendPort,
      detail: 'ready',
    ).toMessage(),
  );

  await for (final message in commands) {
    if (message is Map<Object?, Object?> && message['type'] == 'shutdown') {
      sendPort.send(
        const StemFlutterWorkerSignal.status(
          status: StemFlutterWorkerStatus.stopped,
          detail: 'shutdown',
        ).toMessage(),
      );
      commands.close();
      return;
    }
  }
}

Future<void> _failingWorkerEntry(SendPort sendPort) async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  throw StateError('boom');
}

void main() {
  group('StemFlutterWorkerHost', () {
    test('captures ready signals and forwards shutdown requests', () async {
      final host = await StemFlutterWorkerHost.spawn<SendPort>(
        entrypoint: _readyWorkerEntry,
        messageBuilder: (sendPort) => sendPort,
      );
      addTearDown(host.dispose);

      final ready = await host.signals
          .firstWhere(
            (signal) => signal.type == StemFlutterWorkerSignalType.ready,
          )
          .timeout(const Duration(seconds: 2));

      expect(ready.detail, 'ready');
      expect(ready.commandPort, isNotNull);
      expect(host.commandPort, isNotNull);

      final stoppedFuture = host.signals
          .firstWhere(
            (signal) =>
                signal.type == StemFlutterWorkerSignalType.status &&
                signal.status == StemFlutterWorkerStatus.stopped &&
                signal.detail == 'shutdown',
          )
          .timeout(const Duration(seconds: 2));

      await host.requestShutdown(gracePeriod: Duration.zero);

      final stopped = await stoppedFuture;
      expect(stopped.status, StemFlutterWorkerStatus.stopped);
      expect(stopped.detail, 'shutdown');
    });

    test('reports isolate failures as fatal signals', () async {
      final host = await StemFlutterWorkerHost.spawn<SendPort>(
        entrypoint: _failingWorkerEntry,
        messageBuilder: (sendPort) => sendPort,
      );
      addTearDown(host.dispose);

      final fatal = await host.signals
          .firstWhere(
            (signal) => signal.type == StemFlutterWorkerSignalType.fatal,
          )
          .timeout(const Duration(seconds: 2));

      expect(fatal.message, contains('Bad state: boom'));
    });
  });
}
