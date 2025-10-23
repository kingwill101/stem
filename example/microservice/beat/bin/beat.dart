import 'dart:async';
import 'dart:io';

import 'package:stem/stem.dart';
import 'package:yaml/yaml.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();

  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );

  final scheduleUrl = config.scheduleStoreUrl ?? config.brokerUrl;
  final scheduleStore = await RedisScheduleStore.connect(
    scheduleUrl,
    tls: config.tls,
  );
  final lockStore = await RedisLockStore.connect(scheduleUrl, tls: config.tls);
  final signer = PayloadSigner.maybe(config.signing);

  final beat = Beat(
    store: scheduleStore,
    broker: broker,
    lockStore: lockStore,
    tickInterval: const Duration(seconds: 1),
    signer: signer,
  );

  final seedPath = Platform.environment['STEM_SCHEDULE_FILE']?.trim();
  if (seedPath != null && seedPath.isNotEmpty) {
    await _seedSchedules(scheduleStore, seedPath);
  }

  await beat.start();
  stdout.writeln('Beat scheduler started (broker: ${config.brokerUrl}).');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down beat (${signal.toString()})');
    await beat.stop();
    await scheduleStore.close();
    await lockStore.close();
    await broker.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  await Completer<void>().future;
}

Future<void> _seedSchedules(ScheduleStore store, String path) async {
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('Schedule seed file not found at $path');
    return;
  }

  final raw = await file.readAsString();
  final doc = loadYaml(raw);
  if (doc is! YamlMap || !doc.containsKey('entries')) {
    stderr.writeln('Seed file $path must contain an "entries" list.');
    return;
  }

  final entries = doc['entries'];
  if (entries is! YamlList) {
    stderr.writeln('Seed file $path: "entries" must be a list.');
    return;
  }

  for (final element in entries) {
    if (element is! YamlMap) continue;

    final id = element['id']?.toString();
    final taskName =
        element['task']?.toString() ?? element['taskName']?.toString();
    if (id == null || taskName == null) {
      stderr.writeln('Skipping schedule missing id/task: $element');
      continue;
    }
    final queue = element['queue']?.toString() ?? 'default';
    final specRaw = element['spec'];
    final spec = ScheduleSpec.fromPersisted(specRaw ?? 'every:60s');
    final jitterRaw = element['jitter'];
    final enabled = element['enabled'] != false;
    final timezone = element['timezone']?.toString();
    final args = element['args'] is Map
        ? Map<String, Object?>.from(
            (element['args'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : const <String, Object?>{};
    final meta = element['meta'] is Map
        ? Map<String, Object?>.from(
            (element['meta'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : const <String, Object?>{};

    final entry = ScheduleEntry(
      id: id,
      taskName: taskName,
      queue: queue,
      spec: spec,
      args: args,
      enabled: enabled,
      jitter: _parseDuration(jitterRaw),
      timezone: timezone,
      meta: meta,
    );

    await store.upsert(entry);
    stdout.writeln(
      'Seeded schedule ${entry.id} -> ${entry.taskName} (${_describeSpec(entry.spec)})',
    );
  }
}

String _describeSpec(ScheduleSpec spec) {
  switch (spec) {
    case IntervalScheduleSpec interval:
      return 'every ${interval.every.inSeconds}s';
    case CronScheduleSpec cron:
      return cron.expression;
    case SolarScheduleSpec solar:
      return '${solar.event} @${solar.latitude}/${solar.longitude}';
    case ClockedScheduleSpec clocked:
      return 'once ${clocked.runAt.toIso8601String()}';
    case CalendarScheduleSpec calendar:
      return 'calendar ${calendar.toJson()}';
  }
}

Duration? _parseDuration(Object? value) {
  if (value == null) return null;
  if (value is int) {
    return Duration(seconds: value);
  }
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final match = RegExp(r'^(\d+)(ms|s|m|h)$').firstMatch(raw);
  if (match == null) {
    stderr.writeln(
      'Unable to parse duration "$raw"; expected formats like 500ms, 30s, 5m, 1h.',
    );
    return null;
  }
  final amount = int.parse(match.group(1)!);
  switch (match.group(2)) {
    case 'ms':
      return Duration(milliseconds: amount);
    case 's':
      return Duration(seconds: amount);
    case 'm':
      return Duration(minutes: amount);
    case 'h':
      return Duration(hours: amount);
  }
  return null;
}
