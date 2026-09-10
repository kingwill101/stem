import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_stem_example/src/demo_tasks.dart';
import 'package:image/image.dart' as img;
import 'package:stem_flutter/stem_flutter.dart';

// Independent heaps, synchronized immediately before writing, not just two
// futures serializing CPU work on the test isolate.
Future<void> _overlappingPhoto((Map<String, Object?>, SendPort) message) async {
  final (json, reply) = message;
  final release = ReceivePort();
  try {
    final result = await processPhoto(
      PhotoTaskArgs.fromJson(json),
      onProgress: (percent, _) async {
        if (percent == 85) {
          reply.send(release.sendPort);
          await release.first;
        }
      },
    );
    reply.send(result);
  } catch (error, stack) {
    reply.send('$error\n$stack');
  } finally {
    release.close();
  }
}

Future<void> _verifyResult(Map<String, Object?> result) async {
  final hashes = result['checksums']! as Map;
  for (final (key, width, height) in [
    ('sourcePath', 'width', 'height'),
    ('previewPath', 'previewWidth', 'previewHeight'),
    ('thumbnailPath', 'thumbnailWidth', 'thumbnailHeight'),
  ]) {
    final bytes = await File(result[key]! as String).readAsBytes();
    expect(sha256.convert(bytes).toString(), hashes[key]);
    final image = img.decodeJpg(bytes)!;
    expect(image.width, result[width]);
    expect(image.height, result[height]);
  }
}

void main() {
  late Directory directory;
  PhotoTaskArgs args({
    int index = 0,
    int width = 96,
    int height = 64,
    String batchId = 'test-batch',
  }) => PhotoTaskArgs(
    outputDirectory: directory.path,
    batchId: batchId,
    index: index,
    width: width,
    height: height,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('stem-photo-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'module executes isolated photo task and reuses verified artifacts',
    () async {
      final app = await StemApp.inMemory(
        module: demoModule,
        workerConfig: StemFlutter.defaultWorkerConfig,
      );
      addTearDown(app.close);
      await app.start();
      Future<Map<String, Object?>> run() async {
        final id = await app.enqueueCall(preparePhoto.buildCall(args()));
        final result = await preparePhoto.waitFor(
          app,
          id,
          timeout: const Duration(seconds: 20),
        );
        expect(result?.value, isNotNull);
        return result!.value!;
      }

      final first = await run();
      expect(first['reused'], false);
      expect(first['batchId'], 'test-batch');
      expect(first['index'], 0);
      for (final key in ['sourcePath', 'previewPath', 'thumbnailPath']) {
        final bytes = await File(first[key]! as String).readAsBytes();
        final decoded = img.decodeJpg(bytes)!;
        expect(decoded.width, 96);
        expect(decoded.height, 64);
        if (key == 'previewPath') {
          expect(first['sha256'], sha256.convert(bytes).toString());
        }
      }
      final second = await run();
      expect(second, {...first, 'reused': true});
    },
  );

  test('recovers corrupt/missing artifacts and malformed manifest', () async {
    final first = await processPhoto(args());
    final manifest = File('${directory.path}/test-batch/photo-0/manifest.json');
    await File(first['previewPath']! as String).writeAsString('incomplete');
    final repaired = await processPhoto(args());
    expect(repaired['reused'], false);
    expect(repaired['sha256'], first['sha256']);
    await File(repaired['thumbnailPath']! as String).delete();
    expect((await processPhoto(args()))['reused'], false);
    await manifest.writeAsString('{broken');
    expect((await processPhoto(args()))['reused'], false);
    final stored = jsonDecode(await manifest.readAsString()) as Map;
    expect(stored['sha256'], first['sha256']);
    await manifest.delete();
    expect((await processPhoto(args()))['reused'], false);
  });

  test(
    'changed config rebuilds; photo indices produce distinct images',
    () async {
      final first = await processPhoto(args());
      final other = await processPhoto(args(index: 1));
      expect(other['sha256'], isNot(first['sha256']));
      final resized = await processPhoto(args(width: 384, height: 256));
      expect(resized['reused'], false);
      expect(resized['width'], 384);
      final thumb = img.decodeJpg(
        await File(resized['thumbnailPath']! as String).readAsBytes(),
      )!;
      expect(thumb.width, 256);
      expect(thumb.height, 171);
      expect(
        (await processPhoto(args(width: 384, height: 256)))['reused'],
        true,
      );
    },
  );

  test('independent overlapping attempts publish whole generations', () async {
    final replies = ReceivePort();
    final ready = <SendPort>[];
    final results = <Map<String, Object?>>[];
    final isolates = <Isolate>[];
    addTearDown(() {
      replies.close();
      for (final isolate in isolates) {
        isolate.kill(priority: Isolate.immediate);
      }
    });
    for (final input in [
      args(width: 1001, height: 667),
      args(width: 256, height: 384),
    ]) {
      isolates.add(
        await Isolate.spawn(_overlappingPhoto, (
          input.toJson(),
          replies.sendPort,
        )),
      );
    }
    await for (final message in replies.timeout(const Duration(seconds: 30))) {
      if (message is SendPort) {
        ready.add(message);
        if (ready.length == 2) {
          for (final port in ready) {
            port.send(null);
          }
        }
      } else {
        expect(message, isA<Map<String, Object?>>());
        results.add(Map<String, Object?>.from(message as Map));
        if (results.length == 2) break;
      }
    }
    expect(results[0]['sourcePath'], isNot(results[1]['sourcePath']));
    for (final result in results) {
      await _verifyResult(result);
    }
    final manifest = File('${directory.path}/test-batch/photo-0/manifest.json');
    final committed = Map<String, Object?>.from(
      jsonDecode(await manifest.readAsString()) as Map,
    );
    expect(results, contains(equals(committed)));
    final cached = await processPhoto(
      args(
        width: committed['width']! as int,
        height: committed['height']! as int,
      ),
    );
    expect(cached, {...committed, 'reused': true});
    // A later rebuild must not remove or mutate either returned generation.
    await processPhoto(args());
    for (final result in results) {
      await _verifyResult(result);
    }
  });

  test('rejects missing or corrupt dimensions and required metrics', () async {
    var valid = await processPhoto(args());
    final manifest = File('${directory.path}/test-batch/photo-0/manifest.json');
    for (final key in [
      'previewWidth',
      'previewHeight',
      'thumbnailWidth',
      'thumbnailHeight',
      'elapsedMs',
      'sourceBytes',
      'outputBytes',
      'sha256',
      'checksums',
      'reused',
    ]) {
      for (final value in [
        null,
        -1,
        'invalid',
        if (key.endsWith('Width') || key.endsWith('Height')) ...[1, 96.0],
      ]) {
        final corrupt = {...valid};
        if (value == null) {
          corrupt.remove(key);
        } else {
          corrupt[key] = value;
        }
        await manifest.writeAsString(jsonEncode(corrupt));
        final rebuilt = await processPhoto(args());
        expect(rebuilt['reused'], false, reason: '$key = $value');
        expect(rebuilt['sha256'], valid['sha256']);
        valid = rebuilt;
      }
    }
  });

  test(
    'reuses legacy manifests and preserves their artifacts on rebuild',
    () async {
      final first = await processPhoto(args());
      final photo = Directory('${directory.path}/test-batch/photo-0');
      final legacy = {...first, 'version': 1}..remove('generation');
      for (final (key, name) in [
        ('sourcePath', 'original.jpg'),
        ('previewPath', 'preview.jpg'),
        ('thumbnailPath', 'thumbnail.jpg'),
      ]) {
        final path = '${photo.path}/$name';
        await File(first[key]! as String).copy(path);
        legacy[key] = path;
      }
      await File(
        '${photo.path}/manifest.json',
      ).writeAsString(jsonEncode(legacy));
      expect(await processPhoto(args()), {...legacy, 'reused': true});
      await processPhoto(args(width: 384, height: 256));
      await _verifyResult(legacy);
    },
  );

  test(
    'failed publication cleans owned temporaries, not completed generations',
    () async {
      final first = await processPhoto(args());
      final photo = Directory('${directory.path}/test-batch/photo-0');
      final manifest = File('${photo.path}/manifest.json');
      await manifest.delete();
      await Directory(manifest.path).create();
      await expectLater(
        processPhoto(args()),
        throwsA(isA<FileSystemException>()),
      );
      final names = await photo.list().map((entity) => entity.path).toList();
      expect(
        names,
        unorderedEquals([
          File(first['sourcePath']! as String).parent.path,
          manifest.path,
        ]),
      );
      await _verifyResult(first);
      await Directory(manifest.path).delete();
      await expectLater(
        processPhoto(
          args(),
          onProgress: (percent, _) async {
            if (percent == 100) throw StateError('notification failed');
          },
        ),
        throwsStateError,
      );
      expect((await processPhoto(args()))['reused'], true);
    },
  );

  test('rejects generation traversal and symbolic links', () async {
    final first = await processPhoto(args());
    final photo = Directory('${directory.path}/test-batch/photo-0');
    final manifest = File('${photo.path}/manifest.json');
    for (final generation in ['../escape', '/absolute', r'..\escape']) {
      await manifest.writeAsString(
        jsonEncode({...first, 'generation': generation}),
      );
      expect((await processPhoto(args()))['reused'], false);
    }
    final originalDirectory = File(first['sourcePath']! as String).parent;
    final linkedDirectory = '${photo.path}/generation-linked';
    await Link(linkedDirectory).create(originalDirectory.path);
    final linked = {...first, 'generation': 'generation-linked'};
    for (final key in ['sourcePath', 'previewPath', 'thumbnailPath']) {
      linked[key] = (first[key]! as String).replaceFirst(
        originalDirectory.path,
        linkedDirectory,
      );
    }
    await manifest.writeAsString(jsonEncode(linked));
    expect((await processPhoto(args()))['reused'], false);
    await _verifyResult(first);
  });

  test(
    'validates payload before enqueue and again inside processing',
    () async {
      for (final invalid in [
        args(batchId: '../outside'),
        args(batchId: ''),
        args(batchId: 'a/b'),
        args(batchId: r'a\b'),
        args(index: -1),
        args(index: 12),
        args(width: 63),
        args(height: 2049),
      ]) {
        expect(() => preparePhoto.encodeArgs(invalid), throwsArgumentError);
        await expectLater(processPhoto(invalid), throwsArgumentError);
      }
      expect(await directory.list().toList(), isEmpty);
      expect(PhotoTaskArgs.fromJson(args().toJson()).toJson(), args().toJson());
    },
  );

  test('reports coarse real processing phases', () async {
    final phases = <double>[];
    await processPhoto(
      args(),
      onProgress: (percent, phase) async {
        phases.add(percent);
        expect(phase, isNotEmpty);
      },
    );
    expect(phases, [0, 10, 35, 60, 85, 100]);
  });
}
