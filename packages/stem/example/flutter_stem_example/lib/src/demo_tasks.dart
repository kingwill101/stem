import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:image/image.dart' as img;
import 'package:stem/stem.dart';

import 'demo_config.dart';

// Opt-in diagnostics only: RSS is process-wide (including every Flutter engine
// and task isolate), and maxRss is the lifetime high-water mark, not this photo's
// private heap or a hard limit. Do not put these samples in cached task results.
const _memoryDiagnostics = bool.fromEnvironment('STEM_DEMO_MEMORY_DIAGNOSTICS');

void _sampleMemory(PhotoTaskArgs args, String stage) {
  if (!_memoryDiagnostics) return;
  // Flutter forwards print from task isolates to logcat; raw stdout does not.
  // ignore: avoid_print
  print(
    jsonEncode({
      'event': 'stem.photo.memory',
      'pid': pid,
      'batchId': args.batchId,
      'index': args.index,
      'width': args.width,
      'height': args.height,
      'stage': stage,
      'rssBytes': ProcessInfo.currentRss,
      'processMaxRssBytes': ProcessInfo.maxRss,
      'at': DateTime.now().toUtc().toIso8601String(),
    }),
  );
}

/// Only scalar values cross the task-isolate boundary; no plugins are needed.
class PhotoTaskArgs {
  const PhotoTaskArgs({
    required this.outputDirectory,
    required this.batchId,
    required this.index,
    required this.width,
    required this.height,
  });

  final String outputDirectory;
  final String batchId;
  final int index;
  final int width;
  final int height;

  Map<String, Object?> toJson() => {
    'outputDirectory': outputDirectory,
    'batchId': batchId,
    'index': index,
    'width': width,
    'height': height,
  };

  factory PhotoTaskArgs.fromJson(Map<String, Object?> json) => PhotoTaskArgs(
    outputDirectory: json['outputDirectory'] as String,
    batchId: json['batchId'] as String,
    index: json['index'] as int,
    width: json['width'] as int,
    height: json['height'] as int,
  );

  void validate() {
    if (outputDirectory.trim().isEmpty ||
        outputDirectory.contains('\u0000') ||
        !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$').hasMatch(batchId) ||
        index < 0 ||
        index > 11 ||
        width < 64 ||
        width > 2048 ||
        height < 64 ||
        height > 2048) {
      throw ArgumentError(
        'Invalid photo directory, batch, index or dimensions',
      );
    }
  }
}

final preparePhoto = TaskDefinition<PhotoTaskArgs, Map<String, Object?>>(
  name: taskName,
  encodeArgs: (args) {
    args.validate();
    return args.toJson();
  },
  decodeResult: (value) => Map<String, Object?>.from(value! as Map),
  defaultOptions: const TaskOptions(
    queue: queueName,
    maxRetries: 3,
    // Verified artifact commits make replay safe; interruptions still spend
    // the normal retry budget instead of silently repeating forever.
    recoveryPolicy: TaskRecoveryPolicy.retry,
  ),
  metadata: const TaskMetadata(
    description: 'Prepare an offline photo album with previews and checksums.',
    idempotent: true,
    tags: <String>['flutter', 'photo', 'cpu', 'offline'],
  ),
);

final demoModule = StemModule(
  tasks: <TaskHandler<Object?>>[
    FunctionTaskHandler<Map<String, Object?>>(
      name: preparePhoto.name,
      entrypoint: _preparePhotoTask,
      options: preparePhoto.defaultOptions,
      metadata: preparePhoto.metadata,
    ),
  ],
);

Future<Object?> _preparePhotoTask(
  TaskInvocationContext context,
  Map<String, Object?> args,
) => processPhoto(
  PhotoTaskArgs.fromJson(args),
  onProgress: (percent, phase) =>
      context.progress(percent, data: {'phase': phase}),
);

/// CPU-bound image work shared by the isolate entrypoint and focused tests.
///
/// A manifest is the commit marker. Missing/corrupt artifacts and changed
/// dimensions cause a deterministic rebuild, never a partial cache hit.
Future<Map<String, Object?>> processPhoto(
  PhotoTaskArgs args, {
  Future<void> Function(double percent, String phase)? onProgress,
}) async {
  args.validate();
  final watch = Stopwatch()..start();
  Future<void> progress(double value, String phase) async {
    await onProgress?.call(value, phase);
  }

  final root = Directory(args.outputDirectory).absolute;
  final batch = Directory('${root.path}/${args.batchId}');
  final directory = Directory('${batch.path}/photo-${args.index}');
  // The caller selects the application-owned root. Child symlinks must not
  // redirect a retry's writes outside that root.
  for (final child in [batch, directory]) {
    if (await FileSystemEntity.type(child.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw ArgumentError('Photo output directories cannot be symbolic links');
    }
    await child.create(recursive: true);
  }
  final paths = <String, String>{
    'sourcePath': '${directory.path}/original.jpg',
    'previewPath': '${directory.path}/preview.jpg',
    'thumbnailPath': '${directory.path}/thumbnail.jpg',
  };
  final manifest = File('${directory.path}/manifest.json');
  await progress(0, 'Checking saved artifacts');
  _sampleMemory(args, 'before-cache-check');
  final cached = await _readVerifiedManifest(manifest, args, paths);
  if (cached != null) {
    _sampleMemory(args, 'reused-artifacts');
    await progress(100, 'Reused verified photo');
    return {...cached, 'reused': true};
  }

  // Remove the previous commit marker before replacing any artifact.
  if (await manifest.exists()) await manifest.delete();
  await progress(10, 'Generating original');
  _sampleMemory(args, 'before-source');
  final source = img.encodeJpg(_landscape(args), quality: 92);
  _sampleMemory(args, 'source-encoded');
  await progress(35, 'Decoding and enhancing');
  final decoded = img.decodeJpg(source)!;
  _sampleMemory(args, 'source-decoded');
  img.adjustColor(decoded, contrast: 1.08, saturation: 1.15, brightness: 1.03);
  _sampleMemory(args, 'source-enhanced');
  await progress(60, 'Resizing previews');
  final previewImage = _fit(decoded, 960);
  final preview = img.encodeJpg(previewImage, quality: 86);
  _sampleMemory(args, 'preview-encoded');
  final thumbnailImage = _fit(previewImage, 256);
  final thumbnail = img.encodeJpg(thumbnailImage, quality: 80);
  _sampleMemory(args, 'thumbnail-encoded');
  await progress(85, 'Saving album artifacts');
  final artifacts = {
    'sourcePath': source,
    'previewPath': preview,
    'thumbnailPath': thumbnail,
  };
  final checksums = <String, String>{};
  for (final entry in artifacts.entries) {
    checksums[entry.key] = crypto.sha256.convert(entry.value).toString();
    await _atomicWrite(File(paths[entry.key]!), entry.value);
  }
  final result = <String, Object?>{
    'version': 1,
    'batchId': args.batchId,
    'index': args.index,
    ...paths,
    'width': args.width,
    'height': args.height,
    'previewWidth': previewImage.width,
    'previewHeight': previewImage.height,
    'thumbnailWidth': thumbnailImage.width,
    'thumbnailHeight': thumbnailImage.height,
    'sourceBytes': source.length,
    'outputBytes': preview.length + thumbnail.length,
    'elapsedMs': watch.elapsedMilliseconds,
    'sha256': checksums['previewPath'],
    'checksums': checksums,
    'reused': false,
  };
  await _atomicWrite(manifest, utf8.encode(jsonEncode(result)));
  _sampleMemory(args, 'artifacts-committed');
  await progress(100, 'Photo ready');
  return result;
}

Future<Map<String, Object?>?> _readVerifiedManifest(
  File manifest,
  PhotoTaskArgs args,
  Map<String, String> paths,
) async {
  try {
    if (!await manifest.exists() || await manifest.length() > 16384) {
      return null;
    }
    final data = Map<String, Object?>.from(
      jsonDecode(await manifest.readAsString()) as Map,
    );
    if (data['version'] != 1 ||
        data['batchId'] != args.batchId ||
        data['index'] != args.index ||
        data['width'] != args.width ||
        data['height'] != args.height ||
        data['elapsedMs'] is! int ||
        data['sourceBytes'] is! int ||
        data['outputBytes'] is! int) {
      return null;
    }
    final hashes = data['checksums'] as Map;
    var outputBytes = 0;
    for (final entry in paths.entries) {
      if (data[entry.key] != entry.value) return null;
      if (await FileSystemEntity.type(entry.value, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      final file = File(entry.value);
      // Bound reads even if an artifact was replaced with unrelated data.
      final length = await file.length();
      if (length > 32 * 1024 * 1024) return null;
      final digest = await crypto.sha256.bind(file.openRead()).first;
      if (digest.toString() != hashes[entry.key]) return null;
      if (entry.key == 'sourcePath') {
        if (length != data['sourceBytes']) return null;
      } else {
        outputBytes += length;
      }
    }
    if (outputBytes != data['outputBytes'] ||
        data['sha256'] != hashes['previewPath']) {
      return null;
    }
    return data;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

Future<void> _atomicWrite(File target, List<int> bytes) async {
  // Unique sibling temporaries also isolate overlapping duplicate attempts.
  final temporary = await Directory(target.parent.path).createTemp('.photo-');
  try {
    final file = File('${temporary.path}/pending');
    await file.writeAsBytes(bytes, flush: true);
    await file.rename(target.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

img.Image _fit(img.Image source, int longestSide) {
  final scale = math.min(
    1.0,
    longestSide / math.max(source.width, source.height),
  );
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
}

/// A reproducible travel-poster landscape: luminous sky, sun, layered ridges
/// and water. Every pixel contributes to an actual saved image, not busywork.
img.Image _landscape(PhotoTaskArgs args) {
  final image = img.Image(width: args.width, height: args.height);
  final phase = args.index * 0.67;
  final palettes = [
    [(30, 58, 103), (249, 177, 126), (29, 73, 91)],
    [(47, 42, 95), (241, 155, 164), (46, 63, 92)],
    [(22, 84, 102), (247, 204, 142), (23, 88, 83)],
  ];
  final palette = palettes[args.index % palettes.length];
  final sunX = 0.25 + (args.index % 4) * 0.16;
  for (var y = 0; y < args.height; y++) {
    final v = y / args.height;
    for (var x = 0; x < args.width; x++) {
      final u = x / args.width;
      final sky = (v / 0.72).clamp(0.0, 1.0);
      var r = palette[0].$1 * (1 - sky) + palette[1].$1 * sky;
      var g = palette[0].$2 * (1 - sky) + palette[1].$2 * sky;
      var b = palette[0].$3 * (1 - sky) + palette[1].$3 * sky;
      final dx = (u - sunX) * args.width / args.height;
      final dy = v - 0.29;
      if (dx * dx + dy * dy < 0.0064) {
        r = 255;
        g = 231;
        b = 181;
      }
      for (var layer = 0; layer < 3; layer++) {
        final ridge =
            0.46 +
            layer * 0.115 +
            0.075 * math.sin(u * 9 + phase + layer * 1.9) +
            0.035 * math.sin(u * 23 - phase + layer);
        if (v > ridge) {
          final haze = (2 - layer) * 25.0;
          r = palette[2].$1 + haze;
          g = palette[2].$2 + haze;
          b = palette[2].$3 + haze;
        }
      }
      if (v > 0.79) {
        final ripple = math.sin(v * 240 + u * 18 + phase) * 5;
        final reflection = math.max(0.0, 1 - (u - sunX).abs() * 8) * 32;
        r = palette[2].$1 + reflection + ripple;
        g = palette[2].$2 + 13 + reflection + ripple;
        b = palette[2].$3 + 20 + ripple;
      }
      // Fine deterministic grain gives the JPEG encoder real texture.
      final grain = ((x * 37 + y * 17 + x * y + args.index * 13) % 11) - 5;
      image.setPixelRgb(
        x,
        y,
        (r + grain).clamp(0, 255),
        (g + grain).clamp(0, 255),
        (b + grain).clamp(0, 255),
      );
    }
  }
  return image;
}
