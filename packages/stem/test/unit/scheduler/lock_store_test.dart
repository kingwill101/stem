import 'package:stem/memory.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory lock fencing tokens increase for each acquisition', () async {
    final store = InMemoryLockStore();

    final first = await store.acquire('fenced', owner: 'first');
    expect(first, isA<FencedLock>());
    expect(first!.fencingToken, equals(1));
    await first.release();

    final second = await store.acquire('fenced', owner: 'second');
    expect(second, isA<FencedLock>());
    expect(second!.fencingToken, equals(2));
    await second.release();
  });

  test('legacy locks expose no fencing token', () async {
    final lock = _LegacyLock();
    expect(lock.fencingToken, isNull);
  });
}

class _LegacyLock implements Lock {
  @override
  String get key => 'legacy';

  @override
  String get owner => 'legacy-owner';

  @override
  Future<bool> renew(Duration ttl) async => true;

  @override
  Future<void> release() async {}
}
