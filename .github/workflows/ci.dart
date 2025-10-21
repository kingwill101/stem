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
        services: {
          'redis': const ServiceContainer(
            image: 'redis:7',
            ports: ['6379:6379'],
            options:
                '--health-cmd "redis-cli ping" '
                '--health-interval 5s '
                '--health-timeout 5s '
                '--health-retries 20',
          ),
        },
        steps: [
          checkout(),
          setupDart(sdk: '3.5.0'),
          const Step(name: 'Fetch dependencies', run: 'dart pub get'),
          const Step(
            name: 'Run quality checks',
            run: 'tool/quality/run_quality_checks.sh',
            env: {
              'STEM_CHAOS_REDIS_URL': 'redis://127.0.0.1:6379/15',
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
