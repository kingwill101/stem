import 'dart:io';

import 'package:stem/stem.dart';

Future<void> main() async {
  final greeting = HostedWorkflow<String, String>(
    name: 'greeting',
    run: (flow, name) async {
      final cleaned = await flow.step('normalize-name', () => name.trim());
      if (cleaned.isEmpty) return 'Hello, stranger!';
      return 'Hello, $cleaned!';
    },
  );
  final host = await WorkflowHost.inMemory(workflows: [greeting]);
  try {
    final first = await host.submit(greeting, ' Ada ');
    final second = await host.submit(greeting, '');
    stdout.writeln('${first.id}: ${await first.result}');
    stdout.writeln('${second.id}: ${await second.result}');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await host.close();
  }
}
