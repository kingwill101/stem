import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await Process.run(
      'dart',
      [
        'pub',
        'get',
      ],
      workingDirectory: 'examples/monolith_service');

  final process = await Process.start(
      'dart',
      [
        'run',
        'bin/service.dart',
      ],
      workingDirectory: 'examples/monolith_service');

  process.stdout.transform(utf8.decoder).listen(stdout.write);
  process.stderr.transform(utf8.decoder).listen(stderr.write);

  await Future<void>.delayed(const Duration(seconds: 2));

  final client = HttpClient();
  final request = await client.post('localhost', 8080, '/enqueue');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'name': 'CI'}));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  stdout.writeln('enqueue response: $body');

  process.kill(ProcessSignal.sigint);
  await process.exitCode;
  client.close();
}
