import 'dart:io';

import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';
import 'package:test/test.dart';

void main() {
  final redisUrl = Platform.environment['STEM_TEST_REDIS_URL'];
  if (redisUrl == null || redisUrl.isEmpty) {
    test(
      'Redis rate limiter integration requires STEM_TEST_REDIS_URL',
      () {},
      skip: 'Set STEM_TEST_REDIS_URL to run Redis rate limiter tests.',
    );
    return;
  }

  late RedisRateLimiter limiter;

  setUp(() async {
    limiter = await RedisRateLimiter.connect(
      redisUrl,
      namespace: 'rate-test-${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() => limiter.close());

  test('shares one atomic bucket across concurrent acquires', () async {
    final decisions = await Future.wait(
      List.generate(
        20,
        (_) => limiter.acquire(
          'shared',
          tokens: 5,
          interval: const Duration(seconds: 1),
        ),
      ),
    );

    expect(decisions.where((decision) => decision.allowed), hasLength(5));
    expect(
      decisions.where((decision) => !decision.allowed),
      everyElement(
        predicate<RateLimitDecision>(
          (decision) => decision.retryAfter != null,
        ),
      ),
    );
  });

  test('refills permits and reports retry delay', () async {
    final first = await limiter.acquire(
      'refill',
      interval: const Duration(milliseconds: 100),
    );
    final denied = await limiter.acquire(
      'refill',
      interval: const Duration(milliseconds: 100),
    );

    expect(first.allowed, isTrue);
    expect(denied.allowed, isFalse);
    final retryAfter = denied.retryAfter;
    expect(retryAfter, isNotNull);
    await Future<void>.delayed(retryAfter! + const Duration(milliseconds: 25));

    expect(
      (await limiter.acquire(
        'refill',
        interval: const Duration(milliseconds: 100),
      )).allowed,
      isTrue,
    );
  });
}
