import 'package:property_testing/property_testing.dart';
import 'package:stem/stem.dart';
import 'package:test/test.dart';

import '../support/property_test_helpers.dart';

void main() {
  group('RoutingConfig', () {
    test('returns legacy defaults when empty YAML provided', () {
      final config = RoutingConfig.fromYaml('');
      expect(config.defaultQueue.alias, 'default');
      expect(config.defaultQueue.queue, 'default');
      expect(config.queues, contains('default'));
      expect(config.routes, isEmpty);
      expect(config.broadcasts, isEmpty);
    });

    test('parses queue definitions and default queue aliasing', () {
      const yaml = '''
default_queue:
  alias: main
  queue: primary
queues:
  primary:
    exchange: jobs
    routing_key: jobs.default
    priority_range: [0, 9]
    bindings:
      - routing_key: jobs.default
        headers:
          region: eu
  secondary:
    exchange: jobs
''';
      final config = RoutingConfig.fromYaml(yaml);
      expect(config.defaultQueue.alias, 'main');
      expect(config.defaultQueue.queue, 'primary');
      expect(config.queues.keys, containsAll(['primary', 'secondary']));

      final primary = config.queues['primary']!;
      expect(primary.exchange, 'jobs');
      expect(primary.routingKey, 'jobs.default');
      expect(primary.priorityRange.min, 0);
      expect(primary.priorityRange.max, 9);
      expect(primary.bindings, hasLength(1));
      expect(primary.bindings.first.routingKey, 'jobs.default');
      expect(primary.bindings.first.headers, containsPair('region', 'eu'));
    });

    test('throws when referenced default queue is missing', () {
      const yaml = '''
default_queue: missing
queues:
  primary: {}
''';
      expect(
        () => RoutingConfig.fromYaml(yaml),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid priority range ordering', () {
      const yaml = '''
queues:
  default:
    priority_range: [5, 1]
''';
      expect(
        () => RoutingConfig.fromYaml(yaml),
        throwsA(isA<FormatException>()),
      );
    });

    test('parses route task patterns into glob objects', () {
      const yaml = '''
queues:
  default: {}
routes:
  - match:
      task:
        - reports.*
        - analytics.update
      headers:
        env: prod
    target:
      type: queue
      name: default
''';
      final config = RoutingConfig.fromYaml(yaml);
      expect(config.routes, hasLength(1));
      final match = config.routes.first.match;
      expect(match.taskGlobs, isNotNull);
      expect(
        match.taskGlobs!.map((glob) => glob.pattern).toList(),
        equals(['reports.*', 'analytics.update']),
      );
      expect(match.headers, containsPair('env', 'prod'));
      final serialized = config.routes.first.match.toJson();
      expect(serialized['task'], ['reports.*', 'analytics.update']);
    });

    test('serializes single task glob as string', () {
      const yaml = '''
queues:
  default: {}
routes:
  - match:
      task: reports.*
    target:
      type: queue
      name: default
''';
      final config = RoutingConfig.fromYaml(yaml);
      final match = config.routes.first.match;
      expect(match.taskGlobs, isNotNull);
      expect(match.taskGlobs!.single.pattern, 'reports.*');
      final serialized = match.toJson();
      expect(serialized['task'], 'reports.*');
    });

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
  });
}

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
