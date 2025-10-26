import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:stem/stem.dart';
import 'package:stem_redis/stem_redis.dart';

Future<void> main(List<String> args) async {
  final config = StemConfig.fromEnvironment();
  final broker = await RedisStreamsBroker.connect(
    config.brokerUrl,
    tls: config.tls,
  );
  final backend = config.resultBackendUrl != null
      ? await RedisResultBackend.connect(
          config.resultBackendUrl!,
          tls: config.tls,
        )
      : null;
  final signer = PayloadSigner.maybe(config.signing);

  if (backend == null) {
    stderr.writeln(
      'STEM_RESULT_BACKEND_URL must be provided for the image service.',
    );
    exit(64);
  }

  final registry = SimpleTaskRegistry()
    ..register(
      FunctionTaskHandler<String>(
        name: 'image.generate_thumbnail',
        entrypoint: generateThumbnail,
        options: const TaskOptions(queue: 'images', maxRetries: 2),
      ),
    );

  final worker = Worker(
    broker: broker,
    registry: registry,
    backend: backend,
    concurrency: 2, // Parallel processing
    signer: signer,
  );

  await worker.start();
  stdout.writeln('Image worker started, listening for tasks...');

  Future<void> shutdown(ProcessSignal signal) async {
    stdout.writeln('Shutting down image worker ($signal)...');
    await worker.shutdown();
    await broker.close();
    await backend.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
}

Future<String> generateThumbnail(
  TaskInvocationContext context,
  Map<String, Object?> args,
) async {
  final imageUrl = args['imageUrl'] as String;

  try {
    // Download image
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image: ${response.statusCode}');
    }

    final image = img.decodeImage(response.bodyBytes);
    if (image == null) {
      throw Exception('Invalid image format');
    }

    // Resize to thumbnail (200x200, maintain aspect ratio)
    final thumbnail = img.copyResize(image, width: 200, height: 200);

    // Save to temp directory
    final outputDirPath =
        Platform.environment['OUTPUT_DIR'] ?? Directory.systemTemp.path;
    final tempDir = Directory(outputDirPath);
    if (!tempDir.existsSync()) {
      await tempDir.create(recursive: true);
    }
    final fileName = 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = path.join(tempDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(img.encodeJpg(thumbnail));

    stdout.writeln('Thumbnail generated: $filePath');
    return filePath; // In real app, upload to S3 and return URL
  } catch (e) {
    stderr.writeln('Failed to process image $imageUrl: $e');
    throw Exception('Thumbnail generation failed: $e');
  }
}
