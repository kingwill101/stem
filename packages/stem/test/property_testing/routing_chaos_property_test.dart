import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import 'property_test_helpers.dart';

class _RoutingCase {
  _RoutingCase({
    required this.useBroadcast,
    required this.queue,
    required this.channel,
    required this.priority,
  });

  final bool useBroadcast;
  final String queue;
  final String channel;
  final int priority;
}

void main() {
  test('routing info survives chaotic inputs', () async {
    final gen = Gen.boolean().flatMap((useBroadcast) {
      return Chaos.string(minLength: 1, maxLength: 32).flatMap((queue) {
        return Chaos.string(minLength: 1, maxLength: 32).flatMap((channel) {
          return Chaos.integer(min: 0, max: 9).map(
            (priority) => _RoutingCase(
              useBroadcast: useBroadcast,
              queue: queue,
              channel: channel,
              priority: priority,
            ),
          );
        });
      });
    });

    final runner = PropertyTestRunner<_RoutingCase>(
      gen,
      (sample) async {
        final routing = sample.useBroadcast
            ? RoutingInfo.broadcast(
                channel: sample.channel,
                meta: const {'source': 'property'},
              )
            : RoutingInfo.queue(
                queue: sample.queue,
                priority: sample.priority,
                meta: const {'source': 'property'},
              );

        final roundTrip = RoutingInfo.fromJson(routing.toJson());

        expect(roundTrip.type, routing.type);
        if (sample.useBroadcast) {
          expect(roundTrip.broadcastChannel, routing.broadcastChannel);
        } else {
          expect(roundTrip.queue, routing.queue);
          expect(roundTrip.priority, routing.priority);
        }
      },
      fastPropertyConfig,
    );

    await expectProperty(
      runner,
      description: 'routing chaos round-trip',
    );
  });
}
