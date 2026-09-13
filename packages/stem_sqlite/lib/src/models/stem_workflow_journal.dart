import 'package:ormed/ormed.dart';

part 'stem_workflow_journal.orm.dart';

/// Database model for versioned workflow journal records.
@OrmModel(
  table: 'wf_journal',
  primaryKey: ['namespace', 'runId', 'kind', 'name'],
)
class StemWorkflowJournal extends Model<StemWorkflowJournal> {
  /// Creates a journal record.
  StemWorkflowJournal({
    required this.namespace,
    required this.runId,
    required this.kind,
    required this.name,
    required this.revision,
    required this.data,
    this.position,
  });

  /// Namespace that owns the journal record.
  final String namespace;

  /// Workflow run identifier.
  @OrmField(columnName: 'run_id')
  final String runId;

  /// Journal namespace (`step` or `compensation`).
  final String kind;

  /// Exact checkpoint name.
  final String name;

  /// Current optimistic-concurrency revision.
  final int revision;

  /// JSON-encoded protocol data.
  final String data;

  /// Completion order for compensation records.
  final int? position;
}
