import 'package:gha/gha.dart';

void main() {
  final workflow = Workflow(
    name: 'Security Scan',
    on: const WorkflowTriggers(
      schedule: [CronSchedule('0 6 * * 1')],
      workflowDispatch: TriggerConfig(),
    ),
    jobs: {
      'vulnerability-scan': Job(
        name: 'Trivy Vulnerability Scan',
        runsOn: RunnerSpec.single('ubuntu-latest'),
        steps: [
          checkout(),
          setupDart(sdk: "stable"),
          const Step(
            name: 'Run vulnerability scan',
            run: './scripts/security/run_vulnerability_scan.sh',
            env: {'TRIVY_SEVERITY': 'CRITICAL,HIGH', 'TRIVY_FAIL_ON': '1'},
          ),
        ],
      ),
    },
  );

  workflow.save();
}
