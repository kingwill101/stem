// Demonstrates sleep and external event resumption.
// Run with: dart run example/workflows/sleep_and_event.dart
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:stem/stem.dart';

const demoEvent = WorkflowEventRef<Map<String, Object?>>(
  topic: 'demo.event',
);

Future<void> main() async {
  final sleepAndEvent = Flow<String>(
    name: 'durable.sleep.event',
    build: (flow) {
      flow
        ..step('initial', (ctx) async {
          if (!ctx.sleepUntilResumed(const Duration(milliseconds: 200))) {
            return null;
          }
          return 'awake';
        })
        ..step('await-event', (ctx) async {
          final payload = ctx.waitForEventRef(demoEvent);
          if (payload == null) {
            return null;
          }
          return payload['message'];
        });
    },
  );

  final app = await StemWorkflowApp.inMemory(
    flows: [sleepAndEvent],
  );

  final runId = await sleepAndEvent.startWith(app);

  // Wait until the workflow is suspended before emitting the event to avoid
  // losing the signal.
  while (true) {
    final state = await app.getRun(runId);
    if (state?.waitTopic == demoEvent.topic) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  await demoEvent.emitWith(app, const {'message': 'event received'});

  final result = await sleepAndEvent.waitFor(app, runId);
  print('Workflow $runId resumed and completed with: ${result?.value}');

  await app.close();
}
