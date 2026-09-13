import 'dart:io';

import 'package:workflow_host_prototype/workflow_host.dart';

Future<void> main() async {
  final greeting = HostedWorkflow<String, String>(
    name: 'greeting',
    run: (flow, name) async {
      final cleaned = await flow.step('normalize-name', () => name.trim());
      if (cleaned.isEmpty) return 'Hello, stranger!';
      return 'Hello, $cleaned!';
    },
  );
  try {
    await WorkflowHost.run<void>(
      workflows: [greeting],
      body: (host) async {
        final first = await host.submit(greeting, ' Ada ');
        final second = await host.submit(greeting, '');
        stdout.writeln('${first.id}: ${await first.result}');
        stdout.writeln('${second.id}: ${await second.result}');
      },
    );
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  }
}
