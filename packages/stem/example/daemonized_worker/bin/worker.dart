import 'dart:async';
import 'dart:io';

// #region daemonized-worker-main
Future<void> main(List<String> args) async {
  // #region daemonized-worker-entrypoint
  final node = Platform.environment['STEM_WORKER_NODE'] ?? 'unknown';
  final currentPid = pid;
  stdout.writeln('Stub worker "$node" started (pid $currentPid).');
  // #endregion daemonized-worker-entrypoint

  final completer = Completer<void>();
  // #region daemonized-worker-signal-handlers
  void complete() {
    if (!completer.isCompleted) {
      stdout.writeln('Stub worker "$node" shutting down.');
      completer.complete();
    }
  }

  ProcessSignal.sigterm.watch().listen((_) => complete());
  ProcessSignal.sigint.watch().listen((_) => complete());
  // #endregion daemonized-worker-signal-handlers

  // Simulate background work.
  // #region daemonized-worker-loop
  while (!completer.isCompleted) {
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!completer.isCompleted) {
      stdout.writeln(
        'Stub worker "$node" heartbeat at ${DateTime.now().toIso8601String()}.',
      );
    }
  }
  // #endregion daemonized-worker-loop
}

// #endregion daemonized-worker-main
