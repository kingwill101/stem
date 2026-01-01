// #region daemonized-worker-main
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final node = Platform.environment['STEM_WORKER_NODE'] ?? 'unknown';
  final currentPid = pid;
  stdout.writeln('Stub worker "$node" started (pid $currentPid).');

  final completer = Completer<void>();
  void complete() {
    if (!completer.isCompleted) {
      stdout.writeln('Stub worker "$node" shutting down.');
      completer.complete();
    }
  }

  ProcessSignal.sigterm.watch().listen((_) => complete());
  ProcessSignal.sigint.watch().listen((_) => complete());

  // Simulate background work.
  while (!completer.isCompleted) {
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!completer.isCompleted) {
      stdout.writeln(
        'Stub worker "$node" heartbeat at ${DateTime.now().toIso8601String()}.',
      );
    }
  }
}
// #endregion daemonized-worker-main
