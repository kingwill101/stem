import 'package:stem/src/routing/routing_registry.dart';
import 'package:test/test.dart';

void main() {
  group('RoutingRegistry', () {
    test('defaults to configured default queue when no routes match', () {
      const yaml = '''
default_queue: primary
queues:
  primary: {}
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(RouteRequest(task: 'tasks.process'));
      expect(decision.type, RouteDecisionType.queue);
      expect(decision.queue!.name, 'primary');
      expect(decision.selectedQueueAlias, 'default');
      expect(decision.fallbackQueues, isEmpty);
    });

    test('respects explicit queue when no routes match', () {
      const yaml = '''
default_queue: primary
queues:
  primary: {}
  secondary: {}
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(
        RouteRequest(task: 'tasks.process', queue: 'secondary'),
      );
      expect(decision.queue!.name, 'secondary');
      expect(decision.selectedQueueAlias, 'secondary');
    });

    test('applies first matching route using glob patterns', () {
      const yaml = '''
queues:
  default: {}
  reports: {}
  special: {}
routes:
  - match:
      task: reports.*
    target:
      type: queue
      name: reports
  - match:
      task: reports.generate
    target:
      type: queue
      name: special
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(
        RouteRequest(task: 'reports.generate'),
      );
      expect(decision.queue!.name, 'reports');
      expect(decision.route, isNotNull);
      expect(decision.selectedQueueAlias, 'reports');
    });

    test('matches routes with headers and queue override', () {
      const yaml = '''
queues:
  default: {}
  critical: {}
routes:
  - match:
      task: reports.*
      headers:
        region: eu
      queue_override: critical
    target:
      type: queue
      name: critical
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(
        RouteRequest(
          task: 'reports.generate',
          headers: {'region': 'eu'},
          queue: 'critical',
        ),
      );
      expect(decision.queue!.name, 'critical');
      expect(decision.route, isNotNull);
      expect(decision.selectedQueueAlias, 'critical');
    });

    test('routes to broadcast channels', () {
      const yaml = '''
queues:
  default: {}
broadcasts:
  maintenance: {}
routes:
  - match:
      task: maintenance.notify
    target:
      type: broadcast
      name: maintenance
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(
        RouteRequest(task: 'maintenance.notify'),
      );
      expect(decision.type, RouteDecisionType.broadcast);
      expect(decision.broadcast!.name, 'maintenance');
      expect(decision.isBroadcast, isTrue);
    });

    test('exposes default queue fallbacks', () {
      const yaml = '''
default_queue:
  queue: primary
  fallbacks:
    - secondary
queues:
  primary: {}
  secondary: {}
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      final decision = registry.resolve(RouteRequest(task: 'tasks.process'));
      expect(decision.fallbackQueues.map((queue) => queue.name).toList(),
          equals(['secondary']));
    });

    test('throws for unknown explicit queue', () {
      const yaml = '''
default_queue: primary
queues:
  primary: {}
''';
      final registry = RoutingRegistry.fromYaml(yaml);
      expect(
        () => registry.resolve(
          RouteRequest(task: 'tasks.process', queue: 'missing'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('validates unknown route targets at construction', () {
      const yaml = '''
default_queue: primary
queues:
  primary: {}
routes:
  - match:
      task: reports.*
    target:
      type: queue
      name: missing
''';
      expect(
        () => RoutingRegistry.fromYaml(yaml),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
