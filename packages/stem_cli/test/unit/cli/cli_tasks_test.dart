import 'dart:convert';

import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:test/test.dart';

void main() {
  group('stem tasks', () {
    test('lists tasks with metadata', () async {
      final broker = InMemoryBroker();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'task.one',
            entrypoint: (context, args) async {
              return null;
            },
            metadata: const TaskMetadata(
              description: 'Demo task',
              idempotent: true,
              tags: ['demo'],
            ),
          ),
        );

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['tasks', 'ls'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          backend: null,
          revokeStore: null,
          dispose: () async {
            broker.dispose();
          },
          registry: registry,
        ),
      );

      expect(code, equals(0), reason: err.toString());
      final output = out.toString();
      expect(output, contains('task.one'));
      expect(output, contains('Demo task'));
      expect(output, contains('yes'));
      expect(output, contains('demo'));
    });

    test('emits json when requested', () async {
      final broker = InMemoryBroker();
      final registry = SimpleTaskRegistry()
        ..register(
          FunctionTaskHandler<void>(
            name: 'task.two',
            entrypoint: (context, args) async {
              return null;
            },
            metadata: const TaskMetadata(tags: ['api']),
          ),
        );

      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['tasks', 'ls', '--json'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: null,
          revokeStore: null,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {
            broker.dispose();
          },
          registry: registry,
        ),
      );

      expect(code, equals(0), reason: err.toString());
      final payload = jsonDecode(out.toString()) as List;
      expect(payload, hasLength(1));
      final entry = payload.single as Map<String, dynamic>;
      expect(entry['name'], 'task.two');
      expect(entry['tags'], contains('api'));
    });

    test('warns when registry unavailable', () async {
      final broker = InMemoryBroker();
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await runStemCli(
        ['tasks', 'ls'],
        out: out,
        err: err,
        contextBuilder: () async => CliContext(
          broker: broker,
          backend: null,
          revokeStore: null,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {
            broker.dispose();
          },
          registry: null,
        ),
      );

      expect(code, equals(0));
      expect(out.toString(), contains('No task registry available'));
    });
  });
}
