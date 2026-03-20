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
  final sleepAndEventRef = sleepAndEvent.ref0();

  final app = await StemWorkflowApp.inMemory(
    flows: [sleepAndEvent],
  );

  final runId = await sleepAndEventRef.startWith(app);

  // Wait until the workflow is suspended before emitting the event to avoid
  // losing the signal.
  while (true) {
    final state = await app.getRun(runId);
    if (state?.waitTopic == demoEvent.topic) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  await app
      .emitEventBuilder(
        event: demoEvent,
        value: const {'message': 'event received'},
      )
      .emit();

  final result = await sleepAndEventRef.waitFor(app, runId);
  print('Workflow $runId resumed and completed with: ${result?.value}');

  await app.close();
}
