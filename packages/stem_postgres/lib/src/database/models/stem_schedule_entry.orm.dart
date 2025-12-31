// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_schedule_entry.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemScheduleEntryIdField = FieldDefinition(
  name: 'id',
  columnName: 'id',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: true,
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryTaskNameField = FieldDefinition(
  name: 'taskName',
  columnName: 'task_name',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryQueueField = FieldDefinition(
  name: 'queue',
  columnName: 'queue',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntrySpecField = FieldDefinition(
  name: 'spec',
  columnName: 'spec',
  dartType: 'String',
  resolvedType: 'String',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryArgsField = FieldDefinition(
  name: 'args',
  columnName: 'args',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryKwargsField = FieldDefinition(
  name: 'kwargs',
  columnName: 'kwargs',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryEnabledField = FieldDefinition(
  name: 'enabled',
  columnName: 'enabled',
  dartType: 'bool',
  resolvedType: 'bool',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryJitterField = FieldDefinition(
  name: 'jitter',
  columnName: 'jitter',
  dartType: 'int',
  resolvedType: 'int?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryLastRunAtField = FieldDefinition(
  name: 'lastRunAt',
  columnName: 'last_run_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryNextRunAtField = FieldDefinition(
  name: 'nextRunAt',
  columnName: 'next_run_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryLastJitterField = FieldDefinition(
  name: 'lastJitter',
  columnName: 'last_jitter',
  dartType: 'int',
  resolvedType: 'int?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryLastErrorField = FieldDefinition(
  name: 'lastError',
  columnName: 'last_error',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryTimezoneField = FieldDefinition(
  name: 'timezone',
  columnName: 'timezone',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryTotalRunCountField = FieldDefinition(
  name: 'totalRunCount',
  columnName: 'total_run_count',
  dartType: 'int',
  resolvedType: 'int',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryLastSuccessAtField = FieldDefinition(
  name: 'lastSuccessAt',
  columnName: 'last_success_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryLastErrorAtField = FieldDefinition(
  name: 'lastErrorAt',
  columnName: 'last_error_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryDriftField = FieldDefinition(
  name: 'drift',
  columnName: 'drift',
  dartType: 'int',
  resolvedType: 'int?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryExpireAtField = FieldDefinition(
  name: 'expireAt',
  columnName: 'expire_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryMetaField = FieldDefinition(
  name: 'meta',
  columnName: 'meta',
  dartType: 'String',
  resolvedType: 'String?',
  isNullable: true,
);

const FieldDefinition _$StemScheduleEntryCreatedAtField = FieldDefinition(
  name: 'createdAt',
  columnName: 'created_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryUpdatedAtField = FieldDefinition(
  name: 'updatedAt',
  columnName: 'updated_at',
  dartType: 'DateTime',
  resolvedType: 'DateTime',
  isNullable: false,
);

const FieldDefinition _$StemScheduleEntryVersionField = FieldDefinition(
  name: 'version',
  columnName: 'version',
  dartType: 'int',
  resolvedType: 'int?',
  isNullable: true,
);

Map<String, Object?> _encodeStemScheduleEntryUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemScheduleEntry;
  return <String, Object?>{
    'id': registry.encodeField(_$StemScheduleEntryIdField, m.id),
    'task_name': registry.encodeField(
      _$StemScheduleEntryTaskNameField,
      m.taskName,
    ),
    'queue': registry.encodeField(_$StemScheduleEntryQueueField, m.queue),
    'spec': registry.encodeField(_$StemScheduleEntrySpecField, m.spec),
    'args': registry.encodeField(_$StemScheduleEntryArgsField, m.args),
    'kwargs': registry.encodeField(_$StemScheduleEntryKwargsField, m.kwargs),
    'enabled': registry.encodeField(_$StemScheduleEntryEnabledField, m.enabled),
    'jitter': registry.encodeField(_$StemScheduleEntryJitterField, m.jitter),
    'last_run_at': registry.encodeField(
      _$StemScheduleEntryLastRunAtField,
      m.lastRunAt,
    ),
    'next_run_at': registry.encodeField(
      _$StemScheduleEntryNextRunAtField,
      m.nextRunAt,
    ),
    'last_jitter': registry.encodeField(
      _$StemScheduleEntryLastJitterField,
      m.lastJitter,
    ),
    'last_error': registry.encodeField(
      _$StemScheduleEntryLastErrorField,
      m.lastError,
    ),
    'timezone': registry.encodeField(
      _$StemScheduleEntryTimezoneField,
      m.timezone,
    ),
    'total_run_count': registry.encodeField(
      _$StemScheduleEntryTotalRunCountField,
      m.totalRunCount,
    ),
    'last_success_at': registry.encodeField(
      _$StemScheduleEntryLastSuccessAtField,
      m.lastSuccessAt,
    ),
    'last_error_at': registry.encodeField(
      _$StemScheduleEntryLastErrorAtField,
      m.lastErrorAt,
    ),
    'drift': registry.encodeField(_$StemScheduleEntryDriftField, m.drift),
    'expire_at': registry.encodeField(
      _$StemScheduleEntryExpireAtField,
      m.expireAt,
    ),
    'meta': registry.encodeField(_$StemScheduleEntryMetaField, m.meta),
    'created_at': registry.encodeField(
      _$StemScheduleEntryCreatedAtField,
      m.createdAt,
    ),
    'updated_at': registry.encodeField(
      _$StemScheduleEntryUpdatedAtField,
      m.updatedAt,
    ),
    'version': registry.encodeField(_$StemScheduleEntryVersionField, m.version),
  };
}

const ModelDefinition<$StemScheduleEntry> _$StemScheduleEntryDefinition =
    ModelDefinition(
      modelName: 'StemScheduleEntry',
      tableName: 'stem_schedules',
      fields: [
        _$StemScheduleEntryIdField,
        _$StemScheduleEntryTaskNameField,
        _$StemScheduleEntryQueueField,
        _$StemScheduleEntrySpecField,
        _$StemScheduleEntryArgsField,
        _$StemScheduleEntryKwargsField,
        _$StemScheduleEntryEnabledField,
        _$StemScheduleEntryJitterField,
        _$StemScheduleEntryLastRunAtField,
        _$StemScheduleEntryNextRunAtField,
        _$StemScheduleEntryLastJitterField,
        _$StemScheduleEntryLastErrorField,
        _$StemScheduleEntryTimezoneField,
        _$StemScheduleEntryTotalRunCountField,
        _$StemScheduleEntryLastSuccessAtField,
        _$StemScheduleEntryLastErrorAtField,
        _$StemScheduleEntryDriftField,
        _$StemScheduleEntryExpireAtField,
        _$StemScheduleEntryMetaField,
        _$StemScheduleEntryCreatedAtField,
        _$StemScheduleEntryUpdatedAtField,
        _$StemScheduleEntryVersionField,
      ],
      softDeleteColumn: 'deleted_at',
      untrackedToMap: _encodeStemScheduleEntryUntracked,
      codec: _$StemScheduleEntryCodec(),
    );

extension StemScheduleEntryOrmDefinition on StemScheduleEntry {
  static ModelDefinition<$StemScheduleEntry> get definition =>
      _$StemScheduleEntryDefinition;
}

class StemScheduleEntries {
  const StemScheduleEntries._();

  /// Starts building a query for [$StemScheduleEntry].
  ///
  /// {@macro ormed.query}
  static Query<$StemScheduleEntry> query([String? connection]) =>
      Model.query<$StemScheduleEntry>(connection: connection);

  static Future<$StemScheduleEntry?> find(Object id, {String? connection}) =>
      Model.find<$StemScheduleEntry>(id, connection: connection);

  static Future<$StemScheduleEntry> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemScheduleEntry>(id, connection: connection);

  static Future<List<$StemScheduleEntry>> all({String? connection}) =>
      Model.all<$StemScheduleEntry>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemScheduleEntry>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemScheduleEntry>(connection: connection);

  static Query<$StemScheduleEntry> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemScheduleEntry>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemScheduleEntry> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) =>
      Model.whereIn<$StemScheduleEntry>(column, values, connection: connection);

  static Query<$StemScheduleEntry> orderBy(
    String column, {
    String direction = 'asc',
    String? connection,
  }) => Model.orderBy<$StemScheduleEntry>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemScheduleEntry> limit(int count, {String? connection}) =>
      Model.limit<$StemScheduleEntry>(count, connection: connection);

  /// Creates a [Repository] for [$StemScheduleEntry].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemScheduleEntry> repo([String? connection]) =>
      Model.repository<$StemScheduleEntry>(connection: connection);
}

class StemScheduleEntryModelFactory {
  const StemScheduleEntryModelFactory._();

  static ModelDefinition<$StemScheduleEntry> get definition =>
      _$StemScheduleEntryDefinition;

  static ModelCodec<$StemScheduleEntry> get codec => definition.codec;

  static StemScheduleEntry fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemScheduleEntry model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemScheduleEntry> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemScheduleEntry>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemScheduleEntry> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemScheduleEntry>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemScheduleEntryCodec extends ModelCodec<$StemScheduleEntry> {
  const _$StemScheduleEntryCodec();
  @override
  Map<String, Object?> encode(
    $StemScheduleEntry model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemScheduleEntryIdField, model.id),
      'task_name': registry.encodeField(
        _$StemScheduleEntryTaskNameField,
        model.taskName,
      ),
      'queue': registry.encodeField(_$StemScheduleEntryQueueField, model.queue),
      'spec': registry.encodeField(_$StemScheduleEntrySpecField, model.spec),
      'args': registry.encodeField(_$StemScheduleEntryArgsField, model.args),
      'kwargs': registry.encodeField(
        _$StemScheduleEntryKwargsField,
        model.kwargs,
      ),
      'enabled': registry.encodeField(
        _$StemScheduleEntryEnabledField,
        model.enabled,
      ),
      'jitter': registry.encodeField(
        _$StemScheduleEntryJitterField,
        model.jitter,
      ),
      'last_run_at': registry.encodeField(
        _$StemScheduleEntryLastRunAtField,
        model.lastRunAt,
      ),
      'next_run_at': registry.encodeField(
        _$StemScheduleEntryNextRunAtField,
        model.nextRunAt,
      ),
      'last_jitter': registry.encodeField(
        _$StemScheduleEntryLastJitterField,
        model.lastJitter,
      ),
      'last_error': registry.encodeField(
        _$StemScheduleEntryLastErrorField,
        model.lastError,
      ),
      'timezone': registry.encodeField(
        _$StemScheduleEntryTimezoneField,
        model.timezone,
      ),
      'total_run_count': registry.encodeField(
        _$StemScheduleEntryTotalRunCountField,
        model.totalRunCount,
      ),
      'last_success_at': registry.encodeField(
        _$StemScheduleEntryLastSuccessAtField,
        model.lastSuccessAt,
      ),
      'last_error_at': registry.encodeField(
        _$StemScheduleEntryLastErrorAtField,
        model.lastErrorAt,
      ),
      'drift': registry.encodeField(_$StemScheduleEntryDriftField, model.drift),
      'expire_at': registry.encodeField(
        _$StemScheduleEntryExpireAtField,
        model.expireAt,
      ),
      'meta': registry.encodeField(_$StemScheduleEntryMetaField, model.meta),
      'created_at': registry.encodeField(
        _$StemScheduleEntryCreatedAtField,
        model.createdAt,
      ),
      'updated_at': registry.encodeField(
        _$StemScheduleEntryUpdatedAtField,
        model.updatedAt,
      ),
      'version': registry.encodeField(
        _$StemScheduleEntryVersionField,
        model.version,
      ),
    };
  }

  @override
  $StemScheduleEntry decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final stemScheduleEntryIdValue =
        registry.decodeField<String>(_$StemScheduleEntryIdField, data['id']) ??
        (throw StateError('Field id on StemScheduleEntry cannot be null.'));
    final stemScheduleEntryTaskNameValue =
        registry.decodeField<String>(
          _$StemScheduleEntryTaskNameField,
          data['task_name'],
        ) ??
        (throw StateError(
          'Field taskName on StemScheduleEntry cannot be null.',
        ));
    final stemScheduleEntryQueueValue =
        registry.decodeField<String>(
          _$StemScheduleEntryQueueField,
          data['queue'],
        ) ??
        (throw StateError('Field queue on StemScheduleEntry cannot be null.'));
    final stemScheduleEntrySpecValue =
        registry.decodeField<String>(
          _$StemScheduleEntrySpecField,
          data['spec'],
        ) ??
        (throw StateError('Field spec on StemScheduleEntry cannot be null.'));
    final stemScheduleEntryArgsValue = registry.decodeField<String?>(
      _$StemScheduleEntryArgsField,
      data['args'],
    );
    final stemScheduleEntryKwargsValue = registry.decodeField<String?>(
      _$StemScheduleEntryKwargsField,
      data['kwargs'],
    );
    final stemScheduleEntryEnabledValue =
        registry.decodeField<bool>(
          _$StemScheduleEntryEnabledField,
          data['enabled'],
        ) ??
        (throw StateError(
          'Field enabled on StemScheduleEntry cannot be null.',
        ));
    final stemScheduleEntryJitterValue = registry.decodeField<int?>(
      _$StemScheduleEntryJitterField,
      data['jitter'],
    );
    final stemScheduleEntryLastRunAtValue = registry.decodeField<DateTime?>(
      _$StemScheduleEntryLastRunAtField,
      data['last_run_at'],
    );
    final stemScheduleEntryNextRunAtValue = registry.decodeField<DateTime?>(
      _$StemScheduleEntryNextRunAtField,
      data['next_run_at'],
    );
    final stemScheduleEntryLastJitterValue = registry.decodeField<int?>(
      _$StemScheduleEntryLastJitterField,
      data['last_jitter'],
    );
    final stemScheduleEntryLastErrorValue = registry.decodeField<String?>(
      _$StemScheduleEntryLastErrorField,
      data['last_error'],
    );
    final stemScheduleEntryTimezoneValue = registry.decodeField<String?>(
      _$StemScheduleEntryTimezoneField,
      data['timezone'],
    );
    final stemScheduleEntryTotalRunCountValue =
        registry.decodeField<int>(
          _$StemScheduleEntryTotalRunCountField,
          data['total_run_count'],
        ) ??
        (throw StateError(
          'Field totalRunCount on StemScheduleEntry cannot be null.',
        ));
    final stemScheduleEntryLastSuccessAtValue = registry.decodeField<DateTime?>(
      _$StemScheduleEntryLastSuccessAtField,
      data['last_success_at'],
    );
    final stemScheduleEntryLastErrorAtValue = registry.decodeField<DateTime?>(
      _$StemScheduleEntryLastErrorAtField,
      data['last_error_at'],
    );
    final stemScheduleEntryDriftValue = registry.decodeField<int?>(
      _$StemScheduleEntryDriftField,
      data['drift'],
    );
    final stemScheduleEntryExpireAtValue = registry.decodeField<DateTime?>(
      _$StemScheduleEntryExpireAtField,
      data['expire_at'],
    );
    final stemScheduleEntryMetaValue = registry.decodeField<String?>(
      _$StemScheduleEntryMetaField,
      data['meta'],
    );
    final stemScheduleEntryCreatedAtValue =
        registry.decodeField<DateTime>(
          _$StemScheduleEntryCreatedAtField,
          data['created_at'],
        ) ??
        (throw StateError(
          'Field createdAt on StemScheduleEntry cannot be null.',
        ));
    final stemScheduleEntryUpdatedAtValue =
        registry.decodeField<DateTime>(
          _$StemScheduleEntryUpdatedAtField,
          data['updated_at'],
        ) ??
        (throw StateError(
          'Field updatedAt on StemScheduleEntry cannot be null.',
        ));
    final stemScheduleEntryVersionValue = registry.decodeField<int?>(
      _$StemScheduleEntryVersionField,
      data['version'],
    );
    final model = $StemScheduleEntry(
      id: stemScheduleEntryIdValue,
      taskName: stemScheduleEntryTaskNameValue,
      queue: stemScheduleEntryQueueValue,
      spec: stemScheduleEntrySpecValue,
      args: stemScheduleEntryArgsValue,
      kwargs: stemScheduleEntryKwargsValue,
      enabled: stemScheduleEntryEnabledValue,
      jitter: stemScheduleEntryJitterValue,
      lastRunAt: stemScheduleEntryLastRunAtValue,
      nextRunAt: stemScheduleEntryNextRunAtValue,
      lastJitter: stemScheduleEntryLastJitterValue,
      lastError: stemScheduleEntryLastErrorValue,
      timezone: stemScheduleEntryTimezoneValue,
      totalRunCount: stemScheduleEntryTotalRunCountValue,
      lastSuccessAt: stemScheduleEntryLastSuccessAtValue,
      lastErrorAt: stemScheduleEntryLastErrorAtValue,
      drift: stemScheduleEntryDriftValue,
      expireAt: stemScheduleEntryExpireAtValue,
      meta: stemScheduleEntryMetaValue,
      createdAt: stemScheduleEntryCreatedAtValue,
      updatedAt: stemScheduleEntryUpdatedAtValue,
      version: stemScheduleEntryVersionValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemScheduleEntryIdValue,
      'task_name': stemScheduleEntryTaskNameValue,
      'queue': stemScheduleEntryQueueValue,
      'spec': stemScheduleEntrySpecValue,
      'args': stemScheduleEntryArgsValue,
      'kwargs': stemScheduleEntryKwargsValue,
      'enabled': stemScheduleEntryEnabledValue,
      'jitter': stemScheduleEntryJitterValue,
      'last_run_at': stemScheduleEntryLastRunAtValue,
      'next_run_at': stemScheduleEntryNextRunAtValue,
      'last_jitter': stemScheduleEntryLastJitterValue,
      'last_error': stemScheduleEntryLastErrorValue,
      'timezone': stemScheduleEntryTimezoneValue,
      'total_run_count': stemScheduleEntryTotalRunCountValue,
      'last_success_at': stemScheduleEntryLastSuccessAtValue,
      'last_error_at': stemScheduleEntryLastErrorAtValue,
      'drift': stemScheduleEntryDriftValue,
      'expire_at': stemScheduleEntryExpireAtValue,
      'meta': stemScheduleEntryMetaValue,
      'created_at': stemScheduleEntryCreatedAtValue,
      'updated_at': stemScheduleEntryUpdatedAtValue,
      'version': stemScheduleEntryVersionValue,
    });
    return model;
  }
}

/// Insert DTO for [StemScheduleEntry].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemScheduleEntryInsertDto implements InsertDto<$StemScheduleEntry> {
  const StemScheduleEntryInsertDto({
    this.id,
    this.taskName,
    this.queue,
    this.spec,
    this.args,
    this.kwargs,
    this.enabled,
    this.jitter,
    this.lastRunAt,
    this.nextRunAt,
    this.lastJitter,
    this.lastError,
    this.timezone,
    this.totalRunCount,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.drift,
    this.expireAt,
    this.meta,
    this.createdAt,
    this.updatedAt,
    this.version,
  });
  final String? id;
  final String? taskName;
  final String? queue;
  final String? spec;
  final String? args;
  final String? kwargs;
  final bool? enabled;
  final int? jitter;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final int? lastJitter;
  final String? lastError;
  final String? timezone;
  final int? totalRunCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastErrorAt;
  final int? drift;
  final DateTime? expireAt;
  final String? meta;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? version;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (taskName != null) 'task_name': taskName,
      if (queue != null) 'queue': queue,
      if (spec != null) 'spec': spec,
      if (args != null) 'args': args,
      if (kwargs != null) 'kwargs': kwargs,
      if (enabled != null) 'enabled': enabled,
      if (jitter != null) 'jitter': jitter,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (lastJitter != null) 'last_jitter': lastJitter,
      if (lastError != null) 'last_error': lastError,
      if (timezone != null) 'timezone': timezone,
      if (totalRunCount != null) 'total_run_count': totalRunCount,
      if (lastSuccessAt != null) 'last_success_at': lastSuccessAt,
      if (lastErrorAt != null) 'last_error_at': lastErrorAt,
      if (drift != null) 'drift': drift,
      if (expireAt != null) 'expire_at': expireAt,
      if (meta != null) 'meta': meta,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    };
  }

  static const _StemScheduleEntryInsertDtoCopyWithSentinel _copyWithSentinel =
      _StemScheduleEntryInsertDtoCopyWithSentinel();
  StemScheduleEntryInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? taskName = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? spec = _copyWithSentinel,
    Object? args = _copyWithSentinel,
    Object? kwargs = _copyWithSentinel,
    Object? enabled = _copyWithSentinel,
    Object? jitter = _copyWithSentinel,
    Object? lastRunAt = _copyWithSentinel,
    Object? nextRunAt = _copyWithSentinel,
    Object? lastJitter = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? timezone = _copyWithSentinel,
    Object? totalRunCount = _copyWithSentinel,
    Object? lastSuccessAt = _copyWithSentinel,
    Object? lastErrorAt = _copyWithSentinel,
    Object? drift = _copyWithSentinel,
    Object? expireAt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
  }) {
    return StemScheduleEntryInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      taskName: identical(taskName, _copyWithSentinel)
          ? this.taskName
          : taskName as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      spec: identical(spec, _copyWithSentinel) ? this.spec : spec as String?,
      args: identical(args, _copyWithSentinel) ? this.args : args as String?,
      kwargs: identical(kwargs, _copyWithSentinel)
          ? this.kwargs
          : kwargs as String?,
      enabled: identical(enabled, _copyWithSentinel)
          ? this.enabled
          : enabled as bool?,
      jitter: identical(jitter, _copyWithSentinel)
          ? this.jitter
          : jitter as int?,
      lastRunAt: identical(lastRunAt, _copyWithSentinel)
          ? this.lastRunAt
          : lastRunAt as DateTime?,
      nextRunAt: identical(nextRunAt, _copyWithSentinel)
          ? this.nextRunAt
          : nextRunAt as DateTime?,
      lastJitter: identical(lastJitter, _copyWithSentinel)
          ? this.lastJitter
          : lastJitter as int?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      timezone: identical(timezone, _copyWithSentinel)
          ? this.timezone
          : timezone as String?,
      totalRunCount: identical(totalRunCount, _copyWithSentinel)
          ? this.totalRunCount
          : totalRunCount as int?,
      lastSuccessAt: identical(lastSuccessAt, _copyWithSentinel)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastErrorAt: identical(lastErrorAt, _copyWithSentinel)
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
      drift: identical(drift, _copyWithSentinel) ? this.drift : drift as int?,
      expireAt: identical(expireAt, _copyWithSentinel)
          ? this.expireAt
          : expireAt as DateTime?,
      meta: identical(meta, _copyWithSentinel) ? this.meta : meta as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
    );
  }
}

class _StemScheduleEntryInsertDtoCopyWithSentinel {
  const _StemScheduleEntryInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemScheduleEntry].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemScheduleEntryUpdateDto implements UpdateDto<$StemScheduleEntry> {
  const StemScheduleEntryUpdateDto({
    this.id,
    this.taskName,
    this.queue,
    this.spec,
    this.args,
    this.kwargs,
    this.enabled,
    this.jitter,
    this.lastRunAt,
    this.nextRunAt,
    this.lastJitter,
    this.lastError,
    this.timezone,
    this.totalRunCount,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.drift,
    this.expireAt,
    this.meta,
    this.createdAt,
    this.updatedAt,
    this.version,
  });
  final String? id;
  final String? taskName;
  final String? queue;
  final String? spec;
  final String? args;
  final String? kwargs;
  final bool? enabled;
  final int? jitter;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final int? lastJitter;
  final String? lastError;
  final String? timezone;
  final int? totalRunCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastErrorAt;
  final int? drift;
  final DateTime? expireAt;
  final String? meta;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? version;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (taskName != null) 'task_name': taskName,
      if (queue != null) 'queue': queue,
      if (spec != null) 'spec': spec,
      if (args != null) 'args': args,
      if (kwargs != null) 'kwargs': kwargs,
      if (enabled != null) 'enabled': enabled,
      if (jitter != null) 'jitter': jitter,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (lastJitter != null) 'last_jitter': lastJitter,
      if (lastError != null) 'last_error': lastError,
      if (timezone != null) 'timezone': timezone,
      if (totalRunCount != null) 'total_run_count': totalRunCount,
      if (lastSuccessAt != null) 'last_success_at': lastSuccessAt,
      if (lastErrorAt != null) 'last_error_at': lastErrorAt,
      if (drift != null) 'drift': drift,
      if (expireAt != null) 'expire_at': expireAt,
      if (meta != null) 'meta': meta,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    };
  }

  static const _StemScheduleEntryUpdateDtoCopyWithSentinel _copyWithSentinel =
      _StemScheduleEntryUpdateDtoCopyWithSentinel();
  StemScheduleEntryUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? taskName = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? spec = _copyWithSentinel,
    Object? args = _copyWithSentinel,
    Object? kwargs = _copyWithSentinel,
    Object? enabled = _copyWithSentinel,
    Object? jitter = _copyWithSentinel,
    Object? lastRunAt = _copyWithSentinel,
    Object? nextRunAt = _copyWithSentinel,
    Object? lastJitter = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? timezone = _copyWithSentinel,
    Object? totalRunCount = _copyWithSentinel,
    Object? lastSuccessAt = _copyWithSentinel,
    Object? lastErrorAt = _copyWithSentinel,
    Object? drift = _copyWithSentinel,
    Object? expireAt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
  }) {
    return StemScheduleEntryUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      taskName: identical(taskName, _copyWithSentinel)
          ? this.taskName
          : taskName as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      spec: identical(spec, _copyWithSentinel) ? this.spec : spec as String?,
      args: identical(args, _copyWithSentinel) ? this.args : args as String?,
      kwargs: identical(kwargs, _copyWithSentinel)
          ? this.kwargs
          : kwargs as String?,
      enabled: identical(enabled, _copyWithSentinel)
          ? this.enabled
          : enabled as bool?,
      jitter: identical(jitter, _copyWithSentinel)
          ? this.jitter
          : jitter as int?,
      lastRunAt: identical(lastRunAt, _copyWithSentinel)
          ? this.lastRunAt
          : lastRunAt as DateTime?,
      nextRunAt: identical(nextRunAt, _copyWithSentinel)
          ? this.nextRunAt
          : nextRunAt as DateTime?,
      lastJitter: identical(lastJitter, _copyWithSentinel)
          ? this.lastJitter
          : lastJitter as int?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      timezone: identical(timezone, _copyWithSentinel)
          ? this.timezone
          : timezone as String?,
      totalRunCount: identical(totalRunCount, _copyWithSentinel)
          ? this.totalRunCount
          : totalRunCount as int?,
      lastSuccessAt: identical(lastSuccessAt, _copyWithSentinel)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastErrorAt: identical(lastErrorAt, _copyWithSentinel)
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
      drift: identical(drift, _copyWithSentinel) ? this.drift : drift as int?,
      expireAt: identical(expireAt, _copyWithSentinel)
          ? this.expireAt
          : expireAt as DateTime?,
      meta: identical(meta, _copyWithSentinel) ? this.meta : meta as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
    );
  }
}

class _StemScheduleEntryUpdateDtoCopyWithSentinel {
  const _StemScheduleEntryUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemScheduleEntry].
///
/// All fields are nullable; intended for subset SELECTs.
class StemScheduleEntryPartial implements PartialEntity<$StemScheduleEntry> {
  const StemScheduleEntryPartial({
    this.id,
    this.taskName,
    this.queue,
    this.spec,
    this.args,
    this.kwargs,
    this.enabled,
    this.jitter,
    this.lastRunAt,
    this.nextRunAt,
    this.lastJitter,
    this.lastError,
    this.timezone,
    this.totalRunCount,
    this.lastSuccessAt,
    this.lastErrorAt,
    this.drift,
    this.expireAt,
    this.meta,
    this.createdAt,
    this.updatedAt,
    this.version,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemScheduleEntryPartial.fromRow(Map<String, Object?> row) {
    return StemScheduleEntryPartial(
      id: row['id'] as String?,
      taskName: row['task_name'] as String?,
      queue: row['queue'] as String?,
      spec: row['spec'] as String?,
      args: row['args'] as String?,
      kwargs: row['kwargs'] as String?,
      enabled: row['enabled'] as bool?,
      jitter: row['jitter'] as int?,
      lastRunAt: row['last_run_at'] as DateTime?,
      nextRunAt: row['next_run_at'] as DateTime?,
      lastJitter: row['last_jitter'] as int?,
      lastError: row['last_error'] as String?,
      timezone: row['timezone'] as String?,
      totalRunCount: row['total_run_count'] as int?,
      lastSuccessAt: row['last_success_at'] as DateTime?,
      lastErrorAt: row['last_error_at'] as DateTime?,
      drift: row['drift'] as int?,
      expireAt: row['expire_at'] as DateTime?,
      meta: row['meta'] as String?,
      createdAt: row['created_at'] as DateTime?,
      updatedAt: row['updated_at'] as DateTime?,
      version: row['version'] as int?,
    );
  }

  final String? id;
  final String? taskName;
  final String? queue;
  final String? spec;
  final String? args;
  final String? kwargs;
  final bool? enabled;
  final int? jitter;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final int? lastJitter;
  final String? lastError;
  final String? timezone;
  final int? totalRunCount;
  final DateTime? lastSuccessAt;
  final DateTime? lastErrorAt;
  final int? drift;
  final DateTime? expireAt;
  final String? meta;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? version;

  @override
  $StemScheduleEntry toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final taskNameValue = taskName;
    if (taskNameValue == null) {
      throw StateError('Missing required field: taskName');
    }
    final queueValue = queue;
    if (queueValue == null) {
      throw StateError('Missing required field: queue');
    }
    final specValue = spec;
    if (specValue == null) {
      throw StateError('Missing required field: spec');
    }
    final enabledValue = enabled;
    if (enabledValue == null) {
      throw StateError('Missing required field: enabled');
    }
    final totalRunCountValue = totalRunCount;
    if (totalRunCountValue == null) {
      throw StateError('Missing required field: totalRunCount');
    }
    final createdAtValue = createdAt;
    if (createdAtValue == null) {
      throw StateError('Missing required field: createdAt');
    }
    final updatedAtValue = updatedAt;
    if (updatedAtValue == null) {
      throw StateError('Missing required field: updatedAt');
    }
    return $StemScheduleEntry(
      id: idValue,
      taskName: taskNameValue,
      queue: queueValue,
      spec: specValue,
      args: args,
      kwargs: kwargs,
      enabled: enabledValue,
      jitter: jitter,
      lastRunAt: lastRunAt,
      nextRunAt: nextRunAt,
      lastJitter: lastJitter,
      lastError: lastError,
      timezone: timezone,
      totalRunCount: totalRunCountValue,
      lastSuccessAt: lastSuccessAt,
      lastErrorAt: lastErrorAt,
      drift: drift,
      expireAt: expireAt,
      meta: meta,
      createdAt: createdAtValue,
      updatedAt: updatedAtValue,
      version: version,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (taskName != null) 'task_name': taskName,
      if (queue != null) 'queue': queue,
      if (spec != null) 'spec': spec,
      if (args != null) 'args': args,
      if (kwargs != null) 'kwargs': kwargs,
      if (enabled != null) 'enabled': enabled,
      if (jitter != null) 'jitter': jitter,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (lastJitter != null) 'last_jitter': lastJitter,
      if (lastError != null) 'last_error': lastError,
      if (timezone != null) 'timezone': timezone,
      if (totalRunCount != null) 'total_run_count': totalRunCount,
      if (lastSuccessAt != null) 'last_success_at': lastSuccessAt,
      if (lastErrorAt != null) 'last_error_at': lastErrorAt,
      if (drift != null) 'drift': drift,
      if (expireAt != null) 'expire_at': expireAt,
      if (meta != null) 'meta': meta,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (version != null) 'version': version,
    };
  }

  static const _StemScheduleEntryPartialCopyWithSentinel _copyWithSentinel =
      _StemScheduleEntryPartialCopyWithSentinel();
  StemScheduleEntryPartial copyWith({
    Object? id = _copyWithSentinel,
    Object? taskName = _copyWithSentinel,
    Object? queue = _copyWithSentinel,
    Object? spec = _copyWithSentinel,
    Object? args = _copyWithSentinel,
    Object? kwargs = _copyWithSentinel,
    Object? enabled = _copyWithSentinel,
    Object? jitter = _copyWithSentinel,
    Object? lastRunAt = _copyWithSentinel,
    Object? nextRunAt = _copyWithSentinel,
    Object? lastJitter = _copyWithSentinel,
    Object? lastError = _copyWithSentinel,
    Object? timezone = _copyWithSentinel,
    Object? totalRunCount = _copyWithSentinel,
    Object? lastSuccessAt = _copyWithSentinel,
    Object? lastErrorAt = _copyWithSentinel,
    Object? drift = _copyWithSentinel,
    Object? expireAt = _copyWithSentinel,
    Object? meta = _copyWithSentinel,
    Object? createdAt = _copyWithSentinel,
    Object? updatedAt = _copyWithSentinel,
    Object? version = _copyWithSentinel,
  }) {
    return StemScheduleEntryPartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      taskName: identical(taskName, _copyWithSentinel)
          ? this.taskName
          : taskName as String?,
      queue: identical(queue, _copyWithSentinel)
          ? this.queue
          : queue as String?,
      spec: identical(spec, _copyWithSentinel) ? this.spec : spec as String?,
      args: identical(args, _copyWithSentinel) ? this.args : args as String?,
      kwargs: identical(kwargs, _copyWithSentinel)
          ? this.kwargs
          : kwargs as String?,
      enabled: identical(enabled, _copyWithSentinel)
          ? this.enabled
          : enabled as bool?,
      jitter: identical(jitter, _copyWithSentinel)
          ? this.jitter
          : jitter as int?,
      lastRunAt: identical(lastRunAt, _copyWithSentinel)
          ? this.lastRunAt
          : lastRunAt as DateTime?,
      nextRunAt: identical(nextRunAt, _copyWithSentinel)
          ? this.nextRunAt
          : nextRunAt as DateTime?,
      lastJitter: identical(lastJitter, _copyWithSentinel)
          ? this.lastJitter
          : lastJitter as int?,
      lastError: identical(lastError, _copyWithSentinel)
          ? this.lastError
          : lastError as String?,
      timezone: identical(timezone, _copyWithSentinel)
          ? this.timezone
          : timezone as String?,
      totalRunCount: identical(totalRunCount, _copyWithSentinel)
          ? this.totalRunCount
          : totalRunCount as int?,
      lastSuccessAt: identical(lastSuccessAt, _copyWithSentinel)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      lastErrorAt: identical(lastErrorAt, _copyWithSentinel)
          ? this.lastErrorAt
          : lastErrorAt as DateTime?,
      drift: identical(drift, _copyWithSentinel) ? this.drift : drift as int?,
      expireAt: identical(expireAt, _copyWithSentinel)
          ? this.expireAt
          : expireAt as DateTime?,
      meta: identical(meta, _copyWithSentinel) ? this.meta : meta as String?,
      createdAt: identical(createdAt, _copyWithSentinel)
          ? this.createdAt
          : createdAt as DateTime?,
      updatedAt: identical(updatedAt, _copyWithSentinel)
          ? this.updatedAt
          : updatedAt as DateTime?,
      version: identical(version, _copyWithSentinel)
          ? this.version
          : version as int?,
    );
  }
}

class _StemScheduleEntryPartialCopyWithSentinel {
  const _StemScheduleEntryPartialCopyWithSentinel();
}

/// Generated tracked model class for [StemScheduleEntry].
///
/// This class extends the user-defined [StemScheduleEntry] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemScheduleEntry extends StemScheduleEntry
    with ModelAttributes
    implements OrmEntity {
  /// Internal constructor for [$StemScheduleEntry].
  $StemScheduleEntry({
    required String id,
    required String taskName,
    required String queue,
    required String spec,
    required bool enabled,
    required int totalRunCount,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? args,
    String? kwargs,
    int? jitter,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    int? lastJitter,
    String? lastError,
    String? timezone,
    DateTime? lastSuccessAt,
    DateTime? lastErrorAt,
    int? drift,
    DateTime? expireAt,
    String? meta,
    int? version,
  }) : super.new(
         id: id,
         taskName: taskName,
         queue: queue,
         spec: spec,
         args: args,
         kwargs: kwargs,
         enabled: enabled,
         jitter: jitter,
         lastRunAt: lastRunAt,
         nextRunAt: nextRunAt,
         lastJitter: lastJitter,
         lastError: lastError,
         timezone: timezone,
         totalRunCount: totalRunCount,
         lastSuccessAt: lastSuccessAt,
         lastErrorAt: lastErrorAt,
         drift: drift,
         expireAt: expireAt,
         meta: meta,
         createdAt: createdAt,
         updatedAt: updatedAt,
         version: version,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'task_name': taskName,
      'queue': queue,
      'spec': spec,
      'args': args,
      'kwargs': kwargs,
      'enabled': enabled,
      'jitter': jitter,
      'last_run_at': lastRunAt,
      'next_run_at': nextRunAt,
      'last_jitter': lastJitter,
      'last_error': lastError,
      'timezone': timezone,
      'total_run_count': totalRunCount,
      'last_success_at': lastSuccessAt,
      'last_error_at': lastErrorAt,
      'drift': drift,
      'expire_at': expireAt,
      'meta': meta,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'version': version,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemScheduleEntry.fromModel(StemScheduleEntry model) {
    return $StemScheduleEntry(
      id: model.id,
      taskName: model.taskName,
      queue: model.queue,
      spec: model.spec,
      args: model.args,
      kwargs: model.kwargs,
      enabled: model.enabled,
      jitter: model.jitter,
      lastRunAt: model.lastRunAt,
      nextRunAt: model.nextRunAt,
      lastJitter: model.lastJitter,
      lastError: model.lastError,
      timezone: model.timezone,
      totalRunCount: model.totalRunCount,
      lastSuccessAt: model.lastSuccessAt,
      lastErrorAt: model.lastErrorAt,
      drift: model.drift,
      expireAt: model.expireAt,
      meta: model.meta,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
      version: model.version,
    );
  }

  $StemScheduleEntry copyWith({
    String? id,
    String? taskName,
    String? queue,
    String? spec,
    String? args,
    String? kwargs,
    bool? enabled,
    int? jitter,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    int? lastJitter,
    String? lastError,
    String? timezone,
    int? totalRunCount,
    DateTime? lastSuccessAt,
    DateTime? lastErrorAt,
    int? drift,
    DateTime? expireAt,
    String? meta,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
  }) {
    return $StemScheduleEntry(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      queue: queue ?? this.queue,
      spec: spec ?? this.spec,
      args: args ?? this.args,
      kwargs: kwargs ?? this.kwargs,
      enabled: enabled ?? this.enabled,
      jitter: jitter ?? this.jitter,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      lastJitter: lastJitter ?? this.lastJitter,
      lastError: lastError ?? this.lastError,
      timezone: timezone ?? this.timezone,
      totalRunCount: totalRunCount ?? this.totalRunCount,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastErrorAt: lastErrorAt ?? this.lastErrorAt,
      drift: drift ?? this.drift,
      expireAt: expireAt ?? this.expireAt,
      meta: meta ?? this.meta,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [taskName].
  @override
  String get taskName => getAttribute<String>('task_name') ?? super.taskName;

  /// Tracked setter for [taskName].
  set taskName(String value) => setAttribute('task_name', value);

  /// Tracked getter for [queue].
  @override
  String get queue => getAttribute<String>('queue') ?? super.queue;

  /// Tracked setter for [queue].
  set queue(String value) => setAttribute('queue', value);

  /// Tracked getter for [spec].
  @override
  String get spec => getAttribute<String>('spec') ?? super.spec;

  /// Tracked setter for [spec].
  set spec(String value) => setAttribute('spec', value);

  /// Tracked getter for [args].
  @override
  String? get args => getAttribute<String?>('args') ?? super.args;

  /// Tracked setter for [args].
  set args(String? value) => setAttribute('args', value);

  /// Tracked getter for [kwargs].
  @override
  String? get kwargs => getAttribute<String?>('kwargs') ?? super.kwargs;

  /// Tracked setter for [kwargs].
  set kwargs(String? value) => setAttribute('kwargs', value);

  /// Tracked getter for [enabled].
  @override
  bool get enabled => getAttribute<bool>('enabled') ?? super.enabled;

  /// Tracked setter for [enabled].
  set enabled(bool value) => setAttribute('enabled', value);

  /// Tracked getter for [jitter].
  @override
  int? get jitter => getAttribute<int?>('jitter') ?? super.jitter;

  /// Tracked setter for [jitter].
  set jitter(int? value) => setAttribute('jitter', value);

  /// Tracked getter for [lastRunAt].
  @override
  DateTime? get lastRunAt =>
      getAttribute<DateTime?>('last_run_at') ?? super.lastRunAt;

  /// Tracked setter for [lastRunAt].
  set lastRunAt(DateTime? value) => setAttribute('last_run_at', value);

  /// Tracked getter for [nextRunAt].
  @override
  DateTime? get nextRunAt =>
      getAttribute<DateTime?>('next_run_at') ?? super.nextRunAt;

  /// Tracked setter for [nextRunAt].
  set nextRunAt(DateTime? value) => setAttribute('next_run_at', value);

  /// Tracked getter for [lastJitter].
  @override
  int? get lastJitter => getAttribute<int?>('last_jitter') ?? super.lastJitter;

  /// Tracked setter for [lastJitter].
  set lastJitter(int? value) => setAttribute('last_jitter', value);

  /// Tracked getter for [lastError].
  @override
  String? get lastError =>
      getAttribute<String?>('last_error') ?? super.lastError;

  /// Tracked setter for [lastError].
  set lastError(String? value) => setAttribute('last_error', value);

  /// Tracked getter for [timezone].
  @override
  String? get timezone => getAttribute<String?>('timezone') ?? super.timezone;

  /// Tracked setter for [timezone].
  set timezone(String? value) => setAttribute('timezone', value);

  /// Tracked getter for [totalRunCount].
  @override
  int get totalRunCount =>
      getAttribute<int>('total_run_count') ?? super.totalRunCount;

  /// Tracked setter for [totalRunCount].
  set totalRunCount(int value) => setAttribute('total_run_count', value);

  /// Tracked getter for [lastSuccessAt].
  @override
  DateTime? get lastSuccessAt =>
      getAttribute<DateTime?>('last_success_at') ?? super.lastSuccessAt;

  /// Tracked setter for [lastSuccessAt].
  set lastSuccessAt(DateTime? value) => setAttribute('last_success_at', value);

  /// Tracked getter for [lastErrorAt].
  @override
  DateTime? get lastErrorAt =>
      getAttribute<DateTime?>('last_error_at') ?? super.lastErrorAt;

  /// Tracked setter for [lastErrorAt].
  set lastErrorAt(DateTime? value) => setAttribute('last_error_at', value);

  /// Tracked getter for [drift].
  @override
  int? get drift => getAttribute<int?>('drift') ?? super.drift;

  /// Tracked setter for [drift].
  set drift(int? value) => setAttribute('drift', value);

  /// Tracked getter for [expireAt].
  @override
  DateTime? get expireAt =>
      getAttribute<DateTime?>('expire_at') ?? super.expireAt;

  /// Tracked setter for [expireAt].
  set expireAt(DateTime? value) => setAttribute('expire_at', value);

  /// Tracked getter for [meta].
  @override
  String? get meta => getAttribute<String?>('meta') ?? super.meta;

  /// Tracked setter for [meta].
  set meta(String? value) => setAttribute('meta', value);

  /// Tracked getter for [createdAt].
  @override
  DateTime get createdAt =>
      getAttribute<DateTime>('created_at') ?? super.createdAt;

  /// Tracked setter for [createdAt].
  set createdAt(DateTime value) => setAttribute('created_at', value);

  /// Tracked getter for [updatedAt].
  @override
  DateTime get updatedAt =>
      getAttribute<DateTime>('updated_at') ?? super.updatedAt;

  /// Tracked setter for [updatedAt].
  set updatedAt(DateTime value) => setAttribute('updated_at', value);

  /// Tracked getter for [version].
  @override
  int? get version => getAttribute<int?>('version') ?? super.version;

  /// Tracked setter for [version].
  set version(int? value) => setAttribute('version', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemScheduleEntryDefinition);
  }
}

extension StemScheduleEntryOrmExtension on StemScheduleEntry {
  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemScheduleEntry;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemScheduleEntry toTracked() {
    return $StemScheduleEntry.fromModel(this);
  }
}

void registerStemScheduleEntryEventHandlers(EventBus bus) {
  // No event handlers registered for StemScheduleEntry.
}
