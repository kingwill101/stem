import 'dart:isolate';

import 'package:stem/stem.dart';

/// Minimal button -> workflow -> result demo.
///
/// `normalize` shows a durable checkpoint. `greet` hops to a fresh Dart
/// isolate via [Isolate.run] so the heavy work (and its isolate name) provably
/// comes from a different thread than the UI isolate that submitted the run.
final greetingWorkflow = HostedWorkflow<String, String>(
  name: 'greeting',
  run: (context, name) async {
    final cleaned = await context.step('normalize', () => name.trim());
    return context.step('greet', () => greetOffThread(cleaned));
  },
);

/// Runs the greeting on a worker isolate and reports both isolate names so
/// the screen can show the result crossed an isolate boundary.
Future<String> greetOffThread(String name) async {
  final caller = Isolate.current.debugName;
  final result = await Isolate.run(() => _greet(name));
  return '$result (ui: $caller)';
}

String _greet(String name) {
  final worker = Isolate.current.debugName;
  final display = name.isEmpty ? 'stranger' : name;
  return 'Hello, $display! [from $worker]';
}
