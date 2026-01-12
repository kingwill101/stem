import 'package:stem/src/workflow/core/workflow_definition.dart';
import 'package:stem/src/workflow/runtime/workflow_registry.dart';
import 'package:test/test.dart';

void main() {
  test('WorkflowRegistry registers and looks up definitions', () {
    final registry = InMemoryWorkflowRegistry();
    final first = WorkflowDefinition.script(
      name: 'first',
      run: (_) async => null,
    );
    final second = WorkflowDefinition.script(
      name: 'second',
      run: (_) async => null,
    );

    registry
      ..register(first)
      ..register(second);

    expect(registry.lookup('first'), same(first));
    expect(registry.lookup('second'), same(second));
    expect(registry.lookup('missing'), isNull);
  });

  test('WorkflowRegistry returns a copy of registered definitions', () {
    final registry = InMemoryWorkflowRegistry()
      ..register(
        WorkflowDefinition.script(
          name: 'alpha',
          run: (_) async => null,
        ),
      );

    final all = registry.all;
    expect(all, hasLength(1));
    expect(() => all.add(all.first), throwsUnsupportedError);
    expect(registry.all, hasLength(1));
  });
}
