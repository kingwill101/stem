import 'package:stem/stem.dart';
import 'package:test/test.dart';

void main() {
  test('workflow definitions expose stable ids and manifest entries', () {
    final definition = Flow(
      name: 'manifest.flow',
      version: '1.0.0',
      build: (flow) {
        flow
          ..step('first', (context) async => 'ok')
          ..step('second', (context) async => context.previousResult);
      },
    ).definition;

    final firstId = definition.stableId;
    final secondId = definition.stableId;
    expect(firstId, equals(secondId));

    final manifest = definition.toManifestEntry();
    expect(manifest.id, equals(firstId));
    expect(manifest.name, equals('manifest.flow'));
    expect(manifest.kind, equals(WorkflowDefinitionKind.flow));
    expect(manifest.steps, hasLength(2));
    expect(manifest.steps.first.position, equals(0));
    expect(manifest.steps.first.name, equals('first'));
    expect(manifest.steps.first.id, isNotEmpty);
    expect(manifest.steps.first.id, isNot(equals(manifest.steps.last.id)));
  });

  test('script workflows can publish declared step metadata', () {
    final definition = WorkflowScript<Map<String, Object?>>(
      name: 'manifest.script',
      run: (script) async {
        final email = script.params['email'] as String;
        return {'email': email, 'status': 'done'};
      },
      steps: [
        FlowStep(
          name: 'create-user',
          title: 'Create user',
          kind: WorkflowStepKind.task,
          taskNames: const ['user.create'],
          handler: (context) async => {'id': '1'},
        ),
        FlowStep(
          name: 'send-welcome-email',
          title: 'Send welcome email',
          kind: WorkflowStepKind.task,
          taskNames: const ['email.send'],
          handler: (context) async => null,
        ),
      ],
    ).definition;

    final manifest = definition.toManifestEntry();
    expect(manifest.kind, equals(WorkflowDefinitionKind.script));
    expect(manifest.steps, hasLength(2));
    expect(manifest.steps.first.name, equals('create-user'));
    expect(manifest.steps.first.position, equals(0));
    expect(manifest.steps.first.taskNames, equals(const ['user.create']));
    expect(manifest.steps.last.name, equals('send-welcome-email'));
    expect(manifest.steps.last.position, equals(1));
    expect(manifest.steps.last.taskNames, equals(const ['email.send']));
  });
}
