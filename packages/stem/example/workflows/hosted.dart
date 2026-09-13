import 'package:stem/stem.dart';

const approval = WorkflowEventRef<Map<String, Object?>>(
  topic: 'hosted.greeting.approval',
);

final greeting = HostedWorkflow<String, String>(
  name: 'hosted.greeting',
  run: (context, name) async {
    final cleaned = await context.step('normalize', () => name.trim());
    await context.sleep('pause', const Duration(milliseconds: 10));
    final decision = await context.awaitEvent('approval', approval);
    return context.step(
      'greet',
      () => decision['approved'] == true ? 'Hello, $cleaned!' : 'Not approved',
    );
  },
);

Future<void> main() async {
  final host = await WorkflowHost.inMemory(workflows: [greeting]);
  try {
    final run = await host.submit(greeting, ' Ada ');
    // Event topics are shared, not run-addressed mailboxes. For this example,
    // wait until the watcher exists before sending its one approval event.
    await run
        .watch()
        .firstWhere(
          (view) =>
              view.status == WorkflowStatus.suspended &&
              view.suspensionData?['step'] == 'approval',
        )
        .timeout(const Duration(seconds: 5));
    await host.emitEvent(approval, {'approved': true});
    print(await run.result.timeout(const Duration(seconds: 5)));
  } finally {
    await host.close();
  }
}
