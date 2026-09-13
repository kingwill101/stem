import 'package:ormed/ormed.dart';

part 'stem_workflow_journal.orm.dart';

/// Database model for versioned workflow journal records.
@OrmModel(
  table: 'stem_workflow_journal',
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

  /// Resource namespace.
  @OrmField(columnName: 'namespace')
  final String namespace;

  /// Workflow run identifier.
  @OrmField(columnName: 'run_id')
  final String runId;

  /// Journal kind.
  @OrmField(columnName: 'kind')
  final String kind;

  /// Exact checkpoint name.
  @OrmField(columnName: 'name')
  final String name;

  /// Compare-and-set revision.
  @OrmField(columnName: 'revision')
  final int revision;

  /// Successful completion position, only meaningful for compensations.
  @OrmField(columnName: 'position')
  final int? position;

  /// Serialized protocol data.
  @OrmField(columnName: 'data')
  final String data;
}
