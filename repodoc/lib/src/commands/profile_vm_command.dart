import 'dart:io';

import 'package:artisanal/args.dart';
import 'package:path/path.dart' as p;

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';

final class ProfileVmCommand extends Command<int> {
  ProfileVmCommand() {
    argParser
      ..addOption('tasks', defaultsTo: '5000')
      ..addOption('warmup', defaultsTo: '500')
      ..addOption('concurrency', defaultsTo: '4')
      ..addOption('mode', defaultsTo: 'isolate')
      ..addOption('workload', defaultsTo: 'noop')
      ..addOption('work-units', defaultsTo: '100')
      ..addOption('hold-seconds', defaultsTo: '0')
      ..addOption(
        'service-info',
        defaultsTo: 'build/stem-profile/vm-service.json',
      );
  }

  @override
  String get name => 'profile:job:vm';

  @override
  String get description =>
      'Pause a job profile under the Dart VM service for DevTools.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final root = catalog.root;
    final serviceInfo = _required('service-info');
    await File(p.join(root.path, serviceInfo)).parent.create(recursive: true);
    stdout.writeln('VM service details will be written to $serviceInfo');
    stdout.writeln(
      'Connect DevTools, resume the paused isolate, and inspect CPU, '
      'timeline, and allocations.',
    );
    await ProcessRunner(environment: catalog.processEnvironment).run(
      'dart',
      [
        'run',
        '--observe=0',
        '--pause-isolates-on-start',
        '--timeline-streams=all',
        '--write-service-info=$serviceInfo',
        'benchmark/stem_job_profile.dart',
        '--tasks',
        _required('tasks'),
        '--warmup',
        _required('warmup'),
        '--concurrency',
        _required('concurrency'),
        '--mode',
        _required('mode'),
        '--workload',
        _required('workload'),
        '--work-units',
        _required('work-units'),
        '--hold-seconds',
        _required('hold-seconds'),
      ],
      workingDirectory: root,
      label: 'VM job profile',
    );
    return 0;
  }

  String _required(String name) {
    final value = argResults?[name];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('Missing profile option: --$name');
    }
    return value;
  }
}
