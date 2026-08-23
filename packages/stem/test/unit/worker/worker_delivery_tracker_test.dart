import 'package:stem/src/worker/worker_delivery_tracker.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('tracks and releases deliveries with queue accounting', () {
    final tracker = WorkerDeliveryTracker();
    final first = _delivery('first', 'orders');
    final second = _delivery('second', 'orders');
    final startedAt = DateTime.utc(2026, 8, 19);

    tracker
      ..track(first, startedAt: startedAt)
      ..track(second, startedAt: startedAt);

    expect(tracker.inflight, 2);
    expect(tracker.inflightPerQueue, {'orders': 2});
    expect(
      tracker.active.values
          .firstWhere((active) => identical(active.delivery, first))
          .startedAt,
      startedAt,
    );

    expect(tracker.release(first)?.delivery, same(first));
    expect(tracker.inflight, 1);
    expect(tracker.inflightPerQueue, {'orders': 1});
    expect(tracker.release(first), isNull);

    tracker.release(second);

    final duplicate = _delivery('second', 'orders');
    tracker
      ..track(second, startedAt: startedAt)
      ..track(duplicate, startedAt: startedAt);
    expect(tracker.inflight, 2);
    expect(tracker.containsEnvelopeId('second'), isTrue);
    expect(tracker.forEnvelopeId('second')?.delivery, same(second));
    expect(tracker.forDelivery(duplicate)?.delivery, same(duplicate));
    expect(tracker.release(duplicate)?.delivery, same(duplicate));
    expect(tracker.release(second)?.delivery, same(second));

    tracker.clear();
    expect(tracker.inflight, 0);
    expect(tracker.active, isEmpty);
    expect(tracker.inflightPerQueue, isEmpty);
  });
}

Delivery _delivery(String id, String queue, {String? receipt}) {
  final envelope = Envelope(
    id: id,
    name: 'test.task',
    args: const {},
    queue: queue,
  );
  return Delivery(
    envelope: envelope,
    receipt: receipt ?? 'receipt-$id',
    leaseExpiresAt: null,
  );
}
