// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'stem_broadcast_message.dart';

// **************************************************************************
// OrmModelGenerator
// **************************************************************************

const FieldDefinition _$StemBroadcastMessageIdField = FieldDefinition(
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

const FieldDefinition _$StemBroadcastMessageNamespaceField = FieldDefinition(
  name: 'namespace',
  columnName: 'namespace',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastMessageChannelField = FieldDefinition(
  name: 'channel',
  columnName: 'channel',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastMessageEnvelopeField = FieldDefinition(
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

const FieldDefinition _$StemBroadcastMessageDeliveryField = FieldDefinition(
  name: 'delivery',
  columnName: 'delivery',
  dartType: 'String',
  resolvedType: 'String',
  isPrimaryKey: false,
  isNullable: false,
  isUnique: false,
  isIndexed: false,
  autoIncrement: false,
);

const FieldDefinition _$StemBroadcastMessageCreatedAtField = FieldDefinition(
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

const FieldDefinition _$StemBroadcastMessageUpdatedAtField = FieldDefinition(
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

Map<String, Object?> _encodeStemBroadcastMessageUntracked(
  Object model,
  ValueCodecRegistry registry,
) {
  final m = model as StemBroadcastMessage;
  return <String, Object?>{
    'id': registry.encodeField(_$StemBroadcastMessageIdField, m.id),
    'namespace': registry.encodeField(
      _$StemBroadcastMessageNamespaceField,
      m.namespace,
    ),
    'channel': registry.encodeField(
      _$StemBroadcastMessageChannelField,
      m.channel,
    ),
    'envelope': registry.encodeField(
      _$StemBroadcastMessageEnvelopeField,
      m.envelope,
    ),
    'delivery': registry.encodeField(
      _$StemBroadcastMessageDeliveryField,
      m.delivery,
    ),
  };
}

final ModelDefinition<$StemBroadcastMessage> _$StemBroadcastMessageDefinition =
    ModelDefinition(
      modelName: 'StemBroadcastMessage',
      tableName: 'stem_broadcast_messages',
      fields: const [
        _$StemBroadcastMessageIdField,
        _$StemBroadcastMessageNamespaceField,
        _$StemBroadcastMessageChannelField,
        _$StemBroadcastMessageEnvelopeField,
        _$StemBroadcastMessageDeliveryField,
        _$StemBroadcastMessageCreatedAtField,
        _$StemBroadcastMessageUpdatedAtField,
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
        },
        softDeletes: false,
        softDeleteColumn: 'deleted_at',
      ),
      untrackedToMap: _encodeStemBroadcastMessageUntracked,
      codec: _$StemBroadcastMessageCodec(),
    );

extension StemBroadcastMessageOrmDefinition on StemBroadcastMessage {
  static ModelDefinition<$StemBroadcastMessage> get definition =>
      _$StemBroadcastMessageDefinition;
}

class StemBroadcastMessages {
  const StemBroadcastMessages._();

  /// Starts building a query for [$StemBroadcastMessage].
  ///
  /// {@macro ormed.query}
  static Query<$StemBroadcastMessage> query([String? connection]) =>
      Model.query<$StemBroadcastMessage>(connection: connection);

  static Future<$StemBroadcastMessage?> find(Object id, {String? connection}) =>
      Model.find<$StemBroadcastMessage>(id, connection: connection);

  static Future<$StemBroadcastMessage> findOrFail(
    Object id, {
    String? connection,
  }) => Model.findOrFail<$StemBroadcastMessage>(id, connection: connection);

  static Future<List<$StemBroadcastMessage>> all({String? connection}) =>
      Model.all<$StemBroadcastMessage>(connection: connection);

  static Future<int> count({String? connection}) =>
      Model.count<$StemBroadcastMessage>(connection: connection);

  static Future<bool> anyExist({String? connection}) =>
      Model.anyExist<$StemBroadcastMessage>(connection: connection);

  static Query<$StemBroadcastMessage> where(
    String column,
    String operator,
    dynamic value, {
    String? connection,
  }) => Model.where<$StemBroadcastMessage>(
    column,
    operator,
    value,
    connection: connection,
  );

  static Query<$StemBroadcastMessage> whereIn(
    String column,
    List<dynamic> values, {
    String? connection,
  }) => Model.whereIn<$StemBroadcastMessage>(
    column,
    values,
    connection: connection,
  );

  static Query<$StemBroadcastMessage> orderBy(
    String column, {
    String direction = "asc",
    String? connection,
  }) => Model.orderBy<$StemBroadcastMessage>(
    column,
    direction: direction,
    connection: connection,
  );

  static Query<$StemBroadcastMessage> limit(int count, {String? connection}) =>
      Model.limit<$StemBroadcastMessage>(count, connection: connection);

  /// Creates a [Repository] for [$StemBroadcastMessage].
  ///
  /// {@macro ormed.repository}
  static Repository<$StemBroadcastMessage> repo([String? connection]) =>
      Model.repository<$StemBroadcastMessage>(connection: connection);

  /// Builds a tracked model from a column/value map.
  static $StemBroadcastMessage fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemBroadcastMessageDefinition.fromMap(data, registry: registry);

  /// Converts a tracked model to a column/value map.
  static Map<String, Object?> toMap(
    $StemBroadcastMessage model, {
    ValueCodecRegistry? registry,
  }) => _$StemBroadcastMessageDefinition.toMap(model, registry: registry);
}

class StemBroadcastMessageModelFactory {
  const StemBroadcastMessageModelFactory._();

  static ModelDefinition<$StemBroadcastMessage> get definition =>
      _$StemBroadcastMessageDefinition;

  static ModelCodec<$StemBroadcastMessage> get codec => definition.codec;

  static StemBroadcastMessage fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => definition.fromMap(data, registry: registry);

  static Map<String, Object?> toMap(
    StemBroadcastMessage model, {
    ValueCodecRegistry? registry,
  }) => definition.toMap(model.toTracked(), registry: registry);

  static void registerWith(ModelRegistry registry) =>
      registry.register(definition);

  static ModelFactoryConnection<StemBroadcastMessage> withConnection(
    QueryContext context,
  ) => ModelFactoryConnection<StemBroadcastMessage>(
    definition: definition,
    context: context,
  );

  static ModelFactoryBuilder<StemBroadcastMessage> factory({
    GeneratorProvider? generatorProvider,
  }) => ModelFactoryBuilder<StemBroadcastMessage>(
    definition: definition,
    generatorProvider: generatorProvider,
  );
}

class _$StemBroadcastMessageCodec extends ModelCodec<$StemBroadcastMessage> {
  const _$StemBroadcastMessageCodec();
  @override
  Map<String, Object?> encode(
    $StemBroadcastMessage model,
    ValueCodecRegistry registry,
  ) {
    return <String, Object?>{
      'id': registry.encodeField(_$StemBroadcastMessageIdField, model.id),
      'namespace': registry.encodeField(
        _$StemBroadcastMessageNamespaceField,
        model.namespace,
      ),
      'channel': registry.encodeField(
        _$StemBroadcastMessageChannelField,
        model.channel,
      ),
      'envelope': registry.encodeField(
        _$StemBroadcastMessageEnvelopeField,
        model.envelope,
      ),
      'delivery': registry.encodeField(
        _$StemBroadcastMessageDeliveryField,
        model.delivery,
      ),
      if (model.hasAttribute('created_at'))
        'created_at': registry.encodeField(
          _$StemBroadcastMessageCreatedAtField,
          model.getAttribute<DateTime?>('created_at'),
        ),
      if (model.hasAttribute('updated_at'))
        'updated_at': registry.encodeField(
          _$StemBroadcastMessageUpdatedAtField,
          model.getAttribute<DateTime?>('updated_at'),
        ),
    };
  }

  @override
  $StemBroadcastMessage decode(
    Map<String, Object?> data,
    ValueCodecRegistry registry,
  ) {
    final String stemBroadcastMessageIdValue =
        registry.decodeField<String>(
          _$StemBroadcastMessageIdField,
          data['id'],
        ) ??
        (throw StateError('Field id on StemBroadcastMessage cannot be null.'));
    final String stemBroadcastMessageNamespaceValue =
        registry.decodeField<String>(
          _$StemBroadcastMessageNamespaceField,
          data['namespace'],
        ) ??
        (throw StateError(
          'Field namespace on StemBroadcastMessage cannot be null.',
        ));
    final String stemBroadcastMessageChannelValue =
        registry.decodeField<String>(
          _$StemBroadcastMessageChannelField,
          data['channel'],
        ) ??
        (throw StateError(
          'Field channel on StemBroadcastMessage cannot be null.',
        ));
    final Map<String, Object?> stemBroadcastMessageEnvelopeValue =
        registry.decodeField<Map<String, Object?>>(
          _$StemBroadcastMessageEnvelopeField,
          data['envelope'],
        ) ??
        (throw StateError(
          'Field envelope on StemBroadcastMessage cannot be null.',
        ));
    final String stemBroadcastMessageDeliveryValue =
        registry.decodeField<String>(
          _$StemBroadcastMessageDeliveryField,
          data['delivery'],
        ) ??
        (throw StateError(
          'Field delivery on StemBroadcastMessage cannot be null.',
        ));
    final DateTime? stemBroadcastMessageCreatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemBroadcastMessageCreatedAtField,
          data['created_at'],
        );
    final DateTime? stemBroadcastMessageUpdatedAtValue = registry
        .decodeField<DateTime?>(
          _$StemBroadcastMessageUpdatedAtField,
          data['updated_at'],
        );
    final model = $StemBroadcastMessage(
      id: stemBroadcastMessageIdValue,
      namespace: stemBroadcastMessageNamespaceValue,
      channel: stemBroadcastMessageChannelValue,
      envelope: stemBroadcastMessageEnvelopeValue,
      delivery: stemBroadcastMessageDeliveryValue,
    );
    model._attachOrmRuntimeMetadata({
      'id': stemBroadcastMessageIdValue,
      'namespace': stemBroadcastMessageNamespaceValue,
      'channel': stemBroadcastMessageChannelValue,
      'envelope': stemBroadcastMessageEnvelopeValue,
      'delivery': stemBroadcastMessageDeliveryValue,
      if (data.containsKey('created_at'))
        'created_at': stemBroadcastMessageCreatedAtValue,
      if (data.containsKey('updated_at'))
        'updated_at': stemBroadcastMessageUpdatedAtValue,
    });
    return model;
  }
}

/// Insert DTO for [StemBroadcastMessage].
///
/// Auto-increment/DB-generated fields are omitted by default.
class StemBroadcastMessageInsertDto
    implements InsertDto<$StemBroadcastMessage> {
  const StemBroadcastMessageInsertDto({
    this.id,
    this.namespace,
    this.channel,
    this.envelope,
    this.delivery,
  });
  final String? id;
  final String? namespace;
  final String? channel;
  final Map<String, Object?>? envelope;
  final String? delivery;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (channel != null) 'channel': channel,
      if (envelope != null) 'envelope': envelope,
      if (delivery != null) 'delivery': delivery,
    };
  }

  static const _StemBroadcastMessageInsertDtoCopyWithSentinel
  _copyWithSentinel = _StemBroadcastMessageInsertDtoCopyWithSentinel();
  StemBroadcastMessageInsertDto copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? channel = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? delivery = _copyWithSentinel,
  }) {
    return StemBroadcastMessageInsertDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      channel: identical(channel, _copyWithSentinel)
          ? this.channel
          : channel as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      delivery: identical(delivery, _copyWithSentinel)
          ? this.delivery
          : delivery as String?,
    );
  }
}

class _StemBroadcastMessageInsertDtoCopyWithSentinel {
  const _StemBroadcastMessageInsertDtoCopyWithSentinel();
}

/// Update DTO for [StemBroadcastMessage].
///
/// All fields are optional; only provided entries are used in SET clauses.
class StemBroadcastMessageUpdateDto
    implements UpdateDto<$StemBroadcastMessage> {
  const StemBroadcastMessageUpdateDto({
    this.id,
    this.namespace,
    this.channel,
    this.envelope,
    this.delivery,
  });
  final String? id;
  final String? namespace;
  final String? channel;
  final Map<String, Object?>? envelope;
  final String? delivery;

  @override
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (channel != null) 'channel': channel,
      if (envelope != null) 'envelope': envelope,
      if (delivery != null) 'delivery': delivery,
    };
  }

  static const _StemBroadcastMessageUpdateDtoCopyWithSentinel
  _copyWithSentinel = _StemBroadcastMessageUpdateDtoCopyWithSentinel();
  StemBroadcastMessageUpdateDto copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? channel = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? delivery = _copyWithSentinel,
  }) {
    return StemBroadcastMessageUpdateDto(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      channel: identical(channel, _copyWithSentinel)
          ? this.channel
          : channel as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      delivery: identical(delivery, _copyWithSentinel)
          ? this.delivery
          : delivery as String?,
    );
  }
}

class _StemBroadcastMessageUpdateDtoCopyWithSentinel {
  const _StemBroadcastMessageUpdateDtoCopyWithSentinel();
}

/// Partial projection for [StemBroadcastMessage].
///
/// All fields are nullable; intended for subset SELECTs.
class StemBroadcastMessagePartial
    implements PartialEntity<$StemBroadcastMessage> {
  const StemBroadcastMessagePartial({
    this.id,
    this.namespace,
    this.channel,
    this.envelope,
    this.delivery,
  });

  /// Creates a partial from a database row map.
  ///
  /// The [row] keys should be column names (snake_case).
  /// Missing columns will result in null field values.
  factory StemBroadcastMessagePartial.fromRow(Map<String, Object?> row) {
    return StemBroadcastMessagePartial(
      id: row['id'] as String?,
      namespace: row['namespace'] as String?,
      channel: row['channel'] as String?,
      envelope: row['envelope'] as Map<String, Object?>?,
      delivery: row['delivery'] as String?,
    );
  }

  final String? id;
  final String? namespace;
  final String? channel;
  final Map<String, Object?>? envelope;
  final String? delivery;

  @override
  $StemBroadcastMessage toEntity() {
    // Basic required-field check: non-nullable fields must be present.
    final String? idValue = id;
    if (idValue == null) {
      throw StateError('Missing required field: id');
    }
    final String? namespaceValue = namespace;
    if (namespaceValue == null) {
      throw StateError('Missing required field: namespace');
    }
    final String? channelValue = channel;
    if (channelValue == null) {
      throw StateError('Missing required field: channel');
    }
    final Map<String, Object?>? envelopeValue = envelope;
    if (envelopeValue == null) {
      throw StateError('Missing required field: envelope');
    }
    final String? deliveryValue = delivery;
    if (deliveryValue == null) {
      throw StateError('Missing required field: delivery');
    }
    return $StemBroadcastMessage(
      id: idValue,
      namespace: namespaceValue,
      channel: channelValue,
      envelope: envelopeValue,
      delivery: deliveryValue,
    );
  }

  @override
  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      if (namespace != null) 'namespace': namespace,
      if (channel != null) 'channel': channel,
      if (envelope != null) 'envelope': envelope,
      if (delivery != null) 'delivery': delivery,
    };
  }

  static const _StemBroadcastMessagePartialCopyWithSentinel _copyWithSentinel =
      _StemBroadcastMessagePartialCopyWithSentinel();
  StemBroadcastMessagePartial copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? channel = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? delivery = _copyWithSentinel,
  }) {
    return StemBroadcastMessagePartial(
      id: identical(id, _copyWithSentinel) ? this.id : id as String?,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String?,
      channel: identical(channel, _copyWithSentinel)
          ? this.channel
          : channel as String?,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>?,
      delivery: identical(delivery, _copyWithSentinel)
          ? this.delivery
          : delivery as String?,
    );
  }
}

class _StemBroadcastMessagePartialCopyWithSentinel {
  const _StemBroadcastMessagePartialCopyWithSentinel();
}

/// Generated tracked model class for [StemBroadcastMessage].
///
/// This class extends the user-defined [StemBroadcastMessage] model and adds
/// attribute tracking, change detection, and relationship management.
/// Instances of this class are returned by queries and repositories.
///
/// **Do not instantiate this class directly.** Use queries, repositories,
/// or model factories to create tracked model instances.
class $StemBroadcastMessage extends StemBroadcastMessage
    with ModelAttributes, TimestampsTZImpl
    implements OrmEntity {
  /// Internal constructor for [$StemBroadcastMessage].
  $StemBroadcastMessage({
    required String id,
    required String namespace,
    required String channel,
    required Map<String, Object?> envelope,
    required String delivery,
  }) : super(
         id: id,
         namespace: namespace,
         channel: channel,
         envelope: envelope,
         delivery: delivery,
       ) {
    _attachOrmRuntimeMetadata({
      'id': id,
      'namespace': namespace,
      'channel': channel,
      'envelope': envelope,
      'delivery': delivery,
    });
  }

  /// Creates a tracked model instance from a user-defined model instance.
  factory $StemBroadcastMessage.fromModel(StemBroadcastMessage model) {
    return $StemBroadcastMessage(
      id: model.id,
      namespace: model.namespace,
      channel: model.channel,
      envelope: model.envelope,
      delivery: model.delivery,
    );
  }

  $StemBroadcastMessage copyWith({
    String? id,
    String? namespace,
    String? channel,
    Map<String, Object?>? envelope,
    String? delivery,
  }) {
    return $StemBroadcastMessage(
      id: id ?? this.id,
      namespace: namespace ?? this.namespace,
      channel: channel ?? this.channel,
      envelope: envelope ?? this.envelope,
      delivery: delivery ?? this.delivery,
    );
  }

  /// Builds a tracked model from a column/value map.
  static $StemBroadcastMessage fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemBroadcastMessageDefinition.fromMap(data, registry: registry);

  /// Converts this tracked model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemBroadcastMessageDefinition.toMap(this, registry: registry);

  /// Tracked getter for [id].
  @override
  String get id => getAttribute<String>('id') ?? super.id;

  /// Tracked setter for [id].
  set id(String value) => setAttribute('id', value);

  /// Tracked getter for [namespace].
  @override
  String get namespace => getAttribute<String>('namespace') ?? super.namespace;

  /// Tracked setter for [namespace].
  set namespace(String value) => setAttribute('namespace', value);

  /// Tracked getter for [channel].
  @override
  String get channel => getAttribute<String>('channel') ?? super.channel;

  /// Tracked setter for [channel].
  set channel(String value) => setAttribute('channel', value);

  /// Tracked getter for [envelope].
  @override
  Map<String, Object?> get envelope =>
      getAttribute<Map<String, Object?>>('envelope') ?? super.envelope;

  /// Tracked setter for [envelope].
  set envelope(Map<String, Object?> value) => setAttribute('envelope', value);

  /// Tracked getter for [delivery].
  @override
  String get delivery => getAttribute<String>('delivery') ?? super.delivery;

  /// Tracked setter for [delivery].
  set delivery(String value) => setAttribute('delivery', value);

  void _attachOrmRuntimeMetadata(Map<String, Object?> values) {
    replaceAttributes(values);
    attachModelDefinition(_$StemBroadcastMessageDefinition);
  }
}

class _StemBroadcastMessageCopyWithSentinel {
  const _StemBroadcastMessageCopyWithSentinel();
}

extension StemBroadcastMessageOrmExtension on StemBroadcastMessage {
  static const _StemBroadcastMessageCopyWithSentinel _copyWithSentinel =
      _StemBroadcastMessageCopyWithSentinel();
  StemBroadcastMessage copyWith({
    Object? id = _copyWithSentinel,
    Object? namespace = _copyWithSentinel,
    Object? channel = _copyWithSentinel,
    Object? envelope = _copyWithSentinel,
    Object? delivery = _copyWithSentinel,
  }) {
    return StemBroadcastMessage(
      id: identical(id, _copyWithSentinel) ? this.id : id as String,
      namespace: identical(namespace, _copyWithSentinel)
          ? this.namespace
          : namespace as String,
      channel: identical(channel, _copyWithSentinel)
          ? this.channel
          : channel as String,
      envelope: identical(envelope, _copyWithSentinel)
          ? this.envelope
          : envelope as Map<String, Object?>,
      delivery: identical(delivery, _copyWithSentinel)
          ? this.delivery
          : delivery as String,
    );
  }

  /// Converts this model to a column/value map.
  Map<String, Object?> toMap({ValueCodecRegistry? registry}) =>
      _$StemBroadcastMessageDefinition.toMap(this, registry: registry);

  /// Builds a model from a column/value map.
  static StemBroadcastMessage fromMap(
    Map<String, Object?> data, {
    ValueCodecRegistry? registry,
  }) => _$StemBroadcastMessageDefinition.fromMap(data, registry: registry);

  /// The Type of the generated ORM-managed model class.
  /// Use this when you need to specify the tracked model type explicitly,
  /// for example in generic type parameters.
  static Type get trackedType => $StemBroadcastMessage;

  /// Converts this immutable model to a tracked ORM-managed model.
  /// The tracked model supports attribute tracking, change detection,
  /// and persistence operations like save() and touch().
  $StemBroadcastMessage toTracked() {
    return $StemBroadcastMessage.fromModel(this);
  }
}

extension StemBroadcastMessagePredicateFields
    on PredicateBuilder<StemBroadcastMessage> {
  PredicateField<StemBroadcastMessage, String> get id =>
      PredicateField<StemBroadcastMessage, String>(this, 'id');
  PredicateField<StemBroadcastMessage, String> get namespace =>
      PredicateField<StemBroadcastMessage, String>(this, 'namespace');
  PredicateField<StemBroadcastMessage, String> get channel =>
      PredicateField<StemBroadcastMessage, String>(this, 'channel');
  PredicateField<StemBroadcastMessage, Map<String, Object?>> get envelope =>
      PredicateField<StemBroadcastMessage, Map<String, Object?>>(
        this,
        'envelope',
      );
  PredicateField<StemBroadcastMessage, String> get delivery =>
      PredicateField<StemBroadcastMessage, String>(this, 'delivery');
}

void registerStemBroadcastMessageEventHandlers(EventBus bus) {
  // No event handlers registered for StemBroadcastMessage.
}
