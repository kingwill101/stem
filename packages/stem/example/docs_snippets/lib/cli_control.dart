// CLI control examples for documentation.
// ignore_for_file: unused_local_variable, unused_import, dead_code, avoid_print

import 'dart:io';

// #region cli-control-observe
List<String> observeCommands() {
  return const [
    'stem observe queues',
    'stem observe workers',
    'stem observe dlq',
    'stem observe schedules',
  ];
}
// #endregion cli-control-observe

// #region cli-control-worker
List<String> workerControlCommands() {
  return const [
    'stem worker ping',
    'stem worker stats',
    'stem worker revoke --task <id>',
    'stem worker shutdown --mode warm',
  ];
}
// #endregion cli-control-worker

// #region cli-control-schedule
List<String> scheduleCommands() {
  return const [
    'stem schedule apply --file config/schedules.yaml --yes',
    'stem schedule list',
    'stem schedule dry-run --spec "every:5m"',
  ];
}
// #endregion cli-control-schedule

Future<void> main() async {
  stdout.writeln('Observe:');
  for (final command in observeCommands()) {
    stdout.writeln('  $command');
  }

  stdout.writeln('Worker control:');
  for (final command in workerControlCommands()) {
    stdout.writeln('  $command');
  }

  stdout.writeln('Schedules:');
  for (final command in scheduleCommands()) {
    stdout.writeln('  $command');
  }
}
