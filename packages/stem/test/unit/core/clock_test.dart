import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  group('clock abstraction', () {
    test('stemNow uses active scoped clock', () {
      final fake = FakeStemClock(DateTime.utc(2025, 1, 1, 12));

      final now = withStemClock(fake, stemNow);

      expect(now, DateTime.utc(2025, 1, 1, 12));
    });

    test('withStemClock propagates through async boundaries', () async {
      final fake = FakeStemClock(DateTime.utc(2025, 1, 1, 12));

      final now = await withStemClock(fake, () async {
        await Future<void>.delayed(Duration.zero);
        fake.advance(const Duration(seconds: 30));
        return stemNow();
      });

      expect(now, DateTime.utc(2025, 1, 1, 12, 0, 30));
    });
  });
}
