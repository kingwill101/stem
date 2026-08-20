import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

import '../../support/fakes/fake_redis.dart';

void main() {
  group('RedisRateLimiter', () {
    test(
      'evaluates the atomic token-bucket script and parses grants',
      () async {
        final connection = FakeRedisConnection();
        final command = FakeRedisCommand(connection)
          ..queueResponse((_) => [1, 0, 1.5]);
        final limiter = RedisRateLimiter.test(
          connection: connection,
          command: command,
          namespace: 'unit',
        );

        final decision = await limiter.acquire(
          'tenant-a',
          tokens: 3,
          interval: const Duration(seconds: 2),
          meta: const {'source': 'test'},
        );

        expect(decision.allowed, isTrue);
        expect(decision.retryAfter, isNull);
        expect(decision.meta['capacity'], 3);
        expect(decision.meta['remainingTokens'], 1.5);
        expect(decision.meta['source'], 'test');
        expect(command.sent, hasLength(1));
        expect(command.sent.single.first, 'EVAL');
        expect(command.sent.single[3], 'unit:rate:tenant-a');
        expect(command.sent.single[4], 3);
        expect(command.sent.single[5], 2000);
        expect(command.sent.single[1], contains("redis.call('TIME')"));

        await limiter.close();
        expect(connection.closed, isTrue);
      },
    );

    test('parses denied decisions with retry-after', () async {
      final connection = FakeRedisConnection();
      final command = FakeRedisCommand(connection)
        ..queueResponse((_) => [0, 125, 0.25]);
      final limiter = RedisRateLimiter.test(
        connection: connection,
        command: command,
      );

      final decision = await limiter.acquire('busy');

      expect(decision.allowed, isFalse);
      expect(decision.retryAfter, const Duration(milliseconds: 125));
      expect(decision.meta['remainingTokens'], 0.25);
    });

    test('rejects invalid capacity, interval, and Redis responses', () async {
      final connection = FakeRedisConnection();
      final command = FakeRedisCommand(connection)
        ..queueResponse((_) => const [1]);
      final limiter = RedisRateLimiter.test(
        connection: connection,
        command: command,
      );

      expect(
        () => limiter.acquire('invalid', tokens: 0),
        throwsArgumentError,
      );
      expect(
        () => limiter.acquire('invalid', interval: Duration.zero),
        throwsArgumentError,
      );
      await expectLater(limiter.acquire('invalid'), throwsStateError);
    });
  });
}
