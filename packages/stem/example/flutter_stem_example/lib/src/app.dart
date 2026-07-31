import 'package:flutter/material.dart';

import 'queue_monitor_page.dart';

class StemFlutterExampleApp extends StatelessWidget {
  const StemFlutterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stem Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
      ),
      home: const QueueMonitorPage(),
    );
  }
}
