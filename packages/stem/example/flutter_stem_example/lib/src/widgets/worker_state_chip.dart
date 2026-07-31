import 'package:flutter/material.dart';
import 'package:stem_flutter/stem_flutter.dart';

class WorkerStateChip extends StatelessWidget {
  const WorkerStateChip({required this.state, super.key});

  final StemFlutterWorkerStatus state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = switch (state) {
      StemFlutterWorkerStatus.running => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
        'running',
      ),
      StemFlutterWorkerStatus.waiting => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
        'waiting',
      ),
      StemFlutterWorkerStatus.starting => (
        const Color(0xFFE0F2FE),
        const Color(0xFF075985),
        'starting',
      ),
      StemFlutterWorkerStatus.error => (
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
        'error',
      ),
      StemFlutterWorkerStatus.stopped => (
        const Color(0xFFE5E7EB),
        const Color(0xFF374151),
        'stopped',
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
