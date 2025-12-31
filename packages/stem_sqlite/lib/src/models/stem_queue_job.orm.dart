// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_queue_job.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemQueueJobIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobQueueField = FieldDefinition(
  name: 'queue',
  columnName: 'queue',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobEnvelopeField = FieldDefinition(
  name: 'envelope',
  columnName: 'envelope',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
  codecType: 'json',
);

const FieldDefinition _$StemQueueJobAttemptField = FieldDefinition(
  name: 'attempt',
  columnName: 'attempt',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobMaxRetriesField = FieldDefinition(
  name: 'maxRetries',
  columnName: 'max_retries',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobPriorityField = FieldDefinition(
  name: 'priority',
  columnName: 'priority',
  dartType: 'int',
  resolvedType: 'int',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobNotBeforeField = FieldDefinition(
  name: 'notBefore',
  columnName: 'not_before',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobLockedAtField = FieldDefinition(
  name: 'lockedAt',
  columnName: 'locked_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobLockedUntilField = FieldDefinition(
  name: 'lockedUntil',
  columnName: 'locked_until',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobLockedByField = FieldDefinition(
  name: 'lockedBy',
  columnName: 'locked_by',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemQueueJobUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemQueueJobUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemQueueJob;
  return <String, Object?>{
    'id': registry.encodeField(_$StemQueueJobIdField, m.id),
    'queue': registry.encodeField(_$StemQueueJobQueueField, m.queue),
    'envelope': registry.encodeField(_$StemQueueJobEnvelopeField, m.envelope),
    'attempt': registry.encodeField(_$StemQueueJobAttemptField, m.attempt),
    'max_retries': registry.encodeField(
      _$StemQueueJobMaxRetriesField,
      m.maxRetries,
    ),
    'priority': registry.encodeField(_$StemQueueJobPriorityField, m.priority),
    'not_before': registry.encodeField(
      _$StemQueueJobNotBeforeField,
      m.notBefore,
    ),
    'locked_at': registry.encodeField(_$StemQueueJobLockedAtField, m.lockedAt),
    'locked_until': registry.encodeField(
      _$StemQueueJobLockedUntilField,
      m.lockedUntil,
    ),
    'locked_by': registry.encodeField(_$StemQueueJobLockedByField, m.lockedBy),
  };
}

final ModelDefinition<$StemQueueJob> _$StemQueueJobDefinition = ModelDefinition(
  modelName: 'StemQueueJob',
  tableName: 'stem_queue_jobs',
  fields: const [
    _$StemQueueJobIdField,
    _$StemQueueJobQueueField,
    _$StemQueueJobEnvelopeField,
    _$StemQueueJobAttemptField,
    _$StemQueueJobMaxRetriesField,
    _$StemQueueJobPriorityField,
    _$StemQueueJobNotBeforeField,
    _$StemQueueJobLockedAtField,
    _$StemQueueJobLockedUntilField,
    _$StemQueueJobLockedByField,
    _$StemQueueJobCreatedAtField,
    _$StemQueueJobUpdatedAtField,
  ],
  relations: const [],
  softDeleteColumn: 'deleted_at',
  metadata: ModelAttributesMetadata(
    hidden: const <String>[],
    visible: const <String>[],
    fillable: const <String>[],
    guarded: const <String>[],
    casts: const <String, String>{},
    appends: const <String>[],
    touches: const <String>[],
    timestamps: true,
    fieldOverrides: const {'envelope': FieldAttributeMetadata(cast: 'json')},
    softDeletes: false,
    softDeleteColumn: 'deleted_at',
  ),
  untrackedToMap: _encodeStemQueueJobUntracked,
  codec: _$StemQueueJobCodec(),
);

extension StemQueueJobOrmDefinition on StemQueueJob {
  static ModelDefinition<$StemQueueJob> get definition =>
      _$StemQueueJobDefinition;
}

class StemQueueJobs {
  const StemQueueJobs._();

  /// Starts building a query for [$StemQueueJob].
  ///
  /// {@macro ormed.query}
  static Query<$StemQueueJob> query([String? connection]) =>
      Model.query<$StemQueueJob>(connection: connection);

  static Future<$StemQueueJob?> find(Object id, {String? connection}) =>
      Model.find<$StemQueueJob>(id, connection: connection);

  static Future<$StemQueueJob> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemQueueJob>(id, connection: connection);

  static Future<List<$StemQueueJob>> all({String? connection}) =>
      Model.all<$StemQueueJob>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemQueueJob>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemQueueJob>(connection: connection);

  static Query<$StemQueueJob> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemQueueJob>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemQueueJob> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemQueueJob>(column, values, connection: connection);

  static Query<$StemQueueJob> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemQueueJob>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemQueueJob> limit(int count, {String? connection}) =>
      Model.limit<$StemQueueJob>(count, connection: connection);

  /// Creates a [Repository] for [$StemQueueJob].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemQueueJob> repo([String? connection]) =>
      Model.repository<$StemQueueJob>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemQueueJob fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemQueueJobDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemQueueJob model, {
    ValueCodecRegistry? registry,
  }) => _$StemQueueJobDefinition.toMap(model, registry: registry);
}

class StemQueueJobModelFactory {
  const StemQueueJobModelFactory._();

  static ModelDefinition<$StemQueueJob> get definition =>
      _$StemQueueJobDefinition;

  static ModelCodec<$StemQueueJob> get codec => definition.codec;

  static StemQueueJob fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemQueueJob model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemQueueJob> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemQueueJob>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemQueueJob> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemQueueJob>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemQueueJobCodec extends ModelCodec<$StemQueueJob> {
  const _$StemQueueJobCodec();
  @override
  Map<String, Object?> encode(
    $StemQueueJob model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemQueueJobIdField, model.id),
      'queue': registry.encodeField(_$StemQueueJobQueueField, model.queue),
      'envelope': registry.encodeField(
        _$StemQueueJobEnvelopeField,
        model.envelope,
      ),
      'attempt': registry.encodeField(
        _$StemQueueJobAttemptField,
        model.attempt,
      ),
      'max_retries': registry.encodeField(
        _$StemQueueJobMaxRetriesField,
        model.maxRetries,
      ),
      'priority': registry.encodeField(
        _$StemQueueJobPriorityField,
        model.priority,
      ),
      'not_before': registry.encodeField(
        _$StemQueueJobNotBeforeField,
        model.notBefore,
      ),
      'locked_at': registry.encodeField(
        _$StemQueueJobLockedAtField,
        model.lockedAt,
      ),
      'locked_until': registry.encodeField(
        _$StemQueueJobLockedUntilField,
        model.lockedUntil,
      ),
      'locked_by': registry.encodeField(
        _$StemQueueJobLockedByField,
        model.lockedBy,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemQueueJobCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemQueueJobUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemQueueJob decode(Map<String, Object?> data, ValueCodecRegistry registry) {
    final String stemQueueJobIdValue =
        registry.decodeField<String>(_$StemQueueJobIdField, data['id']) ??
        (throw StateError('Field id on StemQueueJob cannot be null.'));
    final String stemQueueJobQueueValue =
        registry.decodeField<String>(_$StemQueueJobQueueField, data['queue']) ??
        (throw StateError('Field queue on StemQueueJob cannot be null.'));
    final Map<String, Object?> stemQueueJobEnvelopeValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemQueueJobEnvelopeField,
          data['envelope'],
        ) ??
        (throw StateError('Field envelope on StemQueueJob cannot be null.'));
    final int stemQueueJobAttemptValue =
        registry.decodeField<int>(
          _$StemQueueJobAttemptField,
          data['attempt'],
        ) ??
        (throw StateError('Field attempt on StemQueueJob cannot be null.'));
    final int stemQueueJobMaxRetriesValue =
        registry.decodeField<int>(
          _$StemQueueJobMaxRetriesField,
          data['max_retries'],
        ) ??
        (throw StateError('Field maxRetries on StemQueueJob cannot be null.'));
    final int stemQueueJobPriorityValue =
        registry.decodeField<int>(
          _$StemQueueJobPriorityField,
          data['priority'],
        ) ??
        (throw StateError('Field priority on StemQueueJob cannot be null.'));
    final DateTime? stemQueueJobNotBeforeValue = registry
        .decodeField<DateTime?>(
          _$StemQueueJobNotBeforeField,
          data['not_before'],
        );
    final DateTime? stemQueueJobLockedAtValue = registry.decodeField<DateTime?>(
      _$StemQueueJobLockedAtField,
      data['locked_at'],
    );
    final DateTime? stemQueueJobLockedUntilValue = registry
        .decodeField<DateTime?>(
          _$StemQueueJobLockedUntilField,
          data['locked_until'],
        );
    final String? stemQueueJobLockedByValue = registry.decodeField<String?>(
      _$StemQueueJobLockedByField,
      data['locked_by'],
    );
    final DateTime? stemQueueJobCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemQueueJobCreatedAtField,
          data['created_at'],
        );
    final DateTime? stemQueueJobUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemQueueJobUpdatedAtField,
          data['updated_at'],
        );
    final model = $StemQueueJob(
      id: stemQueueJobIdValue,
      queue: stemQueueJobQueueValue,
      envelope: stemQueueJobEnvelopeValue,
      attempt: stemQueueJobAttemptValue,
      maxRetries: stemQueueJobMaxRetriesValue,
      priority: stemQueueJobPriorityValue,
      notBefore: stemQueueJobNotBeforeValue,
      lockedAt: stemQueueJobLockedAtValue,
      lockedUntil: stemQueueJobLockedUntilValue,
      lockedBy: stemQueueJobLockedByValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemQueueJobIdValue,
      'queue': stemQueueJobQueueValue,
      'envelope': stemQueueJobEnvelopeValue,
      'attempt': stemQueueJobAttemptValue,
      'max_retries': stemQueueJobMaxRetriesValue,
      'priority': stemQueueJobPriorityValue,
      'not_before': stemQueueJobNotBeforeValue,
      'locked_at': stemQueueJobLockedAtValue,
      'locked_until': stemQueueJobLockedUntilValue,
      'locked_by': stemQueueJobLockedByValue,
      if (data.containsKey('created_at'))
        'created_at': stemQueueJobCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemQueueJobUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemQueueJob].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemQueueJobInsertDto implements InsertDto<$StemQueueJob> {
  const StemQueueJobInsertDto({
    this.id,
    this.queue,
    this.envelope,
    this.attempt,
    this.maxRetries,
    this.priority,
    this.notBefore,
    this.lockedAt,
    this.lockedUntil,
    this.lockedBy,
  });
  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final int? attempt;
  final int? maxRetries;
  final int? priority;
  final DateTime? notBefore;
  final DateTime? lockedAt;
  final DateTime? lockedUntil;
  final String? lockedBy;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (attempt != null) 'attempt': attempt,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (priority != null) 'priority': priority,
      if (notBefore != null) 'not_before': notBefore,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lockedBy != null) 'locked_by': lockedBy,
    };
  }

  static const _StemQueueJobInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemQueueJobInsertDtoCopyWithSentinel();
  StemQueueJobInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? maxRetries = _copyWithSentinel,
    Object? priority = _copyWithSentinel,
    Object? notBefore = _copyWithSentinel,
    Object? lockedAt = _copyWithSentinel,
    Object? lockedUntil = _copyWithSentinel,
    Object? lockedBy = _copyWithSentinel,
  }) {
    return StemQueueJobInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      maxRetries: identical(maxRetries, _copyWithSentinel)
          ? this.maxRetries
          : maxRetries as int?,
      priority: identical(priority, _copyWithSentinel)
          ? this.priority
          : priority as int?,
      notBefore: identical(notBefore, _copyWithSentinel)
          ? this.notBefore
          : notBefore as DateTime?,
      lockedAt: identical(lockedAt, _copyWithSentinel)
          ? this.lockedAt
          : lockedAt as DateTime?,
      lockedUntil: identical(lockedUntil, _copyWithSentinel)
          ? this.lockedUntil
          : lockedUntil as DateTime?,
      lockedBy: identical(lockedBy, _copyWithSentinel)
          ? this.lockedBy
          : lockedBy as String?,
    );
  }
}

class _StemQueueJobInsertDtoCopyWithSentinel {
  const _StemQueueJobInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemQueueJob].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemQueueJobUpdateDto implements UpdateDto<$StemQueueJob> {
  const StemQueueJobUpdateDto({
    this.id,
    this.queue,
    this.envelope,
    this.attempt,
    this.maxRetries,
    this.priority,
    this.notBefore,
    this.lockedAt,
    this.lockedUntil,
    this.lockedBy,
  });
  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final int? attempt;
  final int? maxRetries;
  final int? priority;
  final DateTime? notBefore;
  final DateTime? lockedAt;
  final DateTime? lockedUntil;
  final String? lockedBy;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (attempt != null) 'attempt': attempt,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (priority != null) 'priority': priority,
      if (notBefore != null) 'not_before': notBefore,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lockedBy != null) 'locked_by': lockedBy,
    };
  }

  static const _StemQueueJobUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemQueueJobUpdateDtoCopyWithSentinel();
  StemQueueJobUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? maxRetries = _copyWithSentinel,
    Object? priority = _copyWithSentinel,
    Object? notBefore = _copyWithSentinel,
    Object? lockedAt = _copyWithSentinel,
    Object? lockedUntil = _copyWithSentinel,
    Object? lockedBy = _copyWithSentinel,
  }) {
    return StemQueueJobUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      maxRetries: identical(maxRetries, _copyWithSentinel)
          ? this.maxRetries
          : maxRetries as int?,
      priority: identical(priority, _copyWithSentinel)
          ? this.priority
          : priority as int?,
      notBefore: identical(notBefore, _copyWithSentinel)
          ? this.notBefore
          : notBefore as DateTime?,
      lockedAt: identical(lockedAt, _copyWithSentinel)
          ? this.lockedAt
          : lockedAt as DateTime?,
      lockedUntil: identical(lockedUntil, _copyWithSentinel)
          ? this.lockedUntil
          : lockedUntil as DateTime?,
      lockedBy: identical(lockedBy, _copyWithSentinel)
          ? this.lockedBy
          : lockedBy as String?,
    );
  }
}

class _StemQueueJobUpdateDtoCopyWithSentinel {
  const _StemQueueJobUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemQueueJob].
///
/// All fields are nullable; intended for subset SELECTs.
class StemQueueJobPartial implements PartialEntity<$StemQueueJob> {
  const StemQueueJobPartial({
    this.id,
    this.queue,
    this.envelope,
    this.attempt,
    this.maxRetries,
    this.priority,
    this.notBefore,
    this.lockedAt,
    this.lockedUntil,
    this.lockedBy,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemQueueJobPartial.fromRow(Map<String, Object?> row) {
    return StemQueueJobPartial(
      id: row['id'] as String?,
      queue: row['queue'] as String?,
      envelope: row['envelope'] as Map<String, Object?>?,
      attempt: row['attempt'] as int?,
      maxRetries: row['max_retries'] as int?,
      priority: row['priority'] as int?,
      notBefore: row['not_before'] as DateTime?,
      lockedAt: row['locked_at'] as DateTime?,
      lockedUntil: row['locked_until'] as DateTime?,
      lockedBy: row['locked_by'] as String?,
    );
  }

  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final int? attempt;
  final int? maxRetries;
  final int? priority;
  final DateTime? notBefore;
  final DateTime? lockedAt;
  final DateTime? lockedUntil;
  final String? lockedBy;

  @override
  $StemQueueJob toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? queueValue = queue;
    if (queueValue == null) {
      throw StateError('Missing required field: queue');
    }
    final Map<String, Object?>? envelopeValue = envelope;
    if (envelopeValue == null) {
      throw StateError('Missing required field: envelope');
    }
    final int? attemptValue = attempt;
    if (attemptValue == null) {
      throw StateError('Missing required field: attempt');
    }
    final int? maxRetriesValue = maxRetries;
    if (maxRetriesValue == null) {
      throw StateError('Missing required field: maxRetries');
    }
    final int? priorityValue = priority;
    if (priorityValue == null) {
      throw StateError('Missing required field: priority');
    }
    return $StemQueueJob(
      id: idValue,
      queue: queueValue,
      envelope: envelopeValue,
      attempt: attemptValue,
      maxRetries: maxRetriesValue,
      priority: priorityValue,
      notBefore: notBefore,
      lockedAt: lockedAt,
      lockedUntil: lockedUntil,
      lockedBy: lockedBy,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (attempt != null) 'attempt': attempt,
      if (maxRetries != null) 'max_retries': maxRetries,
      if (priority != null) 'priority': priority,
      if (notBefore != null) 'not_before': notBefore,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lockedBy != null) 'locked_by': lockedBy,
    };
  }

  static const _StemQueueJobPartialCopyWithSentinel _copyWithSentinel =
      _StemQueueJobPartialCopyWithSentinel();
  StemQueueJobPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? maxRetries = _copyWithSentinel,
    Object? priority = _copyWithSentinel,
    Object? notBefore = _copyWithSentinel,
    Object? lockedAt = _copyWithSentinel,
    Object? lockedUntil = _copyWithSentinel,
    Object? lockedBy = _copyWithSentinel,
  }) {
    return StemQueueJobPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int?,
      maxRetries: identical(maxRetries, _copyWithSentinel)
          ? this.maxRetries
          : maxRetries as int?,
      priority: identical(priority, _copyWithSentinel)
          ? this.priority
          : priority as int?,
      notBefore: identical(notBefore, _copyWithSentinel)
          ? this.notBefore
          : notBefore as DateTime?,
      lockedAt: identical(lockedAt, _copyWithSentinel)
          ? this.lockedAt
          : lockedAt as DateTime?,
      lockedUntil: identical(lockedUntil, _copyWithSentinel)
          ? this.lockedUntil
          : lockedUntil as DateTime?,
      lockedBy: identical(lockedBy, _copyWithSentinel)
          ? this.lockedBy
          : lockedBy as String?,
    );
  }
}

class _StemQueueJobPartialCopyWithSentinel {
  const _StemQueueJobPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemQueueJob].
///
/// This class extends the user-defined [StemQueueJob] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemQueueJob extends StemQueueJob
    with ModelAttributes, TimestampsImpl
    implements OrmEntity {
  /// Internal constructor for [$StemQueueJob].
  $StemQueueJob({
    required String id,
    required String queue,
    required Map<String, Object?> envelope,
    required int attempt,
    required int maxRetries,
    required int priority,
    DateTime? notBefore,
    DateTime? lockedAt,
    DateTime? lockedUntil,
    String? lockedBy,
  }) : super(
         id: id,
         queue: queue,
         envelope: envelope,
         attempt: attempt,
         maxRetries: maxRetries,
         priority: priority,
         notBefore: notBefore,
         lockedAt: lockedAt,
         lockedUntil: lockedUntil,
         lockedBy: lockedBy,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'queue': queue,
      'envelope': envelope,
      'attempt': attempt,
      'max_retries': maxRetries,
      'priority': priority,
      'not_before': notBefore,
      'locked_at': lockedAt,
      'locked_until': lockedUntil,
      'locked_by': lockedBy,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemQueueJob.fromModel(StemQueueJob model) {
    return $StemQueueJob(
      id: model.id,
      queue: model.queue,
      envelope: model.envelope,
      attempt: model.attempt,
      maxRetries: model.maxRetries,
      priority: model.priority,
      notBefore: model.notBefore,
      lockedAt: model.lockedAt,
      lockedUntil: model.lockedUntil,
      lockedBy: model.lockedBy,
    );
  }

  $StemQueueJob copyWith({
    String? id,
    String? queue,
    Map<String, Object?>? envelope,
    int? attempt,
    int? maxRetries,
    int? priority,
    DateTime? notBefore,
    DateTime? lockedAt,
    DateTime? lockedUntil,
    String? lockedBy,
  }) {
    return $StemQueueJob(
      id: id ?? this.id,
      queue: queue ?? this.queue,
      envelope: envelope ?? this.envelope,
      attempt: attempt ?? this.attempt,
      maxRetries: maxRetries ?? this.maxRetries,
      priority: priority ?? this.priority,
      notBefore: notBefore ?? this.notBefore,
      lockedAt: lockedAt ?? this.lockedAt,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lockedBy: lockedBy ?? this.lockedBy,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemQueueJob fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemQueueJobDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemQueueJobDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [queue].
  @override
  String get queue => getAttribute<String>('queue') ?? super.queue;

  /// Tracked setter for [queue].
  set queue(String value) => setAttribute('queue', value);

  /// Tracked getter for [envelope].
  @override
  Map<String, Object?> get envelope =>
      getAttribute<Map<String, Object?>>('envelope') ?? super.envelope;

  /// Tracked setter for [envelope].
  set envelope(Map<String, Object?> value) => setAttribute('envelope', value);

  /// Tracked getter for [attempt].
  @override
  int get attempt => getAttribute<int>('attempt') ?? super.attempt;

  /// Tracked setter for [attempt].
  set attempt(int value) => setAttribute('attempt', value);

  /// Tracked getter for [maxRetries].
  @override
  int get maxRetries => getAttribute<int>('max_retries') ?? super.maxRetries;

  /// Tracked setter for [maxRetries].
  set maxRetries(int value) => setAttribute('max_retries', value);

  /// Tracked getter for [priority].
  @override
  int get priority => getAttribute<int>('priority') ?? super.priority;

  /// Tracked setter for [priority].
  set priority(int value) => setAttribute('priority', value);

  /// Tracked getter for [notBefore].
  @override
  DateTime? get notBefore =>
      getAttribute<DateTime?>('not_before') ?? super.notBefore;

  /// Tracked setter for [notBefore].
  set notBefore(DateTime? value) => setAttribute('not_before', value);

  /// Tracked getter for [lockedAt].
  @override
  DateTime? get lockedAt =>
      getAttribute<DateTime?>('locked_at') ?? super.lockedAt;

  /// Tracked setter for [lockedAt].
  set lockedAt(DateTime? value) => setAttribute('locked_at', value);

  /// Tracked getter for [lockedUntil].
  @override
  DateTime? get lockedUntil =>
      getAttribute<DateTime?>('locked_until') ?? super.lockedUntil;

  /// Tracked setter for [lockedUntil].
  set lockedUntil(DateTime? value) => setAttribute('locked_until', value);

  /// Tracked getter for [lockedBy].
  @override
  String? get lockedBy => getAttribute<String?>('locked_by') ?? super.lockedBy;

  /// Tracked setter for [lockedBy].
  set lockedBy(String? value) => setAttribute('locked_by', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemQueueJobDefinition);
  }
}

class _StemQueueJobCopyWithSentinel {
  const _StemQueueJobCopyWithSentinel();
}

extension StemQueueJobOrmExtension on StemQueueJob {
  static const _StemQueueJobCopyWithSentinel _copyWithSentinel =
      _StemQueueJobCopyWithSentinel();
  StemQueueJob copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? attempt = _copyWithSentinel,
    Object? maxRetries = _copyWithSentinel,
    Object? priority = _copyWithSentinel,
    Object? notBefore = _copyWithSentinel,
    Object? lockedAt = _copyWithSentinel,
    Object? lockedUntil = _copyWithSentinel,
    Object? lockedBy = _copyWithSentinel,
  }) {
    return StemQueueJob(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      queue: identical(queue, _copyWithSentinel) ? this.queue : queue as String,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>,
      attempt: identical(attempt, _copyWithSentinel)
          ? this.attempt
          : attempt as int,
      maxRetries: identical(maxRetries, _copyWithSentinel)
          ? this.maxRetries
          : maxRetries as int,
      priority: identical(priority, _copyWithSentinel)
          ? this.priority
          : priority as int,
      notBefore: identical(notBefore, _copyWithSentinel)
          ? this.notBefore
          : notBefore as DateTime?,
      lockedAt: identical(lockedAt, _copyWithSentinel)
          ? this.lockedAt
          : lockedAt as DateTime?,
      lockedUntil: identical(lockedUntil, _copyWithSentinel)
          ? this.lockedUntil
          : lockedUntil as DateTime?,
      lockedBy: identical(lockedBy, _copyWithSentinel)
          ? this.lockedBy
          : lockedBy as String?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemQueueJobDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemQueueJob fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemQueueJobDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemQueueJob;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemQueueJob toTracked() {
    return $StemQueueJob.fromModel(this);
  }
}

extension StemQueueJobPredicateFields on PredicateBuilder<StemQueueJob> {
  PredicateField<StemQueueJob, String> get id =>
      PredicateField<StemQueueJob, String>(this, 'id');
  PredicateField<StemQueueJob, String> get queue =>
      PredicateField<StemQueueJob, String>(this, 'queue');
  PredicateField<StemQueueJob, Map<String, Object?>> get envelope =>
      PredicateField<StemQueueJob, Map<String, Object?>>(this, 'envelope');
  PredicateField<StemQueueJob, int> get attempt =>
      PredicateField<StemQueueJob, int>(this, 'attempt');
  PredicateField<StemQueueJob, int> get maxRetries =>
      PredicateField<StemQueueJob, int>(this, 'maxRetries');
  PredicateField<StemQueueJob, int> get priority =>
      PredicateField<StemQueueJob, int>(this, 'priority');
  PredicateField<StemQueueJob, DateTime?> get notBefore =>
      PredicateField<StemQueueJob, DateTime?>(this, 'notBefore');
  PredicateField<StemQueueJob, DateTime?> get lockedAt =>
      PredicateField<StemQueueJob, DateTime?>(this, 'lockedAt');
  PredicateField<StemQueueJob, DateTime?> get lockedUntil =>
      PredicateField<StemQueueJob, DateTime?>(this, 'lockedUntil');
  PredicateField<StemQueueJob, String?> get lockedBy =>
      PredicateField<StemQueueJob, String?>(this, 'lockedBy');
}

void registerStemQueueJobEventHandlers(EventBus bus) {
  // No event handlers registered for StemQueueJob.
}
