import 'dart:async';

import 'package:stem/stem.dart';

/// Demonstrates configuring workflow-level cancellation policies.
///
/// The workflow below suspends on a long sleep. Because the run is started with
/// a `WorkflowCancellationPolicy` that limits suspension duration to two
/// seconds, the runtime automatically cancels the run once the policy is
/// exceeded. Operators can introspect the reason via `StemWorkflowApp`.
Future<void> main() async {
  final reportsGenerate = Flow<String>(
    name: 'reports.generate',
    build: (flow) {
      flow.step('poll-status', (ctx) async {
        if (!ctx.sleepUntilResumed(const Duration(seconds: 5))) {
          print('[workflow] polling external system…');
          // Simulate a slow external service; the cancellation policy will
          // cap this suspension to 2 seconds.
          return null;
        }
        print('[workflow] resumed after sleep');
        return 'finished';
      });
    },
  );

  final app = await StemWorkflowApp.inMemory(
    flows: [reportsGenerate],
  );

  final runId = await reportsGenerate
      .startBuilder()
      .cancellationPolicy(
        const WorkflowCancellationPolicy(
          maxRunDuration: Duration(minutes: 10),
          maxSuspendDuration: Duration(seconds: 2),
        ),
      )
      .startWith(app);

  // Wait a bit longer than the policy allows so the auto-cancel can trigger.
  await Future<void>.delayed(const Duration(seconds: 4));

  final state = await app.getRun(runId);
  print('Run status: ${state?.status}');
  print('Cancellation data: ${state?.cancellationData}');

  await app.close();
}
