import '../core/contracts.dart';
import 'schedule_calculator.dart';

/// Simple in-memory schedule store implementation used in tests.
class InMemoryScheduleStore implements ScheduleStore {
  InMemoryScheduleStore({ScheduleCalculator? calculator})
    : _calculator = calculator ?? ScheduleCalculator();

  final ScheduleCalculator _calculator;
  final Map<String, _ScheduleState> _entries = {};

  @override
  Future<List<ScheduleEntry>> due(DateTime now, {int limit = 100}) async {
    final due =
        _entries.values
            .where(
              (state) =>
                  !state.locked &&
                  state.entry.enabled &&
                  !state.nextRun.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.nextRun.compareTo(b.nextRun));

    final selected = <ScheduleEntry>[];
    for (final state in due.take(limit)) {
      state.locked = true;
      selected.add(state.entry);
    }
    return selected;
  }

  @override
  Future<void> upsert(ScheduleEntry entry) async {
    final now = DateTime.now();
    final next = _calculator.nextRun(
      entry,
      entry.lastRunAt ?? now,
      includeJitter: false,
    );
    _entries[entry.id] = _ScheduleState(entry.copyWith(), next, locked: false);
  }

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
  }

  ScheduleEntry? get(String id) => _entries[id]?.entry;
}

class _ScheduleState {
  _ScheduleState(this.entry, this.nextRun, {required this.locked});

  ScheduleEntry entry;
  DateTime nextRun;
  bool locked;
}
