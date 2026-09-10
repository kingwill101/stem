import 'package:flutter/material.dart';

class WorkerStateChip extends StatelessWidget {
  const WorkerStateChip({required this.running, super.key});

  final bool running;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, label) = switch (running) {
      true => (const Color(0xFFDCFCE7), const Color(0xFF166534), 'running'),
      false => (const Color(0xFFE5E7EB), const Color(0xFF374151), 'stopped'),
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
