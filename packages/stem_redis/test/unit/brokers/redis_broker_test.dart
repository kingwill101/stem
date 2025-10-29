import 'dart:async';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

import '../../support/fakes/fake_redis.dart';

void main() {
  group('RedisStreamsBroker', () {
    test('purge clears priority streams and delayed/dead buckets', () async {
      final connection = FakeRedisConnection();
      final command = FakeRedisCommand(connection);
      final broker = RedisStreamsBroker.test(
        connection: connection,
        command: command,
        namespace: 'unit',
      );

      await broker.purge('emails');

      final streamDeletes = command.sent
          .where(
            (command) =>
                command.length >= 2 &&
                command.first == 'DEL' &&
                (command[1] as String).startsWith('unit:stream:emails'),
          )
          .map((command) => command[1] as String)
          .toSet();

      expect(
        streamDeletes,
        equals({
          'unit:stream:emails',
          for (var priority = 1; priority <= 9; priority++)
            'unit:stream:emails:p$priority',
        }),
      );

      final destroyedGroups = command.sent
          .where(
            (command) =>
                command.length >= 4 &&
                command.first == 'XGROUP' &&
                command[1] == 'DESTROY',
          )
          .map((command) => '${command[2]}|${command[3]}')
          .toSet();

      expect(
        destroyedGroups,
        equals({
          for (var priority = 0; priority <= 9; priority++)
            '${priority == 0 ? 'unit:stream:emails' : 'unit:stream:emails:p$priority'}|unit:group:emails',
        }),
      );

      final delTargets = command.sent
          .where((command) => command.length >= 2 && command.first == 'DEL')
          .map((command) => command[1] as String)
          .toSet();

      expect(delTargets.contains('unit:delayed:emails'), isTrue);
      expect(delTargets.contains('unit:dead:emails'), isTrue);
    });

    test('subscription cancellation tears down claim timers', () async {
      final connection = FakeRedisConnection();
      final command = FakeRedisCommand(connection);
      final broker = RedisStreamsBroker.test(
        connection: connection,
        command: command,
        namespace: 'unit',
        claimInterval: const Duration(milliseconds: 10),
      );

      final stream = broker.consume(
        RoutingSubscription.singleQueue('default'),
        prefetch: 1,
        consumerName: 'consumer-unit',
      );
      final subscription = stream.listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(broker.activeClaimTimerCount, greaterThan(0));

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(broker.activeClaimTimerCount, 0);
      await broker.close();
      expect(connection.closed, isTrue);
    });
  });
}
