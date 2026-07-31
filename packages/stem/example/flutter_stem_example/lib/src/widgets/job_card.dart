import 'package:flutter/material.dart';
import 'package:stem/stem.dart';
import 'package:stem_flutter/stem_flutter.dart';

import '../utils/time_format.dart';
import 'status_chip.dart';

class JobCard extends StatelessWidget {
  const JobCard({required this.job, super.key});

  final StemFlutterTrackedJob job;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = job.errorMessage ?? job.result;
    final isError = job.errorMessage != null;
    final accent = switch (job.state) {
      TaskState.queued => const Color(0xFF0EA5E9),
      TaskState.running => const Color(0xFFF59E0B),
      TaskState.succeeded => const Color(0xFF22C55E),
      TaskState.failed => const Color(0xFFEF4444),
      TaskState.retried => const Color(0xFFA855F7),
      TaskState.cancelled => const Color(0xFF64748B),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 4,
            height: 72,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        job.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(state: job.state),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'updated ${formatTimestamp(job.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  job.taskId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                if (preview != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isError
                          ? theme.colorScheme.error
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
