import 'dart:io';

import 'package:artisanal/args.dart';

import 'commands/coverage_command.dart';
import 'commands/benchmark_throughput_command.dart';
import 'commands/demo_commands.dart';
import 'commands/deps_command.dart';
import 'commands/profile_job_command.dart';
import 'commands/profile_vm_command.dart';
import 'commands/quality_command.dart';
import 'commands/standalone_command.dart';
import 'commands/test_commands.dart';
import 'commands/workspace_command.dart';

CommandRunner<int> createRepodocRunner() {
  return CommandRunner<int>(
      'repodoc',
      'Central repository maintenance and diagnostics for Stem.',
    )
    ..addCommand(DepsCommand())
    ..addCommand(WorkspaceCheckCommand())
    ..addCommand(QualityDartCommand())
    ..addCommand(StandaloneDartCommand())
    ..addCommand(StandaloneDartCommand(flutterOnly: true))
    ..addCommand(TestCommand(TestTarget.integration))
    ..addCommand(TestCommand(TestTarget.noEnvironment))
    ..addCommand(TestCommand(TestTarget.flutter))
    ..addCommand(TestCommand(TestTarget.all))
    ..addCommand(TestCommand(TestTarget.contract))
    ..addCommand(TestCommand(TestTarget.redis))
    ..addCommand(TestCommand(TestTarget.postgres))
    ..addCommand(PackageTestCommand())
    ..addCommand(CoverageCommand(CoverageTarget.withEnvironment))
    ..addCommand(CoverageCommand(CoverageTarget.withoutEnvironment))
    ..addCommand(PackageCoverageCommand())
    ..addCommand(BenchmarkThroughputCommand())
    ..addCommand(DemoCommand(DemoTarget.annotated))
    ..addCommand(DemoCommand(DemoTarget.builder))
    ..addCommand(DemoCommand(DemoTarget.ecommerce))
    ..addCommand(DemoCommand(DemoTarget.all))
    ..addCommand(ProfileJobCommand())
    ..addCommand(ProfileJobCommand(commandName: 'profile:job:aot'))
    ..addCommand(ProfileVmCommand());
}

Future<int> runRepodoc(List<String> arguments) async {
  final runner = createRepodocRunner();
  try {
    return await runner.run(arguments) ?? 0;
  } catch (error) {
    stderr.writeln(error);
    return 1;
  }
}
