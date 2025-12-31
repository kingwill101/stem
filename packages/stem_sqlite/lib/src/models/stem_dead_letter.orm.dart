// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_dead_letter.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemDeadLetterIdField = FieldDefinition(
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

const FieldDefinition _$StemDeadLetterQueueField = FieldDefinition(
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

const FieldDefinition _$StemDeadLetterEnvelopeField = FieldDefinition(
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

const FieldDefinition _$StemDeadLetterReasonField = FieldDefinition(
  name: 'reason',
  columnName: 'reason',
  dartType: 'String',
  resolvedType: 'String?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemDeadLetterMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'Map<String, Object?>',
  resolvedType: 'Map<String, Object?>?',
  isPrimaryKey: false,
  isNullable: true,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
  codecType: 'json',
);

const FieldDefinition _$StemDeadLetterDeadAtField = FieldDefinition(
  name: 'deadAt',
  columnName: 'dead_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

Map<String, Object?> _encodeStemDeadLetterUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemDeadLetter;
  return <String, Object?>{
    'id': registry.encodeField(_$StemDeadLetterIdField, m.id),
    'queue': registry.encodeField(_$StemDeadLetterQueueField, m.queue),
    'envelope': registry.encodeField(_$StemDeadLetterEnvelopeField, m.envelope),
    'reason': registry.encodeField(_$StemDeadLetterReasonField, m.reason),
    'meta': registry.encodeField(_$StemDeadLetterMetaField, m.meta),
    'dead_at': registry.encodeField(_$StemDeadLetterDeadAtField, m.deadAt),
  };
}

final ModelDefinition<$StemDeadLetter> _$StemDeadLetterDefinition =
    ModelDefinition(
      modelName: 'StemDeadLetter',
      tableName: 'stem_dead_letters',
      fields: const [
        _$StemDeadLetterIdField,
        _$StemDeadLetterQueueField,
        _$StemDeadLetterEnvelopeField,
        _$StemDeadLetterReasonField,
        _$StemDeadLetterMetaField,
        _$StemDeadLetterDeadAtField,
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
        fieldOverrides: const {
          'envelope': FieldAttributeMetadata(cast: 'json'),
          'meta': FieldAttributeMetadata(cast: 'json'),
        },
        softDeletes: false,
        softDeleteColumn: 'deleted_at',
      ),
      untrackedToMap: _encodeStemDeadLetterUntracked,
      codec: _$StemDeadLetterCodec(),
    );

extension StemDeadLetterOrmDefinition on StemDeadLetter {
  static ModelDefinition<$StemDeadLetter> get definition =>
      _$StemDeadLetterDefinition;
}

class StemDeadLetters {
  const StemDeadLetters._();

  /// Starts building a query for [$StemDeadLetter].
  ///
  /// {@macro ormed.query}
  static Query<$StemDeadLetter> query([String? connection]) =>
      Model.query<$StemDeadLetter>(connection: connection);

  static Future<$StemDeadLetter?> find(Object id, {String? connection}) =>
      Model.find<$StemDeadLetter>(id, connection: connection);

  static Future<$StemDeadLetter> findOrFail(Object id, {String? connection}) =>
      Model.findOrFail<$StemDeadLetter>(id, connection: connection);

  static Future<List<$StemDeadLetter>> all({String? connection}) =>
      Model.all<$StemDeadLetter>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemDeadLetter>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemDeadLetter>(connection: connection);

  static Query<$StemDeadLetter> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemDeadLetter>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemDeadLetter> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemDeadLetter>(column, values, connection: connection);

  static Query<$StemDeadLetter> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemDeadLetter>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemDeadLetter> limit(int count, {String? connection}) =>
      Model.limit<$StemDeadLetter>(count, connection: connection);

  /// Creates a [Repository] for [$StemDeadLetter].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemDeadLetter> repo([String? connection]) =>
      Model.repository<$StemDeadLetter>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemDeadLetter fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemDeadLetterDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemDeadLetter model, {
    ValueCodecRegistry? registry,
  }) => _$StemDeadLetterDefinition.toMap(model, registry: registry);
}

class StemDeadLetterModelFactory {
  const StemDeadLetterModelFactory._();

  static ModelDefinition<$StemDeadLetter> get definition =>
      _$StemDeadLetterDefinition;

  static ModelCodec<$StemDeadLetter> get codec => definition.codec;

  static StemDeadLetter fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemDeadLetter model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemDeadLetter> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemDeadLetter>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemDeadLetter> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemDeadLetter>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemDeadLetterCodec extends ModelCodec<$StemDeadLetter> {
  const _$StemDeadLetterCodec();
  @override
  Map<String, Object?> encode(
    $StemDeadLetter model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemDeadLetterIdField, model.id),
      'queue': registry.encodeField(_$StemDeadLetterQueueField, model.queue),
      'envelope': registry.encodeField(
        _$StemDeadLetterEnvelopeField,
        model.envelope,
      ),
      'reason': registry.encodeField(_$StemDeadLetterReasonField, model.reason),
      'meta': registry.encodeField(_$StemDeadLetterMetaField, model.meta),
      'dead_at': registry.encodeField(
        _$StemDeadLetterDeadAtField,
        model.deadAt,
      ),
    };
  }

  @override
  $StemDeadLetter decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemDeadLetterIdValue =
        registry.decodeField<String>(_$StemDeadLetterIdField, data['id']) ??
        (throw StateError('Field id on StemDeadLetter cannot be null.'));
    final String stemDeadLetterQueueValue =
        registry.decodeField<String>(
          _$StemDeadLetterQueueField,
          data['queue'],
        ) ??
        (throw StateError('Field queue on StemDeadLetter cannot be null.'));
    final Map<String, Object?> stemDeadLetterEnvelopeValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemDeadLetterEnvelopeField,
          data['envelope'],
        ) ??
        (throw StateError('Field envelope on StemDeadLetter cannot be null.'));
    final String? stemDeadLetterReasonValue = registry.decodeField<String?>(
      _$StemDeadLetterReasonField,
      data['reason'],
    );
    final Map<String, Object?>? stemDeadLetterMetaValue = registry
        .decodeField<Map<String, Object?>?>(
          _$StemDeadLetterMetaField,
          data['meta'],
        );
    final DateTime stemDeadLetterDeadAtValue =
        registry.decodeField<DateTime>(
          _$StemDeadLetterDeadAtField,
          data['dead_at'],
        ) ??
        (throw StateError('Field deadAt on StemDeadLetter cannot be null.'));
    final model = $StemDeadLetter(
      id: stemDeadLetterIdValue,
      queue: stemDeadLetterQueueValue,
      envelope: stemDeadLetterEnvelopeValue,
      deadAt: stemDeadLetterDeadAtValue,
      reason: stemDeadLetterReasonValue,
      meta: stemDeadLetterMetaValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemDeadLetterIdValue,
      'queue': stemDeadLetterQueueValue,
      'envelope': stemDeadLetterEnvelopeValue,
      'reason': stemDeadLetterReasonValue,
      'meta': stemDeadLetterMetaValue,
      'dead_at': stemDeadLetterDeadAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemDeadLetter].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemDeadLetterInsertDto implements InsertDto<$StemDeadLetter> {
  const StemDeadLetterInsertDto({
    this.id,
    this.queue,
    this.envelope,
    this.reason,
    this.meta,
    this.deadAt,
  });
  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final String? reason;
  final Map<String, Object?>? meta;
  final DateTime? deadAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (reason != null) 'reason': reason,
      if (meta != null) 'meta': meta,
      if (deadAt != null) 'dead_at': deadAt,
    };
  }

  static const _StemDeadLetterInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemDeadLetterInsertDtoCopyWithSentinel();
  StemDeadLetterInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? deadAt = _copyWithSentinel,
  }) {
    return StemDeadLetterInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      deadAt: identical(deadAt, _copyWithSentinel)
          ? this.deadAt
          : deadAt as DateTime?,
    );
  }
}

class _StemDeadLetterInsertDtoCopyWithSentinel {
  const _StemDeadLetterInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemDeadLetter].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemDeadLetterUpdateDto implements UpdateDto<$StemDeadLetter> {
  const StemDeadLetterUpdateDto({
    this.id,
    this.queue,
    this.envelope,
    this.reason,
    this.meta,
    this.deadAt,
  });
  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final String? reason;
  final Map<String, Object?>? meta;
  final DateTime? deadAt;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (reason != null) 'reason': reason,
      if (meta != null) 'meta': meta,
      if (deadAt != null) 'dead_at': deadAt,
    };
  }

  static const _StemDeadLetterUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemDeadLetterUpdateDtoCopyWithSentinel();
  StemDeadLetterUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? deadAt = _copyWithSentinel,
  }) {
    return StemDeadLetterUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      deadAt: identical(deadAt, _copyWithSentinel)
          ? this.deadAt
          : deadAt as DateTime?,
    );
  }
}

class _StemDeadLetterUpdateDtoCopyWithSentinel {
  const _StemDeadLetterUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemDeadLetter].
///
/// All fields are nullable; intended for subset SELECTs.
class StemDeadLetterPartial implements PartialEntity<$StemDeadLetter> {
  const StemDeadLetterPartial({
    this.id,
    this.queue,
    this.envelope,
    this.reason,
    this.meta,
    this.deadAt,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemDeadLetterPartial.fromRow(Map<String, Object?> row) {
    return StemDeadLetterPartial(
      id: row['id'] as String?,
      queue: row['queue'] as String?,
      envelope: row['envelope'] as Map<String, Object?>?,
      reason: row['reason'] as String?,
      meta: row['meta'] as Map<String, Object?>?,
      deadAt: row['dead_at'] as DateTime?,
    );
  }

  final String? id;
  final String? queue;
  final Map<String, Object?>? envelope;
  final String? reason;
  final Map<String, Object?>? meta;
  final DateTime? deadAt;

  @override
  $StemDeadLetter toEntity() {
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
    final DateTime? deadAtValue = deadAt;
    if (deadAtValue == null) {
      throw StateError('Missing required field: deadAt');
    }
    return $StemDeadLetter(
      id: idValue,
      queue: queueValue,
      envelope: envelopeValue,
      reason: reason,
      meta: meta,
      deadAt: deadAtValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (queue != null) 'queue': queue,
      if (envelope != null) 'envelope': envelope,
      if (reason != null) 'reason': reason,
      if (meta != null) 'meta': meta,
      if (deadAt != null) 'dead_at': deadAt,
    };
  }

  static const _StemDeadLetterPartialCopyWithSentinel _copyWithSentinel =
      _StemDeadLetterPartialCopyWithSentinel();
  StemDeadLetterPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? deadAt = _copyWithSentinel,
  }) {
    return StemDeadLetterPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
      deadAt: identical(deadAt, _copyWithSentinel)
          ? this.deadAt
          : deadAt as DateTime?,
    );
  }
}

class _StemDeadLetterPartialCopyWithSentinel {
  const _StemDeadLetterPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemDeadLetter].
///
/// This class extends the user-defined [StemDeadLetter] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemDeadLetter extends StemDeadLetter
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemDeadLetter].
  $StemDeadLetter({
    required String id,
    required String queue,
    required Map<String, Object?> envelope,
    required DateTime deadAt,
    String? reason,
    Map<String, Object?>? meta,
  }) : super(
         id: id,
         queue: queue,
         envelope: envelope,
         deadAt: deadAt,
         reason: reason,
         meta: meta,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'queue': queue,
      'envelope': envelope,
      'reason': reason,
      'meta': meta,
      'dead_at': deadAt,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemDeadLetter.fromModel(StemDeadLetter model) {
    return $StemDeadLetter(
      id: model.id,
      queue: model.queue,
      envelope: model.envelope,
      reason: model.reason,
      meta: model.meta,
      deadAt: model.deadAt,
    );
  }

  $StemDeadLetter copyWith({
    String? id,
    String? queue,
    Map<String, Object?>? envelope,
    String? reason,
    Map<String, Object?>? meta,
    DateTime? deadAt,
  }) {
    return $StemDeadLetter(
      id: id ?? this.id,
      queue: queue ?? this.queue,
      envelope: envelope ?? this.envelope,
      reason: reason ?? this.reason,
      meta: meta ?? this.meta,
      deadAt: deadAt ?? this.deadAt,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemDeadLetter fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemDeadLetterDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemDeadLetterDefinition.toMap(this, registry: registry);

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

  /// Tracked getter for [reason].
  @override
  String? get reason => getAttribute<String?>('reason') ?? super.reason;

  /// Tracked setter for [reason].
  set reason(String? value) => setAttribute('reason', value);

  /// Tracked getter for [meta].
  @override
  Map<String, Object?>? get meta =>
      getAttribute<Map<String, Object?>?>('meta') ?? super.meta;

  /// Tracked setter for [meta].
  set meta(Map<String, Object?>? value) => setAttribute('meta', value);

  /// Tracked getter for [deadAt].
  @override
  DateTime get deadAt => getAttribute<DateTime>('dead_at') ?? super.deadAt;

  /// Tracked setter for [deadAt].
  set deadAt(DateTime value) => setAttribute('dead_at', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemDeadLetterDefinition);
  }
}

class _StemDeadLetterCopyWithSentinel {
  const _StemDeadLetterCopyWithSentinel();
}

extension StemDeadLetterOrmExtension on StemDeadLetter {
  static const _StemDeadLetterCopyWithSentinel _copyWithSentinel =
      _StemDeadLetterCopyWithSentinel();
  StemDeadLetter copyWith({
    Object? id = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? deadAt = _copyWithSentinel,
    Object? reason = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
  }) {
    return StemDeadLetter(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      queue: identical(queue, _copyWithSentinel) ? this.queue : queue as String,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>,
      deadAt: identical(deadAt, _copyWithSentinel)
          ? this.deadAt
          : deadAt as DateTime,
      reason: identical(reason, _copyWithSentinel)
          ? this.reason
          : reason as String?,
      meta: identical(meta, _copyWithSentinel)
          ? this.meta
          : meta as Map<String, Object?>?,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemDeadLetterDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemDeadLetter fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemDeadLetterDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemDeadLetter;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemDeadLetter toTracked() {
    return $StemDeadLetter.fromModel(this);
  }
}

extension StemDeadLetterPredicateFields on PredicateBuilder<StemDeadLetter> {
  PredicateField<StemDeadLetter, String> get id =>
      PredicateField<StemDeadLetter, String>(this, 'id');
  PredicateField<StemDeadLetter, String> get queue =>
      PredicateField<StemDeadLetter, String>(this, 'queue');
  PredicateField<StemDeadLetter, Map<String, Object?>> get envelope =>
      PredicateField<StemDeadLetter, Map<String, Object?>>(this, 'envelope');
  PredicateField<StemDeadLetter, String?> get reason =>
      PredicateField<StemDeadLetter, String?>(this, 'reason');
  PredicateField<StemDeadLetter, Map<String, Object?>?> get meta =>
      PredicateField<StemDeadLetter, Map<String, Object?>?>(this, 'meta');
  PredicateField<StemDeadLetter, DateTime> get deadAt =>
      PredicateField<StemDeadLetter, DateTime>(this, 'deadAt');
}

void registerStemDeadLetterEventHandlers(EventBus bus) {
  // No event handlers registered for StemDeadLetter.
}
