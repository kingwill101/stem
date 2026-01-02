// CLI control examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

// #region cli-control-observe-queues
const String observeQueuesCommand = 'stem observe queues';
// #endregion cli-control-observe-queues

// #region cli-control-observe-workers
const String observeWorkersCommand = 'stem observe workers';
// #endregion cli-control-observe-workers

// #region cli-control-observe-dlq
const String observeDlqCommand = 'stem observe dlq';
// #endregion cli-control-observe-dlq

// #region cli-control-observe-schedules
const String observeSchedulesCommand = 'stem observe schedules';
// #endregion cli-control-observe-schedules

// #region cli-control-worker-ping
const String workerPingCommand = 'stem worker ping';
// #endregion cli-control-worker-ping

// #region cli-control-worker-stats
const String workerStatsCommand = 'stem worker stats';
// #endregion cli-control-worker-stats

// #region cli-control-worker-revoke
const String workerRevokeCommand = 'stem worker revoke --task <id>';
// #endregion cli-control-worker-revoke

// #region cli-control-worker-shutdown
const String workerShutdownCommand = 'stem worker shutdown --mode warm';
// #endregion cli-control-worker-shutdown

// #region cli-control-schedule-apply
const String scheduleApplyCommand =
    'stem schedule apply --file config/schedules.yaml --yes';
// #endregion cli-control-schedule-apply

// #region cli-control-schedule-list
const String scheduleListCommand = 'stem schedule list';
// #endregion cli-control-schedule-list

// #region cli-control-schedule-dry-run
const String scheduleDryRunCommand =
    'stem schedule dry-run --spec "every:5m"';
// #endregion cli-control-schedule-dry-run

Future<void> main() async {
  stdout.writeln('Observe:');
  stdout.writeln('  $observeQueuesCommand');
  stdout.writeln('  $observeWorkersCommand');
  stdout.writeln('  $observeDlqCommand');
  stdout.writeln('  $observeSchedulesCommand');

  stdout.writeln('Worker control:');
  stdout.writeln('  $workerPingCommand');
  stdout.writeln('  $workerStatsCommand');
  stdout.writeln('  $workerRevokeCommand');
  stdout.writeln('  $workerShutdownCommand');

  stdout.writeln('Schedules:');
  stdout.writeln('  $scheduleApplyCommand');
  stdout.writeln('  $scheduleListCommand');
  stdout.writeln('  $scheduleDryRunCommand');
}
