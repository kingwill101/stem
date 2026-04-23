import 'dart:async';
import 'dart:isolate';

import 'package:stem_flutter/src/runtime/stem_flutter_worker_signal.dart';

/// Supervises a worker isolate launched from a Flutter app.
///
/// This host owns the isolate lifecycle, exposes decoded worker signals, and
/// provides a small control channel for graceful shutdown.
class StemFlutterWorkerHost {
  StemFlutterWorkerHost._({
    required Isolate isolate,
    required ReceivePort messages,
    required ReceivePort errors,
    required ReceivePort exit,
    required StreamController<StemFlutterWorkerSignal> controller,
  }) : _isolate = isolate,
       _messages = messages,
       _errors = errors,
       _exit = exit,
       _controller = controller;

  final Isolate _isolate;
  final ReceivePort _messages;
  final ReceivePort _errors;
  final ReceivePort _exit;
  final StreamController<StemFlutterWorkerSignal> _controller;
  late final StreamSubscription<dynamic> _messagesSub;
  late final StreamSubscription<dynamic> _errorsSub;
  late final StreamSubscription<dynamic> _exitSub;

  SendPort? _commandPort;
  StemFlutterWorkerSignal? _lastSignal;
  final Completer<void> _stoppedCompleter = Completer<void>();
  bool _disposed = false;

  /// A stream of worker signals emitted by the supervised isolate.
  Stream<StemFlutterWorkerSignal> get signals =>
      Stream<StemFlutterWorkerSignal>.multi((controller) {
        final lastSignal = _lastSignal;
        if (lastSignal != null) {
          controller.add(lastSignal);
        }

        final subscription = _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = subscription.cancel;
      }, isBroadcast: true);

  /// The latest command port reported by the worker.
  SendPort? get commandPort => _commandPort;

  /// Spawns a worker isolate and wires its control channels.
  ///
  /// The [messageBuilder] callback receives the host's signal port so the
  /// spawned isolate can report status updates back to this host.
  static Future<StemFlutterWorkerHost> spawn<T extends Object?>({
    required FutureOr<void> Function(T message) entrypoint,
    required T Function(SendPort sendPort) messageBuilder,
  }) async {
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    final controller = StreamController<StemFlutterWorkerSignal>.broadcast();
    final message = messageBuilder(messages.sendPort);

    final isolate = await Isolate.spawn<T>(
      entrypoint,
      message,
      onError: errors.sendPort,
      onExit: exit.sendPort,
    );

    final host = StemFlutterWorkerHost._(
      isolate: isolate,
      messages: messages,
      errors: errors,
      exit: exit,
      controller: controller,
    );

    // Owned by the host and cancelled in dispose().
    // ignore: cancel_subscriptions
    final messagesSub = messages.listen((dynamic raw) {
      final signal = StemFlutterWorkerSignal.tryParse(raw);
      if (signal == null) return;
      if (signal.type == StemFlutterWorkerSignalType.ready) {
        host._commandPort = signal.commandPort;
      }
      host._emitSignal(signal);
    });

    // Owned by the host and cancelled in dispose().
    // ignore: cancel_subscriptions
    final errorsSub = errors.listen((dynamic raw) {
      final detail = switch (raw) {
        final List<Object?> values => values.join('\n'),
        _ => raw.toString(),
      };
      host._emitSignal(StemFlutterWorkerSignal.fatal(detail));
    });

    // Owned by the host and cancelled in dispose().
    // ignore: cancel_subscriptions
    final exitSub = exit.listen((dynamic _) {
      host._emitSignal(
        const StemFlutterWorkerSignal.status(
          status: StemFlutterWorkerStatus.stopped,
          detail: 'Worker isolate exited.',
        ),
      );
    });

    host
      .._messagesSub = messagesSub
      .._errorsSub = errorsSub
      .._exitSub = exitSub;

    return host;
  }

  /// Requests a graceful worker shutdown.
  ///
  /// If the worker has not reported a command port yet, this method returns
  /// immediately.
  Future<void> requestShutdown({
    Duration gracePeriod = const Duration(seconds: 5),
  }) async {
    final port = _commandPort;
    if (port == null) return;
    port.send(const <String, Object?>{'type': 'shutdown'});
    if (gracePeriod <= Duration.zero) return;
    await _stoppedCompleter.future.timeout(
      gracePeriod,
      onTimeout: () {},
    );
  }

  /// Tears down this host and kills the supervised isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await requestShutdown();
    _isolate.kill(priority: Isolate.immediate);
    await _messagesSub.cancel();
    await _errorsSub.cancel();
    await _exitSub.cancel();
    _messages.close();
    _errors.close();
    _exit.close();
    await _controller.close();
  }

  void _emitSignal(StemFlutterWorkerSignal signal) {
    _lastSignal = signal;
    if (signal.type == StemFlutterWorkerSignalType.fatal ||
        signal.status == StemFlutterWorkerStatus.stopped) {
      _completeStopped();
    }
    if (!_controller.isClosed) {
      _controller.add(signal);
    }
  }

  void _completeStopped() {
    if (!_stoppedCompleter.isCompleted) {
      _stoppedCompleter.complete();
    }
  }
}
