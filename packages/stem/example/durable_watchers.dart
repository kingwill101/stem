import 'package:stem/stem.dart';

final shipmentReadyEventCodec = PayloadCodec<_ShipmentReadyEvent>(
  encode: (value) => value.toJson(),
  decode: _ShipmentReadyEvent.fromJson,
);

/// Runs a workflow that suspends on `awaitEvent` and resumes once a payload is
/// emitted. The example also inspects watcher metadata before the resume.
Future<void> main() async {
  final app = await StemWorkflowApp.inMemory(
    scripts: [
      WorkflowScript(
        name: 'shipment.workflow',
        run: (script) async {
          await script.step('prepare', (step) async {
            final orderId = step.params['orderId'];
            return 'prepared-$orderId';
          });

          final trackingId = await script.step('wait-for-shipment', (
            step,
          ) async {
            final payload = step.takeResumeValue<_ShipmentReadyEvent>(
              codec: shipmentReadyEventCodec,
            );
            if (payload == null) {
              await step.awaitEvent(
                'shipment.ready',
                deadline: DateTime.now().add(const Duration(minutes: 5)),
                data: const {'reason': 'waiting-for-carrier'},
              );
              return 'waiting';
            }
            return payload.trackingId;
          });

          return trackingId;
        },
      ),
    ],
  );

  final runId = await app.startWorkflow(
    'shipment.workflow',
    params: const {'orderId': 'A-123'},
  );

  // Drive the run until it suspends on the watcher.
  await app.runtime.executeRun(runId);

  final watchers = await app.store.listWatchers('shipment.ready');
  for (final watcher in watchers) {
    print(
      'Run ${watcher.runId} waiting on ${watcher.topic} (step ${watcher.stepName})',
    );
    print('Watcher metadata: ${watcher.data}');
  }

  await app.emitValue(
    'shipment.ready',
    const _ShipmentReadyEvent(trackingId: 'ZX-42'),
    codec: shipmentReadyEventCodec,
  );

  await app.runtime.executeRun(runId);

  final completed = await app.store.get(runId);
  print('Workflow completed with result: ${completed?.result}');

  await app.close();
}

class _ShipmentReadyEvent {
  const _ShipmentReadyEvent({required this.trackingId});

  final String trackingId;

  Map<String, Object?> toJson() => {'trackingId': trackingId};

  static _ShipmentReadyEvent fromJson(Object? payload) {
    final json = payload! as Map<String, Object?>;
    return _ShipmentReadyEvent(trackingId: json['trackingId'] as String);
  }
}
