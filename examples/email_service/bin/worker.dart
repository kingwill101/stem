import 'dart:async';
import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:stem/stem.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final broker = await RedisStreamsBroker.connect(config.brokerUrl);
  final backend = config.resultBackendUrl != null
      ? await RedisResultBackend.connect(config.resultBackendUrl!)
      : null;

  if (backend == null) {
    stderr.writeln(
      'STEM_RESULT_BACKEND_URL must be provided for the email service.',
    );
    exit(64);
  }

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'email.send',
        entrypoint: sendEmail,
        options: const TaskOptions(queue: 'emails', maxRetries: 3),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    concurrency: 2, // Allow parallel email sending
  );

  await worker.start();
  stdout.writeln('Email worker started, listening for tasks...');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down email worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
}

Future<String> sendEmail(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final to = args['to'] as String;
  final subject = args['subject'] as String;
  final body = args['body'] as String;
  final host = Platform.environment['SMTP_HOST'] ?? 'mailhog';
  final port =
      int.tryParse(Platform.environment['SMTP_PORT'] ?? '1025') ?? 1025;
  final username = Platform.environment['SMTP_USERNAME'];
  final password = Platform.environment['SMTP_PASSWORD'];
  final useTls =
      (Platform.environment['SMTP_USE_TLS'] ?? 'false').toLowerCase() == 'true';
  final allowInsecure =
      (Platform.environment['SMTP_ALLOW_INSECURE'] ?? 'true').toLowerCase() !=
          'false';

  final smtpServer = SmtpServer(
    host,
    port: port,
    username: (username?.isEmpty ?? true) ? null : username,
    password: (password?.isEmpty ?? true) ? null : password,
    ssl: useTls,
    allowInsecure: allowInsecure,
  );

  final message = Message()
    ..from = Address(
      Platform.environment['EMAIL_FROM_ADDRESS'] ?? 'noreply@example.com',
      Platform.environment['EMAIL_FROM_NAME'] ?? 'Stem Email Service',
    )
    ..recipients.add(to)
    ..subject = subject
    ..text = body;

  try {
    final sendReport = await send(message, smtpServer);
    stdout.writeln('Email sent to $to: ${sendReport.toString()}');
    return 'Email sent successfully';
  } catch (e) {
    stderr.writeln('Failed to send email to $to: $e');
    throw Exception('Email sending failed: $e'); // Triggers retry
  }
}
