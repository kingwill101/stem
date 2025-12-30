import 'package:args/command_runner.dart' as args;

String buildWorkflowAgentHelpMarkdown(
  Iterable<args.Command<dynamic>> commands,
) {
  final buffer = StringBuffer()
    ..writeln('# Stem Workflow Agent Help')
    ..writeln()
    ..writeln('## Summary')
    ..writeln(
      '- Workflow steps are durable and may replay after sleeps, awaited '
      'events, or worker restarts.',
    )
    ..writeln(
      '- Use FlowContext.idempotencyKey and stored checkpoints to guard side '
      'effects.',
    )
    ..writeln(
      '- Always consume resume payloads via FlowContext.takeResumeData to avoid '
      're-suspending on replay.',
    )
    ..writeln()
    ..writeln('## CLI Commands');

  final commandList = commands.toList(growable: false);
  for (final command in commandList) {
    buffer.writeln('- `stem wf ${command.name}`: ${command.description}');
  }

  buffer
    ..writeln()
    ..writeln('## Safety & Idempotency')
    ..writeln(
      '- Confirm the run id with `stem wf show` before cancelling or rewinding.',
    )
    ..writeln(
      '- Review max-run/max-suspend policies; cancelling a run is irreversible.',
    )
    ..writeln(
      '- Use idempotency keys when calling external systems (billing, email, '
      'third-party APIs).',
    )
    ..writeln(
      '- Prefer `stem wf waiters` to inspect pending event topics before '
      'emitting.',
    );

  return buffer.toString().trimRight();
}
