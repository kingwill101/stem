import 'package:test/test.dart';
import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/dependencies.dart';
import 'package:stem_cli/src/cli/workflow.dart';

StemCommandDependencies _deps(StringBuffer out, StringBuffer err) {
  return StemCommandDependencies(
    out: out,
    err: err,
    environment: const {},
    scheduleFilePath: null,
    cliContextBuilder: () async {
      final broker = InMemoryBroker();
      return CliContext(
        broker: broker,
        backend: null,
        revokeStore: null,
        routing: RoutingRegistry(RoutingConfig.legacy()),
        dispose: () async {
          broker.dispose();
        },
        registry: SimpleTaskRegistry(),
      );
    },
  );
}

void main() {
  test('agent-help outputs required sections', () async {
    final out = StringBuffer();
    final err = StringBuffer();

    final code = await runStemCli(
      ['wf', 'agent-help'],
      out: out,
      err: err,
      contextBuilder: () async {
        final broker = InMemoryBroker();
        return CliContext(
          broker: broker,
          backend: null,
          revokeStore: null,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {
            broker.dispose();
          },
          registry: SimpleTaskRegistry(),
        );
      },
    );

    expect(code, equals(0), reason: err.toString());
    final output = out.toString();
    expect(output, contains('# Stem Workflow Agent Help'));
    expect(output, contains('## Summary'));
    expect(output, contains('## CLI Commands'));
    expect(output, contains('## Safety & Idempotency'));
    expect(output, contains('FlowContext.idempotencyKey'));
  });

  test('agent-help stays in sync with workflow subcommands', () async {
    final out = StringBuffer();
    final err = StringBuffer();

    final code = await runStemCli(
      ['wf', 'agent-help'],
      out: out,
      err: err,
      contextBuilder: () async {
        final broker = InMemoryBroker();
        return CliContext(
          broker: broker,
          backend: null,
          revokeStore: null,
          routing: RoutingRegistry(RoutingConfig.legacy()),
          dispose: () async {
            broker.dispose();
          },
          registry: SimpleTaskRegistry(),
        );
      },
    );

    expect(code, equals(0), reason: err.toString());

    final deps = _deps(StringBuffer(), StringBuffer());
    final commands = WorkflowCommand(deps).subcommands.keys;
    final output = out.toString();
    for (final name in commands) {
      expect(output, contains('stem wf $name'));
    }
  });
}
