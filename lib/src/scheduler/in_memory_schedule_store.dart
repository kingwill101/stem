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
    final due = _entries.values
        .where(
          (state) =>
              !state.locked &&
              state.entry.enabled &&
              !(state.entry.nextRunAt ?? state.nextRun).isAfter(now),
        )
        .toList()
      ..sort((a, b) => a.nextRun.compareTo(b.nextRun));

    final selected = <ScheduleEntry>[];
    for (final state in due.take(limit)) {
      state.locked = true;
      state.entry = state.entry.copyWith(nextRunAt: state.nextRun);
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
    final updated = entry.copyWith(nextRunAt: next);
    _entries[entry.id] = _ScheduleState(updated, next, locked: false);
  }

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
  }

  @override
  Future<List<ScheduleEntry>> list({int? limit}) async {
    final values = _entries.values.toList()
      ..sort((a, b) => a.nextRun.compareTo(b.nextRun));
    final subset = limit != null ? values.take(limit).toList() : values;
    return subset.map((state) => state.entry).toList();
  }

  @override
  Future<ScheduleEntry?> get(String id) async => _entries[id]?.entry;

  @override
  Future<void> markExecuted(
    String id, {
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
  }) async {
    final state = _entries[id];
    if (state == null) return;
    final next = _calculator.nextRun(
      state.entry.copyWith(lastRunAt: executedAt),
      executedAt,
      includeJitter: false,
    );
    state.entry = state.entry.copyWith(
      lastRunAt: executedAt,
      lastError: lastError,
      lastJitter: jitter,
      nextRunAt: next,
    );
    state.nextRun = next;
    state.locked = false;
  }
}

class _ScheduleState {
  _ScheduleState(this.entry, this.nextRun, {required this.locked});

  ScheduleEntry entry;
  DateTime nextRun;
  bool locked;
}
