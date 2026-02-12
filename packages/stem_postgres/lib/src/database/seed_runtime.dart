import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:ormed/ormed.dart';
import 'package:ormed_postgres/ormed_postgres.dart';
import 'package:stem/stem.dart' show stemLogger;

/// Runs the registered seeders using an existing ORM connection.
Future<void> runSeedRegistryOnConnection(
  OrmConnection connection,
  List<SeederRegistration> seeds, {
  List<String>? names,
  bool pretend = false,
  void Function(OrmConnection connection)? beforeRun,
  void Function(String message)? log,
}) async {
  if (seeds.isEmpty) {
    throw StateError('No seeders registered.');
  }
  final logger = log ?? (String message) => stdout.writeln(message);
  await SeederRunner().run(
    connection: connection,
    seeders: seeds,
    names: (names == null || names.isEmpty) ? null : names,
    pretend: pretend,
    beforeRun: beforeRun,
    onPretendQueries: pretend
        ? (entries) {
            for (final entry in entries) {
              logger('[pretend] ${entry.sql} ${entry.parameters}');
            }
          }
        : null,
  );
}

/// Runs the seeder CLI entrypoint for the provided arguments.
Future<void> runSeedRegistryEntrypoint({
  required List<String> args,
  required List<SeederRegistration> seeds,
  void Function(OrmConnection connection)? beforeRun,
}) async {
  if (seeds.isEmpty) {
    stdout.writeln(jsonEncode(const []));
    return;
  }

  final normalized = _normalizeArgs(args);
  if (normalized.command == _SeedCommand.info) {
    _printSeedInfo(seeds, normalized.args);
    return;
  }

  final parser = ArgParser()
    ..addFlag(
      'pretend',
      negatable: false,
      help: 'Dump queries without executing any seeder.',
    )
    ..addOption('config', help: 'Path to ormed.yaml to use for this run.')
    ..addOption(
      'url',
      help: 'Override the Postgres connection URL for the active connection.',
    )
    ..addOption(
      'connection',
      help: 'Override the active connection name from ormed.yaml.',
    )
    ..addMultiOption(
      'run',
      help: 'Seeder class names to run (comma-separated or repeated).',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );

  final results = _parseArgs(parser, normalized.args, usage: 'seeds run');
  if (results == null) return;
  if (results['help'] == true) {
    stdout
      ..writeln('Usage: seeds run [options]')
      ..writeln(parser.usage);
    return;
  }

  var config = _loadConfig(results['config'] as String?);
  final connectionName = results['connection'] as String?;
  if (connectionName != null && connectionName.trim().isNotEmpty) {
    config = config.withConnection(connectionName.trim());
  }

  final url = results['url'] as String?;
  if (url != null && url.trim().isNotEmpty) {
    config = config.updateActiveConnection(
      driver: config.driver.copyWith(
        options: {...?config.driver.options, 'url': url.trim()},
      ),
    );
  }

  ensurePostgresDriverRegistration();
  final dataSource = DataSource.fromConfig(config, logger: stemLogger);
  await dataSource.init();
  try {
    final requested =
        (results['run'] as List?)?.cast<String>() ?? const <String>[];
    await runSeedRegistryOnConnection(
      dataSource.connection,
      seeds,
      names: requested.isEmpty ? <String>[seeds.first.name] : requested,
      pretend: results['pretend'] == true,
      beforeRun: beforeRun,
    );
  } finally {
    await dataSource.dispose();
  }
}

_SeedArgs _normalizeArgs(List<String> args) {
  if (args.isEmpty) {
    return const _SeedArgs(_SeedCommand.run, <String>[]);
  }
  final first = args.first;
  if (first == 'info' || first == 'list') {
    return _SeedArgs(_SeedCommand.info, args.sublist(1));
  }
  if (first == 'run') {
    return _SeedArgs(_SeedCommand.run, args.sublist(1));
  }
  if (first.startsWith('-') && first != '--help' && first != '-h') {
    return _SeedArgs(_SeedCommand.run, args);
  }
  return _SeedArgs(_SeedCommand.run, args);
}

void _printSeedInfo(List<SeederRegistration> seeds, List<String> args) {
  final parser = ArgParser()
    ..addFlag(
      'json',
      negatable: false,
      help: 'Output seeders as JSON for tooling.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );
  final results = _parseArgs(parser, args, usage: 'seeds info');
  if (results == null) return;
  if (results['help'] == true) {
    stdout
      ..writeln('Usage: seeds info [options]')
      ..writeln(parser.usage);
    return;
  }

  final jsonOut = results['json'] == true;
  if (jsonOut) {
    stdout.writeln(
      jsonEncode(
        seeds.map((seed) => {'name': seed.name}).toList(growable: false),
      ),
    );
    return;
  }

  for (final seed in seeds) {
    stdout.writeln(seed.name);
  }
}

ArgResults? _parseArgs(
  ArgParser parser,
  List<String> args, {
  required String usage,
}) {
  try {
    return parser.parse(args);
  } on FormatException catch (error) {
    stderr
      ..writeln('Invalid arguments for $usage: ${error.message}')
      ..writeln(parser.usage);
    exitCode = 64;
    return null;
  }
}

OrmProjectConfig _loadConfig(String? configPath) {
  if (configPath == null || configPath.trim().isEmpty) {
    return loadOrmConfig();
  }
  return loadOrmProjectConfig(File(configPath));
}

enum _SeedCommand { run, info }

class _SeedArgs {
  const _SeedArgs(this.command, this.args);

  final _SeedCommand command;
  final List<String> args;
}
