import 'package:stem/stem.dart';
import 'package:stem_cli/src/cli/cli_runner.dart';
import 'package:stem_cli/src/cli/dependencies.dart';
import 'package:stem_cloud_worker/stem_cloud_worker.dart';
import 'package:test/test.dart';

void main() {
  test('schedule context uses cloud store for http URL', () async {
    final deps = StemCommandDependencies(
      out: StringBuffer(),
      err: StringBuffer(),
      environment: const {
        'STEM_SCHEDULE_STORE_URL': 'http://localhost:8080/v1',
        'STEM_CLOUD_API_KEY': 'token',
      },
      scheduleFilePath: null,
      cliContextBuilder: () async => CliContext(
        broker: InMemoryBroker(),
        routing: RoutingRegistry(RoutingConfig.legacy()),
        dispose: () async {},
      ),
    );

    final context = await deps.createScheduleContext();
    expect(context.store, isA<StemCloudScheduleStore>());
    await context.dispose();
  });
}
