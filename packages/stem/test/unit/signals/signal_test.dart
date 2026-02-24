import 'package:stem/src/core/stem_event.dart';
import 'package:stem/src/signals/signal.dart';
import 'package:test/test.dart';

void main() {
  test('SignalContext cancellation stops remaining handlers', () async {
    final signal = Signal<_TestEvent>(name: 'test');
    final calls = <String>[];

    signal
      ..connect((payload, context) {
        calls.add('first');
        context.cancel();
      }, priority: 1)
      ..connect((payload, context) {
        calls.add('second');
      });

    await signal.emit(const _TestEvent(1));

    expect(calls, ['first']);
  });

  test('Signal handlers respect priority and once', () async {
    final signal = Signal<_TestEvent>(name: 'priority');
    final calls = <int>[];

    signal
      ..connect((payload, context) {
        calls.add(payload.value);
      }, priority: 1)
      ..connect((payload, context) {
        calls.add(payload.value * 2);
      }, priority: 5)
      ..connect(
        (payload, context) {
          calls.add(payload.value * 3);
        },
        once: true,
        priority: 3,
      );

    await signal.emit(const _TestEvent(1));
    await signal.emit(const _TestEvent(1));

    expect(calls, [2, 3, 1, 2, 1]);
  });

  test('Signal filters can be combined and negated', () {
    final even = SignalFilter<_TestEvent>.where(
      (payload, _) => payload.value.isEven,
    );
    final gtFive = SignalFilter<_TestEvent>.where(
      (payload, _) => payload.value > 5,
    );
    final combined = even.and(gtFive);

    final context = SignalContext(name: 'filter');

    expect(combined.matches(const _TestEvent(6), context), isTrue);
    expect(combined.matches(const _TestEvent(4), context), isFalse);
    expect(combined.negate().matches(const _TestEvent(4), context), isTrue);
  });

  test('Signal dispatch reports errors without throwing', () async {
    Object? reportedError;
    StackTrace? reportedStack;

    final signal =
        Signal<_TestEvent>(
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

    await signal.emit(const _TestEvent(1));

    expect(reportedError, isA<StateError>());
    expect(reportedStack, isNotNull);
  });

  test(
    'SignalContext.event references the emitted StemEvent payload',
    () async {
      final signal = Signal<_TestEvent>(name: 'event-payload');
      _TestEvent? captured;
      SignalContext? capturedContext;

      signal.connect((event, context) {
        captured = event;
        capturedContext = context;
      });

      const payload = _TestEvent(42);
      await signal.emit(payload, sender: 'tester');

      expect(captured, isNotNull);
      expect(captured, same(payload));
      expect(captured!.eventName, 'test-event');
      expect(captured!.attributes['value'], 42);
      expect(capturedContext, isNotNull);
      expect(capturedContext!.event, same(payload));
      expect(capturedContext!.sender, 'tester');
    },
  );

  test('Signal hasListeners tracks typed listeners', () {
    final signal = Signal<_TestEvent>(name: 'listeners');
    expect(signal.hasListeners, isFalse);

    final sub = signal.connect((event, context) {});
    expect(signal.hasListeners, isTrue);

    sub.cancel();
    expect(signal.hasListeners, isFalse);
  });

  test('SignalDispatchConfig copyWith preserves defaults', () {
    const config = SignalDispatchConfig();
    final updated = config.copyWith(enabled: false);

    expect(updated.enabled, isFalse);
    expect(updated.onError, isNull);
  });
}

class _TestEvent implements StemEvent {
  const _TestEvent(this.value);

  final int value;

  @override
  String get eventName => 'test-event';

  @override
  DateTime get occurredAt => DateTime.fromMillisecondsSinceEpoch(value * 1000);

  @override
  Map<String, Object?> get attributes => {'value': value};
}
