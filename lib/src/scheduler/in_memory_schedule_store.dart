import '../core/contracts.dart';
import 'schedule_calculator.dart';
import 'schedule_spec.dart';

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
                  (state.entry.expireAt == null ||
                      state.entry.expireAt!.isAfter(now)) &&
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
    final now = DateTime.now().toUtc();
    DateTime? next = entry.nextRunAt;
    if (entry.enabled) {
      next ??= _calculator.nextRun(
        entry,
        entry.lastRunAt ?? now,
        includeJitter: false,
      );
    } else {
      next ??= entry.lastRunAt ?? now;
    }
    final existing = _entries[entry.id];
    final currentVersion = existing?.entry.version ?? 0;
    if (existing != null && entry.version != currentVersion) {
      throw ScheduleConflictException(
        entry.id,
        expectedVersion: entry.version,
        actualVersion: currentVersion,
      );
    }
    final nextVersion = existing == null ? 1 : currentVersion + 1;
    final updated = entry.copyWith(nextRunAt: next, version: nextVersion);
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
    required DateTime scheduledFor,
    required DateTime executedAt,
    Duration? jitter,
    String? lastError,
    bool success = true,
    Duration? runDuration,
    DateTime? nextRunAt,
    Duration? drift,
  }) async {
    final state = _entries[id];
    if (state == null) return;
    final resolvedSuccess = success && lastError == null;
    final updatedEntry = state.entry.copyWith(
      lastRunAt: executedAt,
      lastError: lastError,
      lastJitter: jitter,
      lastSuccessAt: resolvedSuccess ? executedAt : state.entry.lastSuccessAt,
      lastErrorAt: resolvedSuccess ? state.entry.lastErrorAt : executedAt,
      totalRunCount: state.entry.totalRunCount + 1,
      drift: drift ?? state.entry.drift,
    );
    DateTime? next = nextRunAt;
    var enabled = updatedEntry.enabled;
    if (next == null && enabled) {
      try {
        next = _calculator.nextRun(
          updatedEntry,
          executedAt,
          includeJitter: false,
        );
      } catch (_) {
        next = executedAt;
      }
    }
    if (updatedEntry.expireAt != null &&
        !executedAt.isBefore(updatedEntry.expireAt!)) {
      enabled = false;
    }
    if (updatedEntry.spec is ClockedScheduleSpec) {
      final spec = updatedEntry.spec as ClockedScheduleSpec;
      if (spec.runOnce && !executedAt.isBefore(spec.runAt)) {
        enabled = false;
      }
    }
    next ??= executedAt;
    final nextVersion = state.entry.version + 1;
    state.entry = updatedEntry.copyWith(
      nextRunAt: next,
      enabled: enabled,
      version: nextVersion,
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
