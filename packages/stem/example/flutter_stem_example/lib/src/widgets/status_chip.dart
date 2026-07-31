import 'package:flutter/material.dart';
import 'package:stem/stem.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({required this.state, super.key});

  final TaskState state;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = switch (state) {
      TaskState.queued => (
        const Color(0xFFE0F2FE),
        const Color(0xFF075985),
        'queued',
      ),
      TaskState.running => (
        const Color(0xFFFEF3C7),
        const Color(0xFF92400E),
        'running',
      ),
      TaskState.succeeded => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
        'succeeded',
      ),
      TaskState.failed => (
        const Color(0xFFFEE2E2),
        const Color(0xFF991B1B),
        'failed',
      ),
      TaskState.retried => (
        const Color(0xFFF3E8FF),
        const Color(0xFF6B21A8),
        'retried',
      ),
      TaskState.cancelled => (
        const Color(0xFFE5E7EB),
        const Color(0xFF374151),
        'cancelled',
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
