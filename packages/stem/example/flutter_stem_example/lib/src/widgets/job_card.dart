import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

import 'status_chip.dart';

String formatPhotoBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Missing artifacts (or results written by an older demo) are harmless.
class PhotoArtifact extends StatelessWidget {
  const PhotoArtifact({super.key, required this.path, this.height = 72});
  final Object? path;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fallback = SizedBox(
      height: height,
      child: const Center(child: Icon(Icons.image_not_supported_outlined)),
    );
    if (path is! String || (path! as String).isEmpty) return fallback;
    return Image.file(
      File(path! as String),
      height: height,
      fit: BoxFit.contain,
      cacheWidth: height <= 72 ? 144 : 960,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard({required this.job, super.key});
  final TaskStatusRecord job;

  @override
  Widget build(BuildContext context) {
    final status = job.status;
    final payload = status.payload;
    final result = payload is Map ? payload : const <String, Object?>{};
    final width = result['width'];
    final height = result['height'];
    final elapsed = result['elapsedMs'];
    final details = [
      if (width is int && width > 0 && height is int && height > 0)
        '$width × $height',
      if (elapsed is num && elapsed.isFinite && elapsed >= 0) '$elapsed ms',
    ].join(' · ');
    final index = status.meta['index'];
    final title =
        '${status.meta['label'] ?? 'Photo'}'
        '${index is num ? ' · ${index.toInt() + 1}' : ''}';
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PhotoArtifact(path: result['previewPath'], height: 240),
                    const SizedBox(height: 12),
                    if (result.isEmpty)
                      const Text(
                        'No photo artifacts available. This may be '
                        'an unfinished task or a result from an older demo.',
                      ),
                    SelectableText(
                      'Task: ${status.id}\n'
                      'State: ${status.state.name}\n'
                      '${status.error?.message ?? ''}',
                    ),
                    for (final entry in result.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText('${entry.key}: ${entry.value}'),
                      ),
                    if (payload is String) SelectableText(payload),
                    const SizedBox(height: 12),
                    const Text(
                      'Artifacts stay in app-owned storage. If a file '
                      'is unavailable, its persisted details remain here.',
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: PhotoArtifact(path: result['thumbnailPath']),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    StatusChip(state: status.state),
                    const SizedBox(height: 6),
                    if (details.isNotEmpty) Text(details),
                    if (status.error != null)
                      Text(
                        status.error!.message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const Text('Tap for preview & artifact details'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
