import 'package:flutter/material.dart';

import 'src/greeting_page.dart';

/// Standalone entrypoint for the minimal demo:
/// `flutter run -t lib/greeting_main.dart`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: GreetingPage()));
}
