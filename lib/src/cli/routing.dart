import 'dart:convert';

import 'package:args/command_runner.dart';

import '../core/config.dart';
import '../routing/routing_config.dart';
import '../routing/routing_registry.dart';
import '../routing/subscription_loader.dart';
import 'dependencies.dart';

class RoutingCommand extends Command<int> {
  RoutingCommand(this.dependencies) {
    addSubcommand(RoutingDumpCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  String get name => 'routing';

  @override
  String get description => 'Inspect or generate routing configuration.';

  @override
  Future<int> run() async {
    throw UsageException('Specify a routing subcommand.', usage);
  }
}

class RoutingDumpCommand extends Command<int> {
  RoutingDumpCommand(this.dependencies) {
    argParser
      ..addFlag(
        'sample',
        defaultsTo: false,
        help: 'Emit a skeleton configuration instead of the active one.',
      )
      ..addFlag(
        'json',
        defaultsTo: false,
        help: 'Emit the configuration as JSON.',
      );
  }

  final StemCommandDependencies dependencies;

  @override
  String get name => 'dump';

  @override
  String get description => 'Print the active routing configuration.';

  @override
  Future<int> run() async {
    final args = argResults!;
    final sample = args['sample'] as bool? ?? false;
    final asJson = args['json'] as bool? ?? false;

    StemConfig config;
    try {
      config = StemConfig.fromEnvironment(dependencies.environment);
    } on Object catch (error) {
      dependencies.err.writeln('Failed to load Stem configuration: $error');
      return 64;
    }

    RoutingRegistry registry;
    if (sample) {
      registry = RoutingRegistry(RoutingConfig.legacy());
    } else {
      try {
        registry = RoutingConfigLoader(
          StemRoutingContext.fromConfig(config),
        ).load();
      } on StateError catch (error) {
        dependencies.err.writeln(error.message);
        return 64;
      } on Object catch (error) {
        dependencies.err
            .writeln('Failed to load routing configuration: $error');
        return 70;
      }
    }

    final buffer = StringBuffer();
    if (asJson) {
      final encoder = JsonEncoder.withIndent('  ');
      buffer.writeln(encoder.convert(registry.config.toJson()));
    } else if (sample) {
      buffer.writeln(_sampleYaml());
    } else {
      buffer.writeln(_renderYaml(registry.config));
    }
    dependencies.out.write(buffer.toString());
    if (!buffer.toString().endsWith('\n')) {
      dependencies.out.writeln();
    }
    return 0;
  }

  String _renderYaml(RoutingConfig config) {
    final buffer = StringBuffer()..writeln('queues:');
    config.queues.forEach((name, definition) {
      buffer.writeln('  $name:');
      buffer.writeln(
          '    priorityRange: ${definition.priorityRange.min}-${definition.priorityRange.max}');
      if (definition.exchange != null) {
        buffer.writeln('    exchange: ${definition.exchange}');
      }
      if (definition.routingKey != null) {
        buffer.writeln('    routingKey: ${definition.routingKey}');
      }
    });

    if (config.broadcasts.isNotEmpty) {
      buffer.writeln('broadcasts:');
      config.broadcasts.forEach((name, definition) {
        buffer.writeln('  $name:');
        buffer.writeln('    delivery: ${definition.delivery}');
        if (definition.durability != null) {
          buffer.writeln('    durability: ${definition.durability}');
        }
      });
    }

    if (config.routes.isNotEmpty) {
      buffer.writeln('routes:');
      for (final route in config.routes) {
        buffer.writeln('  - match:');
        if (route.match.taskGlobs != null &&
            route.match.taskGlobs!.isNotEmpty) {
          final tasks =
              route.match.taskGlobs!.map((glob) => glob.pattern).join(', ');
          buffer.writeln('      task: $tasks');
        }
        if (route.match.queueOverride != null) {
          buffer.writeln('      queue: ${route.match.queueOverride}');
        }
        if (route.match.headers.isNotEmpty) {
          buffer.writeln('      headers:');
          route.match.headers.forEach((key, value) {
            buffer.writeln('        $key: $value');
          });
        }
        buffer.writeln('    target:');
        buffer.writeln('      type: ${route.target.type}');
        buffer.writeln('      name: ${route.target.name}');
        if (route.priorityOverride != null) {
          buffer.writeln('    priorityOverride: ${route.priorityOverride}');
        }
      }
    }

    return buffer.toString();
  }

  String _sampleYaml() => '''
queues:
  default:
    priorityRange: 0-9
  critical:
    priorityRange: 0-9

broadcasts:
  maintenance:
    delivery: at-least-once

routes:
  - match:
      task: example.*
    target:
      type: queue
      name: critical
''';
}
