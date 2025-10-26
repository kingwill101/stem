import 'dart:async';

import 'package:stem/stem.dart';

const _demoRoutingYaml = '''
default_queue:
  alias: default
  queue: standard
  fallbacks:
    - critical
queues:
  standard:
    priority_range: [0, 3]
  critical:
    priority_range:
      min: 3
      max: 9
broadcasts:
  ops:
    delivery: at-least-once
routes:
  - match:
      task: reports.*
    target:
      type: queue
      name: critical
  - match:
      task: ops.*
    target:
      type: broadcast
      name: ops
''';

RoutingRegistry buildRoutingRegistry() =>
    RoutingRegistry(RoutingConfig.fromYaml(_demoRoutingYaml));

SimpleTaskRegistry buildDemoTaskRegistry() {
  return SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<void>(
        name: 'billing.invoice',
        entrypoint: _processInvoice,
        options: const TaskOptions(queue: 'standard', maxRetries: 2),
      ),
    )
    ..register(
      FunctionTaskHandler<void>(
        name: 'reports.generate',
        entrypoint: _processReport,
        options: const TaskOptions(queue: 'critical', maxRetries: 3),
      ),
    )
    ..register(
      FunctionTaskHandler<void>(
        name: 'ops.status',
        entrypoint: _handleBroadcast,
        options: const TaskOptions(queue: 'standard'),
      ),
    );
}

Future<void> _processInvoice(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final invoiceId = args['invoiceId'] ?? 'unknown';
  final queue = context.meta['queue'] ?? 'standard';
  final priority = context.meta['priority'] ?? 0;
  final attempt = context.attempt;
  _log(
    'invoice',
    'Queue: $queue | priority: $priority | attempt: $attempt | invoice: $invoiceId',
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
}

Future<void> _processReport(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final subject = args['subject'] ?? 'unnamed report';
  final queue = context.meta['queue'] ?? 'critical';
  final priority = context.meta['priority'] ?? 0;
  final attempt = context.attempt;
  _log(
    'report',
    'Queue: $queue | priority: $priority | attempt: $attempt | subject: $subject',
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

Future<void> _handleBroadcast(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final message = args['message'] ?? 'ping';
  final channel = context.meta['queue'] ?? 'ops';
  _log('broadcast', 'Channel: $channel | $message');
}

void _log(String label, String message) {
  final timestamp = DateTime.now().toIso8601String();
  // ignore: avoid_print
  print('[$timestamp][$label] $message');
}
