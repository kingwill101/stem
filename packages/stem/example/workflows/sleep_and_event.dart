// Demonstrates sleep and external event resumption.
// Run with: dart run example/workflows/sleep_and_event.dart

import 'dart:async';

import 'package:stem/stem.dart';

Future<void> main() async {
  final app = await StemWorkflowApp.inMemory(
    flows: [
      Flow(
        name: 'durable.sleep.event',
        build: (flow) {
          flow.step('initial', (ctx) async {
            final resumePayload = ctx.takeResumeData();
            if (resumePayload != true) {
              ctx.sleep(const Duration(milliseconds: 200));
              return null;
            }
            return 'awake';
          });

          flow.step('await-event', (ctx) async {
            final resumeData = ctx.takeResumeData();
            if (resumeData == null) {
              ctx.awaitEvent('demo.event');
              return null;
            }
            final payload = resumeData as Map<String, Object?>;
            return payload['message'];
          });
        },
      ),
    ],
  );

  final runId = await app.startWorkflow('durable.sleep.event');

  // Wait until the workflow is suspended before emitting the event to avoid
  // losing the signal.
  while (true) {
    final state = await app.getRun(runId);
    if (state?.waitTopic == 'demo.event') {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  await app.runtime.emit('demo.event', {'message': 'event received'});

  final result = await app.waitForCompletion<String>(runId);
  print('Workflow $runId resumed and completed with: ${result?.value}');

  await app.close();
}
