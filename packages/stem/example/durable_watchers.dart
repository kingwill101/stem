import 'package:stem/stem.dart';

final shipmentReadyEvent = WorkflowEventRef<_ShipmentReadyEvent>.json(
  topic: 'shipment.ready',
  decode: _ShipmentReadyEvent.fromJson,
  typeName: '_ShipmentReadyEvent',
);

/// Runs a workflow that suspends on `awaitEvent` and resumes once a payload is
/// emitted. The example also inspects watcher metadata before the resume.
Future<void> main() async {
  final shipmentWorkflow = WorkflowScript<String>(
    name: 'shipment.workflow',
    run: (script) async {
      await script.step('prepare', (step) async {
        final orderId = step.params['orderId'];
        return 'prepared-$orderId';
      });

      final trackingId = await script.step('wait-for-shipment', (step) async {
        final payload = await shipmentReadyEvent.wait(
          step,
          deadline: DateTime.now().add(const Duration(minutes: 5)),
          data: const {'reason': 'waiting-for-carrier'},
        );
        return payload.trackingId;
      });

      return trackingId;
    },
  );
  final shipmentWorkflowRef = shipmentWorkflow.ref<Map<String, Object?>>(
    encodeParams: (params) => params,
  );
  final app = await StemWorkflowApp.inMemory(
    scripts: [shipmentWorkflow],
  );

  final runId = await shipmentWorkflowRef
      .call(const {'orderId': 'A-123'})
      .start(app);

  // Drive the run until it suspends on the watcher.
  await app.executeRun(runId);

  final watchers = await app.listWatchers(shipmentReadyEvent.topic);
  for (final watcher in watchers) {
    print(
      'Run ${watcher.runId} waiting on ${watcher.topic} (step ${watcher.stepName})',
    );
    print('Watcher metadata: ${watcher.data}');
  }

  await shipmentReadyEvent.emit(
    app,
    const _ShipmentReadyEvent(trackingId: 'ZX-42'),
  );

  await app.executeRun(runId);

  final completed = await shipmentWorkflowRef.waitFor(app, runId);
  print('Workflow completed with result: ${completed?.value}');

  await app.close();
}

class _ShipmentReadyEvent {
  const _ShipmentReadyEvent({required this.trackingId});

  final String trackingId;

  Map<String, Object?> toJson() => {'trackingId': trackingId};

  static _ShipmentReadyEvent fromJson(Map<String, Object?> json) {
    return _ShipmentReadyEvent(trackingId: json['trackingId'] as String);
  }
}
