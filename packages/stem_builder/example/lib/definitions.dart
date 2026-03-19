import 'package:stem/stem.dart';

part 'definitions.stem.g.dart';

@WorkflowDefn(name: 'builder.example.flow')
class BuilderExampleFlow {
  @WorkflowStep(name: 'greet')
  Future<String> greet(String name) async {
    return 'hello $name';
  }
}

@WorkflowDefn(name: 'builder.example.user_signup', kind: WorkflowKind.script)
class BuilderUserSignupWorkflow {
  Future<Map<String, Object?>> run(String email) async {
    final user = await createUser(email);
    await sendWelcomeEmail(email);
    await sendOneWeekCheckInEmail(email);
    return {'userId': user['id'], 'status': 'done'};
  }

  @WorkflowStep(name: 'create-user')
  Future<Map<String, Object?>> createUser(String email) async {
    return {'id': 'user:$email'};
  }

  @WorkflowStep(name: 'send-welcome-email')
  Future<void> sendWelcomeEmail(String email) async {}

  @WorkflowStep(name: 'send-one-week-check-in-email')
  Future<void> sendOneWeekCheckInEmail(String email) async {}
}

@TaskDefn(name: 'builder.example.task')
Future<void> builderExampleTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {}

@TaskDefn(name: 'builder.example.ping')
Future<String> builderPingTask() async => 'pong';
