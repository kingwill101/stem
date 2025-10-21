import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await Process.run(
      'docker',
      [
        'compose',
        'up',
        '-d',
        'redis',
      ],
      workingDirectory: 'examples/microservice');

  final env = {
    ...Platform.environment,
    'STEM_BROKER_URL': 'redis://localhost:6379/0',
    'STEM_RESULT_BACKEND_URL': 'redis://localhost:6379/1',
  };

  await Process.run(
      'dart',
      [
        'pub',
        'get',
      ],
      workingDirectory: 'examples/microservice/worker');
  await Process.run(
      'dart',
      [
        'pub',
        'get',
      ],
      workingDirectory: 'examples/microservice/enqueuer');

  final worker = await Process.start(
    'dart',
    ['run', 'bin/worker.dart'],
    workingDirectory: 'examples/microservice/worker',
    environment: env,
  );
  worker.stdout.transform(utf8.decoder).listen(stdout.write);
  worker.stderr.transform(utf8.decoder).listen(stderr.write);

  await Future<void>.delayed(const Duration(seconds: 3));

  final enqueuer = await Process.start(
    'dart',
    ['run', 'bin/main.dart'],
    workingDirectory: 'examples/microservice/enqueuer',
    environment: env,
  );
  enqueuer.stdout.transform(utf8.decoder).listen(stdout.write);
  enqueuer.stderr.transform(utf8.decoder).listen(stderr.write);

  await Future<void>.delayed(const Duration(seconds: 2));

  final client = HttpClient();
  final request = await client.post('localhost', 8081, '/enqueue');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'name': 'CI'}));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  stdout.writeln('enqueue response: $body');

  enqueuer.kill(ProcessSignal.sigint);
  worker.kill(ProcessSignal.sigint);
  await enqueuer.exitCode;
  await worker.exitCode;
  client.close();

  await Process.run(
      'docker',
      [
        'compose',
        'down',
      ],
      workingDirectory: 'examples/microservice');
}
