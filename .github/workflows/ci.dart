import 'package:gha/gha.dart';

void main() {
  final workflow = Workflow(
    name: 'CI',
    on: const WorkflowTriggers(
      push: TriggerConfig(branches: ['master']),
      pullRequest: TriggerConfig(),
    ),
    jobs: {
      'build-and-test': Job(
        name: 'Build and Test',
        runsOn: RunnerSpec.single('ubuntu-latest'),
        env: const {
          'STEM_TEST_REDIS_URL': 'redis://127.0.0.1:56379',
          'STEM_TEST_POSTGRES_URL':
              'postgresql://postgres:postgres@127.0.0.1:65432/stem_test',
          'STEM_TEST_POSTGRES_TLS_URL':
              'postgresql://postgres:postgres@127.0.0.1:65432/stem_test',
          'STEM_TEST_POSTGRES_TLS_CA_CERT':
              'packages/stem_cli/docker/testing/certs/postgres-root.crt',
          'STEM_CHAOS_REDIS_URL': 'redis://127.0.0.1:56379/15',
        },
        services: const {
          'redis': ServiceContainer(
            image: 'redis:7',
            ports: ['56379:6379'],
            options:
                '--health-cmd "redis-cli ping" --health-interval 5s --health-timeout 3s --health-retries 5',
          ),
          'postgres': ServiceContainer(
            image: 'postgres:15-alpine',
            env: {
              'POSTGRES_USER': 'postgres',
              'POSTGRES_PASSWORD': 'postgres',
              'POSTGRES_DB': 'stem_test',
            },
            ports: ['65432:5432'],
            options:
                '--health-cmd "pg_isready -U postgres" --health-interval 10s --health-timeout 5s --health-retries 5',
          ),
        },
        steps: [
          checkout(),
          setupDart(sdk: 'stable'),
          const Step(name: 'Fetch dependencies', run: 'dart pub get'),
          const Step(
            name: 'Run quality checks',
            run: 'tool/quality/run_quality_checks.sh',
            env: {
              'COVERAGE_THRESHOLD': '60',
            },
          ),
          const Step(
            name: 'Validate OpenSpec changes',
            run: '''if command -v openspec >/dev/null 2>&1; then
  openspec validate --strict
else
  echo 'openspec CLI not available; skipping validation'
fi''',
          ),
          const Step(
            name: 'Install Node.js',
            uses: 'actions/setup-node@v4',
            withArguments: {'node-version': '18'},
          ),
          const Step(
            name: 'Install Docusaurus dependencies',
            workingDirectory: '.site',
            run: 'npm install',
          ),
          const Step(
            name: 'Build docs',
            workingDirectory: '.site',
            run: 'npm run build',
          ),
          const Step(
            name: 'Monolith example smoke test',
            run: 'dart run scripts/test_monolith.dart',
          ),
          const Step(
            name: 'Microservice smoke test',
            run: 'dart run scripts/test_microservice.dart',
          ),
        ],
      ),
    },
  );

  workflow.save();
}
