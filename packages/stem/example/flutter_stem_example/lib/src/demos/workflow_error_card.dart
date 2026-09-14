import 'package:flutter/material.dart';

/// Friendly rendering of a failed workflow run.
///
/// Shows the one-line outcome up front and tucks the full framework error
/// (run id, checkpoint, stack) behind an expander, so a demo screen stays
/// readable when a step throws.
class WorkflowErrorCard extends StatelessWidget {
  const WorkflowErrorCard({
    super.key,
    required this.title,
    required this.error,
  });

  final String title;
  final Object error;

  /// First line of the failure, without the stack trace wall.
  static String shortMessage(Object error) {
    final text = '$error'.trim();
    final firstLine = text.split('\n').first.trim();
    const budget = 220;
    if (firstLine.length <= budget) return firstLine;
    return '${firstLine.substring(0, budget)}…';
  }

  @override
  Widget build(BuildContext context) {
    final full = '$error'.trim();
    final short = shortMessage(error);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SelectableText(short),
            if (full != short)
              ExpansionTile(
                title: const Text('Technical details'),
                tilePadding: EdgeInsets.zero,
                children: [SelectableText(full)],
              ),
          ],
        ),
      ),
    );
  }
}
