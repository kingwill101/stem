import 'dart:convert';
import 'dart:io';

import 'package:stem/stem.dart';

class FileScheduleRepository {
  FileScheduleRepository({String? path}) : _file = File(path ?? _defaultPath);

  final File _file;

  Future<List<ScheduleEntry>> load() async {
    if (!await _file.exists()) {
      return [];
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      return [];
    }
    final data = jsonDecode(raw) as List<dynamic>;
    return data
        .map((e) => ScheduleEntry.fromJson((e as Map).cast<String, Object?>()))
        .toList();
  }

  Future<void> save(List<ScheduleEntry> entries) async {
    await _file.parent.create(recursive: true);
    final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
    await _file.writeAsString(payload);
  }

  static String get _defaultPath =>
      Platform.environment['STEM_SCHEDULE_FILE'] ??
      '${Directory.current.path}/.stem/schedules.json';
}
