import 'package:stem/src/signals/signal.dart';
import 'package:test/test.dart';

void main() {
  test('SignalContext cancellation stops remaining handlers', () async {
    final signal = Signal<int>(name: 'test');
    final calls = <String>[];

    signal
      ..connect((payload, context) {
        calls.add('first');
        context.cancel();
      }, priority: 1)
      ..connect((payload, context) {
        calls.add('second');
      });

    await signal.emit(1);

    expect(calls, ['first']);
  });

  test('Signal handlers respect priority and once', () async {
    final signal = Signal<int>(name: 'priority');
    final calls = <int>[];

    signal
      ..connect((payload, context) {
        calls.add(1);
      }, priority: 1)
      ..connect((payload, context) {
        calls.add(2);
      }, priority: 5)
      ..connect(
        (payload, context) {
          calls.add(3);
        },
        once: true,
        priority: 3,
      );

    await signal.emit(1);
    await signal.emit(1);

    expect(calls, [2, 3, 1, 2, 1]);
  });

  test('Signal filters can be combined and negated', () {
    final even = SignalFilter<int>.where((payload, _) => payload.isEven);
    final gtFive = SignalFilter<int>.where((payload, _) => payload > 5);
    final combined = even.and(gtFive);

    final context = SignalContext(name: 'filter');

    expect(combined.matches(6, context), isTrue);
    expect(combined.matches(4, context), isFalse);
    expect(combined.negate().matches(4, context), isTrue);
  });

  test('Signal dispatch reports errors without throwing', () async {
    Object? reportedError;
    StackTrace? reportedStack;

    final signal =
        Signal<int>(
          name: 'errors',
          config: SignalDispatchConfig(
            onError: (name, error, stackTrace) {
              reportedError = error;
              reportedStack = stackTrace;
            },
          ),
        )..connect((payload, context) {
          throw StateError('boom');
        });

    await signal.emit(1);

    expect(reportedError, isA<StateError>());
    expect(reportedStack, isNotNull);
  });

  test('SignalDispatchConfig copyWith preserves defaults', () {
    const config = SignalDispatchConfig();
    final updated = config.copyWith(enabled: false);

    expect(updated.enabled, isFalse);
    expect(updated.onError, isNull);
  });
}
