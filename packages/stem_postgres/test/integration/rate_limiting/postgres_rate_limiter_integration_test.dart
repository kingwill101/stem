import 'dart:io';

import 'package:stem_postgres/stem_postgres.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final connectionString = Platform.environment['STEM_TEST_POSTGRES_URL'];
  if (connectionString == null || connectionString.isEmpty) {
    test(
      'Postgres rate limiter requires STEM_TEST_POSTGRES_URL',
      () {},
      skip: 'Set STEM_TEST_POSTGRES_URL to run Postgres rate limiter tests.',
    );
    return;
  }

  group('postgres rate limiter', () {
    late PostgresRateLimiter limiter;
    late String namespace;

    setUp(() async {
      namespace = 'rate-${DateTime.now().microsecondsSinceEpoch}';
      limiter = await PostgresRateLimiter.connect(
        connectionString,
        namespace: namespace,
      );
    });

    tearDown(() => limiter.close());

    test('atomically allows capacity and returns a retry delay', () async {
      final decisions = [
        for (var i = 0; i < 4; i++)
          await limiter.acquire(
            'shared',
            tokens: 3,
            interval: const Duration(seconds: 1),
          ),
      ];

      expect(decisions.take(3).every((decision) => decision.allowed), isTrue);
      expect(decisions[3].allowed, isFalse);
      expect(decisions[3].retryAfter, isNotNull);
      expect(decisions[3].retryAfter, greaterThan(Duration.zero));
      expect(decisions[3].meta['backend'], 'postgres');
    });

    test('refills a bucket using the database clock', () async {
      expect(
        (await limiter.acquire(
          'refill',
          interval: const Duration(milliseconds: 100),
        )).allowed,
        isTrue,
      );
      expect(
        (await limiter.acquire(
          'refill',
          interval: const Duration(milliseconds: 100),
        )).allowed,
        isFalse,
      );

      await Future<void>.delayed(const Duration(milliseconds: 125));

      expect(
        (await limiter.acquire(
          'refill',
          interval: const Duration(milliseconds: 100),
        )).allowed,
        isTrue,
      );
    });

    test('serializes concurrent acquisitions across connections', () async {
      final secondConnection = await PostgresRateLimiter.connect(
        connectionString,
        namespace: namespace,
      );
      addTearDown(secondConnection.close);

      final decisions = await Future.wait([
        for (var i = 0; i < 20; i++)
          (i.isEven ? limiter : secondConnection).acquire(
            'concurrent',
            tokens: 5,
            // Keep refill outside the test window so the assertion proves
            // row-lock serialization rather than timing-dependent refill.
            interval: const Duration(hours: 1),
          ),
      ]);

      expect(
        decisions.where((decision) => decision.allowed),
        hasLength(5),
      );
      expect(
        decisions.where((decision) => !decision.allowed),
        hasLength(15),
      );
    });

    test('separates namespaces and validates configuration', () async {
      final other = await PostgresRateLimiter.connect(
        connectionString,
        namespace: '$namespace-other',
      );
      addTearDown(other.close);

      expect(
        (await limiter.acquire('key')).allowed,
        isTrue,
      );
      expect(
        (await other.acquire('key')).allowed,
        isTrue,
      );

      await expectLater(
        limiter.acquire('invalid', tokens: 0),
        throwsArgumentError,
      );
      await expectLater(
        limiter.acquire('invalid', interval: Duration.zero),
        throwsArgumentError,
      );
    });
  });
}
