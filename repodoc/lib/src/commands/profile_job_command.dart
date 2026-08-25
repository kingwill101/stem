import 'package:artisanal/args.dart';

import '../infrastructure/process_runner.dart';
import '../infrastructure/workspace.dart';

final class ProfileJobCommand extends Command<int> {
  final String commandName;

  ProfileJobCommand({this.commandName = 'profile:job'}) {
    argParser
      ..addOption('tasks', defaultsTo: '5000')
      ..addOption('warmup', defaultsTo: '500')
      ..addOption('concurrency', defaultsTo: '4')
      ..addOption('mode', defaultsTo: 'isolate')
      ..addOption('workload', defaultsTo: 'noop')
      ..addOption('work-units', defaultsTo: '100')
      ..addOption('repetitions', defaultsTo: '5')
      ..addOption('output')
      ..addFlag(
        'json',
        help: 'Print the raw JSON result instead of the terminal summary.',
        negatable: false,
      );
  }

  @override
  String get name => commandName;

  @override
  String get description => commandName == 'profile:job:aot'
      ? 'Alias for profile:job; run repeated AOT profiling trials.'
      : 'Run repeated AOT profiling trials for Stem jobs.';

  @override
  Future<int> run() async {
    final catalog = WorkspaceCatalog.load();
    final root = catalog.root;
    final args = <String>[
      'run',
      'tool/profile_job.dart',
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
      '--repetitions',
      _required('repetitions'),
    ];
    final output = argResults?['output'] as String?;
    if (output != null && output.isNotEmpty) {
      args.addAll(['--output', output]);
    }
    if (argResults?['json'] == true) args.add('--json');
    await ProcessRunner(
      environment: catalog.processEnvironment,
    ).run('dart', args, workingDirectory: root, label: 'AOT job profile');
    return 0;
  }

  String _required(String name) {
    final value = argResults?[name];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Missing profile option: --$name');
    }
    return value;
  }
}
