import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  final logPath = Platform.environment['STEM_WORKER_LOGFILE'];
  if (logPath != null && logPath.isNotEmpty) {
    File(logPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'started ${DateTime.now().toIso8601String()} pid $pid\n',
        mode: FileMode.append,
        flush: true,
      );
  }

  final completer = Completer<void>();
  final fallback = Timer(const Duration(seconds: 5), () {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  ProcessSignal.sigterm.watch().listen((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });
  ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  await completer.future;
  fallback.cancel();
}
