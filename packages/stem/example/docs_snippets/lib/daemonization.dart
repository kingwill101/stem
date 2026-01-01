// Daemonization snippets for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:async';
import 'dart:io';

// #region daemonization-entrypoint
Future<void> main(List<String> args) async {
  final node = Platform.environment['STEM_WORKER_NODE'] ?? 'unknown';
  stdout.writeln('Stub worker "$node" started (pid $pid).');
  // #endregion daemonization-entrypoint

  final completer = Completer<void>();

  // #region daemonization-signal-handlers
  void shutdown() {
    if (!completer.isCompleted) {
      stdout.writeln('Stub worker "$node" shutting down.');
      completer.complete();
    }
  }

  ProcessSignal.sigterm.watch().listen((_) => shutdown());
  ProcessSignal.sigint.watch().listen((_) => shutdown());
  // #endregion daemonization-signal-handlers

  // #region daemonization-loop
  while (!completer.isCompleted) {
    await Future<void>.delayed(const Duration(seconds: 10));
    if (!completer.isCompleted) {
      stdout.writeln(
        'Stub worker "$node" heartbeat at ${DateTime.now().toIso8601String()}.',
      );
    }
  }
  // #endregion daemonization-loop
}
