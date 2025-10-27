import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:stem/stem.dart';

import 'cli_runner.dart';
import 'dependencies.dart';
import 'utilities.dart';

class TasksCommand extends Command<int> {
  TasksCommand(this.dependencies) {
    addSubcommand(_TasksListCommand(dependencies));
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'tasks';

  @override
  final String description = 'Inspect registered tasks and metadata.';

  @override
  Future<int> run() async {
    throw UsageException('Specify a subcommand.', usage);
  }
}

class _TasksListCommand extends Command<int> {
  _TasksListCommand(this.dependencies) {
    argParser.addFlag(
      'json',
      help: 'Emit task metadata as JSON.',
      negatable: false,
      defaultsTo: false,
    );
  }

  final StemCommandDependencies dependencies;

  @override
  final String name = 'ls';

  @override
  final String description =
      'List registered tasks with descriptions, tags, and idempotency.';

  @override
  Future<int> run() async {
    final bool jsonOutput = argResults?['json'] as bool? ?? false;
    CliContext? context;
    try {
      context = await dependencies.createCliContext();
      final registry = context.registry;
      if (registry == null) {
        dependencies.out.writeln(
          'No task registry available; provide a contextBuilder that sets CliContext.registry.',
        );
        return 0;
      }

      final handlers = registry.handlers.toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (jsonOutput) {
        final payload = handlers
            .map((handler) => _serializeHandler(handler))
            .toList(growable: false);
        dependencies.out.writeln(jsonEncode(payload));
      } else {
        if (handlers.isEmpty) {
          dependencies.out.writeln('No tasks registered.');
        } else {
          _renderTable(handlers);
        }
      }

      return 0;
    } on UsageException {
      rethrow;
    } catch (error, stackTrace) {
      dependencies.err
        ..writeln('Failed to list tasks: $error')
        ..writeln(stackTrace);
      return 70;
    } finally {
      if (context != null) {
        await context.dispose();
      }
    }
  }

  Map<String, Object?> _serializeHandler(TaskHandler handler) {
    final metadata = handler.metadata;
    final options = handler.options;
    return {
      'name': handler.name,
      'description': metadata.description,
      'idempotent': metadata.idempotent,
      'tags': metadata.tags,
      'queue': options.queue,
      'maxRetries': options.maxRetries,
      'priority': options.priority,
    };
  }

  void _renderTable(List<TaskHandler> handlers) {
    final nameWidth = handlers.fold<int>(
      4,
      (width, handler) =>
          width > handler.name.length ? width : handler.name.length,
    );
    final descWidth = handlers.fold<int>(11, (width, handler) {
      final description = handler.metadata.description ?? '';
      return width > description.length ? width : description.length;
    });
    final tagsWidth = handlers.fold<int>(4, (width, handler) {
      final tags = handler.metadata.tags.join(', ');
      return width > tags.length ? width : tags.length;
    });

    final out = dependencies.out;
    out.writeln(
      '${padCell('NAME', nameWidth)}  '
      '${padCell('DESCRIPTION', descWidth)}  '
      '${padCell('IDEMPOTENT', 11)}  '
      '${padCell('TAGS', tagsWidth)}',
    );
    out.writeln('-' * (nameWidth + descWidth + tagsWidth + 6 + 11));
    for (final handler in handlers) {
      final metadata = handler.metadata;
      final tags = metadata.tags.isEmpty ? '-' : metadata.tags.join(', ');
      out.writeln(
        '${padCell(handler.name, nameWidth)}  '
        '${padCell(metadata.description ?? '-', descWidth)}  '
        '${padCell(metadata.idempotent ? 'yes' : 'no', 11)}  '
        '${padCell(tags, tagsWidth)}',
      );
    }
  }
}
