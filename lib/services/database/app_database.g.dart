// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DiaryEntriesTable extends DiaryEntries
    with TableInfo<$DiaryEntriesTable, DiaryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderPathMeta = const VerificationMeta(
    'folderPath',
  );
  @override
  late final GeneratedColumn<String> folderPath = GeneratedColumn<String>(
    'folder_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tosKeyMeta = const VerificationMeta('tosKey');
  @override
  late final GeneratedColumn<String> tosKey = GeneratedColumn<String>(
    'tos_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioFormatMeta = const VerificationMeta(
    'audioFormat',
  );
  @override
  late final GeneratedColumn<String> audioFormat = GeneratedColumn<String>(
    'audio_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('wav'),
  );
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<int> uploadedAt = GeneratedColumn<int>(
    'uploaded_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<WeatherCondition?, String>
  weatherCondition =
      GeneratedColumn<String>(
        'weather_condition',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      ).withConverter<WeatherCondition?>(
        $DiaryEntriesTable.$converterweatherCondition,
      );
  static const VerificationMeta _weatherIconMeta = const VerificationMeta(
    'weatherIcon',
  );
  @override
  late final GeneratedColumn<String> weatherIcon = GeneratedColumn<String>(
    'weather_icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weatherTextMeta = const VerificationMeta(
    'weatherText',
  );
  @override
  late final GeneratedColumn<String> weatherText = GeneratedColumn<String>(
    'weather_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<String> temperature = GeneratedColumn<String>(
    'temperature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationNameMeta = const VerificationMeta(
    'locationName',
  );
  @override
  late final GeneratedColumn<String> locationName = GeneratedColumn<String>(
    'location_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationLatMeta = const VerificationMeta(
    'locationLat',
  );
  @override
  late final GeneratedColumn<double> locationLat = GeneratedColumn<double>(
    'location_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationLonMeta = const VerificationMeta(
    'locationLon',
  );
  @override
  late final GeneratedColumn<double> locationLon = GeneratedColumn<double>(
    'location_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('completed'),
  );
  static const VerificationMeta _processingStageMeta = const VerificationMeta(
    'processingStage',
  );
  @override
  late final GeneratedColumn<String> processingStage = GeneratedColumn<String>(
    'processing_stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('uploading'),
  );
  static const VerificationMeta _asrTaskIdMeta = const VerificationMeta(
    'asrTaskId',
  );
  @override
  late final GeneratedColumn<String> asrTaskId = GeneratedColumn<String>(
    'asr_task_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    folderPath,
    durationSeconds,
    createdAt,
    tosKey,
    audioFormat,
    uploadedAt,
    weatherCondition,
    weatherIcon,
    weatherText,
    temperature,
    locationName,
    locationLat,
    locationLon,
    status,
    processingStage,
    asrTaskId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('folder_path')) {
      context.handle(
        _folderPathMeta,
        folderPath.isAcceptableOrUnknown(data['folder_path']!, _folderPathMeta),
      );
    } else if (isInserting) {
      context.missing(_folderPathMeta);
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationSecondsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('tos_key')) {
      context.handle(
        _tosKeyMeta,
        tosKey.isAcceptableOrUnknown(data['tos_key']!, _tosKeyMeta),
      );
    }
    if (data.containsKey('audio_format')) {
      context.handle(
        _audioFormatMeta,
        audioFormat.isAcceptableOrUnknown(
          data['audio_format']!,
          _audioFormatMeta,
        ),
      );
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    }
    if (data.containsKey('weather_icon')) {
      context.handle(
        _weatherIconMeta,
        weatherIcon.isAcceptableOrUnknown(
          data['weather_icon']!,
          _weatherIconMeta,
        ),
      );
    }
    if (data.containsKey('weather_text')) {
      context.handle(
        _weatherTextMeta,
        weatherText.isAcceptableOrUnknown(
          data['weather_text']!,
          _weatherTextMeta,
        ),
      );
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    }
    if (data.containsKey('location_name')) {
      context.handle(
        _locationNameMeta,
        locationName.isAcceptableOrUnknown(
          data['location_name']!,
          _locationNameMeta,
        ),
      );
    }
    if (data.containsKey('location_lat')) {
      context.handle(
        _locationLatMeta,
        locationLat.isAcceptableOrUnknown(
          data['location_lat']!,
          _locationLatMeta,
        ),
      );
    }
    if (data.containsKey('location_lon')) {
      context.handle(
        _locationLonMeta,
        locationLon.isAcceptableOrUnknown(
          data['location_lon']!,
          _locationLonMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('processing_stage')) {
      context.handle(
        _processingStageMeta,
        processingStage.isAcceptableOrUnknown(
          data['processing_stage']!,
          _processingStageMeta,
        ),
      );
    }
    if (data.containsKey('asr_task_id')) {
      context.handle(
        _asrTaskIdMeta,
        asrTaskId.isAcceptableOrUnknown(data['asr_task_id']!, _asrTaskIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiaryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      folderPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_path'],
      )!,
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      tosKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tos_key'],
      ),
      audioFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_format'],
      )!,
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded_at'],
      ),
      weatherCondition: $DiaryEntriesTable.$converterweatherCondition.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}weather_condition'],
        ),
      ),
      weatherIcon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weather_icon'],
      ),
      weatherText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weather_text'],
      ),
      temperature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temperature'],
      ),
      locationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_name'],
      ),
      locationLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_lat'],
      ),
      locationLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_lon'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      processingStage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_stage'],
      )!,
      asrTaskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asr_task_id'],
      ),
    );
  }

  @override
  $DiaryEntriesTable createAlias(String alias) {
    return $DiaryEntriesTable(attachedDatabase, alias);
  }

  static TypeConverter<WeatherCondition?, String?> $converterweatherCondition =
      const NullableWeatherConditionConverter();
}

class DiaryEntry extends DataClass implements Insertable<DiaryEntry> {
  final String id;
  final String title;
  final String folderPath;
  final int durationSeconds;
  final int createdAt;
  final String? tosKey;
  final String audioFormat;
  final int? uploadedAt;
  final WeatherCondition? weatherCondition;
  final String? weatherIcon;
  final String? weatherText;
  final String? temperature;
  final String? locationName;
  final double? locationLat;
  final double? locationLon;
  final String status;
  final String processingStage;
  final String? asrTaskId;
  const DiaryEntry({
    required this.id,
    required this.title,
    required this.folderPath,
    required this.durationSeconds,
    required this.createdAt,
    this.tosKey,
    required this.audioFormat,
    this.uploadedAt,
    this.weatherCondition,
    this.weatherIcon,
    this.weatherText,
    this.temperature,
    this.locationName,
    this.locationLat,
    this.locationLon,
    required this.status,
    required this.processingStage,
    this.asrTaskId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['folder_path'] = Variable<String>(folderPath);
    map['duration_seconds'] = Variable<int>(durationSeconds);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || tosKey != null) {
      map['tos_key'] = Variable<String>(tosKey);
    }
    map['audio_format'] = Variable<String>(audioFormat);
    if (!nullToAbsent || uploadedAt != null) {
      map['uploaded_at'] = Variable<int>(uploadedAt);
    }
    if (!nullToAbsent || weatherCondition != null) {
      map['weather_condition'] = Variable<String>(
        $DiaryEntriesTable.$converterweatherCondition.toSql(weatherCondition),
      );
    }
    if (!nullToAbsent || weatherIcon != null) {
      map['weather_icon'] = Variable<String>(weatherIcon);
    }
    if (!nullToAbsent || weatherText != null) {
      map['weather_text'] = Variable<String>(weatherText);
    }
    if (!nullToAbsent || temperature != null) {
      map['temperature'] = Variable<String>(temperature);
    }
    if (!nullToAbsent || locationName != null) {
      map['location_name'] = Variable<String>(locationName);
    }
    if (!nullToAbsent || locationLat != null) {
      map['location_lat'] = Variable<double>(locationLat);
    }
    if (!nullToAbsent || locationLon != null) {
      map['location_lon'] = Variable<double>(locationLon);
    }
    map['status'] = Variable<String>(status);
    map['processing_stage'] = Variable<String>(processingStage);
    if (!nullToAbsent || asrTaskId != null) {
      map['asr_task_id'] = Variable<String>(asrTaskId);
    }
    return map;
  }

  DiaryEntriesCompanion toCompanion(bool nullToAbsent) {
    return DiaryEntriesCompanion(
      id: Value(id),
      title: Value(title),
      folderPath: Value(folderPath),
      durationSeconds: Value(durationSeconds),
      createdAt: Value(createdAt),
      tosKey: tosKey == null && nullToAbsent
          ? const Value.absent()
          : Value(tosKey),
      audioFormat: Value(audioFormat),
      uploadedAt: uploadedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(uploadedAt),
      weatherCondition: weatherCondition == null && nullToAbsent
          ? const Value.absent()
          : Value(weatherCondition),
      weatherIcon: weatherIcon == null && nullToAbsent
          ? const Value.absent()
          : Value(weatherIcon),
      weatherText: weatherText == null && nullToAbsent
          ? const Value.absent()
          : Value(weatherText),
      temperature: temperature == null && nullToAbsent
          ? const Value.absent()
          : Value(temperature),
      locationName: locationName == null && nullToAbsent
          ? const Value.absent()
          : Value(locationName),
      locationLat: locationLat == null && nullToAbsent
          ? const Value.absent()
          : Value(locationLat),
      locationLon: locationLon == null && nullToAbsent
          ? const Value.absent()
          : Value(locationLon),
      status: Value(status),
      processingStage: Value(processingStage),
      asrTaskId: asrTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(asrTaskId),
    );
  }

  factory DiaryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryEntry(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      folderPath: serializer.fromJson<String>(json['folderPath']),
      durationSeconds: serializer.fromJson<int>(json['durationSeconds']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      tosKey: serializer.fromJson<String?>(json['tosKey']),
      audioFormat: serializer.fromJson<String>(json['audioFormat']),
      uploadedAt: serializer.fromJson<int?>(json['uploadedAt']),
      weatherCondition: serializer.fromJson<WeatherCondition?>(
        json['weatherCondition'],
      ),
      weatherIcon: serializer.fromJson<String?>(json['weatherIcon']),
      weatherText: serializer.fromJson<String?>(json['weatherText']),
      temperature: serializer.fromJson<String?>(json['temperature']),
      locationName: serializer.fromJson<String?>(json['locationName']),
      locationLat: serializer.fromJson<double?>(json['locationLat']),
      locationLon: serializer.fromJson<double?>(json['locationLon']),
      status: serializer.fromJson<String>(json['status']),
      processingStage: serializer.fromJson<String>(json['processingStage']),
      asrTaskId: serializer.fromJson<String?>(json['asrTaskId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'folderPath': serializer.toJson<String>(folderPath),
      'durationSeconds': serializer.toJson<int>(durationSeconds),
      'createdAt': serializer.toJson<int>(createdAt),
      'tosKey': serializer.toJson<String?>(tosKey),
      'audioFormat': serializer.toJson<String>(audioFormat),
      'uploadedAt': serializer.toJson<int?>(uploadedAt),
      'weatherCondition': serializer.toJson<WeatherCondition?>(
        weatherCondition,
      ),
      'weatherIcon': serializer.toJson<String?>(weatherIcon),
      'weatherText': serializer.toJson<String?>(weatherText),
      'temperature': serializer.toJson<String?>(temperature),
      'locationName': serializer.toJson<String?>(locationName),
      'locationLat': serializer.toJson<double?>(locationLat),
      'locationLon': serializer.toJson<double?>(locationLon),
      'status': serializer.toJson<String>(status),
      'processingStage': serializer.toJson<String>(processingStage),
      'asrTaskId': serializer.toJson<String?>(asrTaskId),
    };
  }

  DiaryEntry copyWith({
    String? id,
    String? title,
    String? folderPath,
    int? durationSeconds,
    int? createdAt,
    Value<String?> tosKey = const Value.absent(),
    String? audioFormat,
    Value<int?> uploadedAt = const Value.absent(),
    Value<WeatherCondition?> weatherCondition = const Value.absent(),
    Value<String?> weatherIcon = const Value.absent(),
    Value<String?> weatherText = const Value.absent(),
    Value<String?> temperature = const Value.absent(),
    Value<String?> locationName = const Value.absent(),
    Value<double?> locationLat = const Value.absent(),
    Value<double?> locationLon = const Value.absent(),
    String? status,
    String? processingStage,
    Value<String?> asrTaskId = const Value.absent(),
  }) => DiaryEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    folderPath: folderPath ?? this.folderPath,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    createdAt: createdAt ?? this.createdAt,
    tosKey: tosKey.present ? tosKey.value : this.tosKey,
    audioFormat: audioFormat ?? this.audioFormat,
    uploadedAt: uploadedAt.present ? uploadedAt.value : this.uploadedAt,
    weatherCondition: weatherCondition.present
        ? weatherCondition.value
        : this.weatherCondition,
    weatherIcon: weatherIcon.present ? weatherIcon.value : this.weatherIcon,
    weatherText: weatherText.present ? weatherText.value : this.weatherText,
    temperature: temperature.present ? temperature.value : this.temperature,
    locationName: locationName.present ? locationName.value : this.locationName,
    locationLat: locationLat.present ? locationLat.value : this.locationLat,
    locationLon: locationLon.present ? locationLon.value : this.locationLon,
    status: status ?? this.status,
    processingStage: processingStage ?? this.processingStage,
    asrTaskId: asrTaskId.present ? asrTaskId.value : this.asrTaskId,
  );
  DiaryEntry copyWithCompanion(DiaryEntriesCompanion data) {
    return DiaryEntry(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      folderPath: data.folderPath.present
          ? data.folderPath.value
          : this.folderPath,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      tosKey: data.tosKey.present ? data.tosKey.value : this.tosKey,
      audioFormat: data.audioFormat.present
          ? data.audioFormat.value
          : this.audioFormat,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
      weatherCondition: data.weatherCondition.present
          ? data.weatherCondition.value
          : this.weatherCondition,
      weatherIcon: data.weatherIcon.present
          ? data.weatherIcon.value
          : this.weatherIcon,
      weatherText: data.weatherText.present
          ? data.weatherText.value
          : this.weatherText,
      temperature: data.temperature.present
          ? data.temperature.value
          : this.temperature,
      locationName: data.locationName.present
          ? data.locationName.value
          : this.locationName,
      locationLat: data.locationLat.present
          ? data.locationLat.value
          : this.locationLat,
      locationLon: data.locationLon.present
          ? data.locationLon.value
          : this.locationLon,
      status: data.status.present ? data.status.value : this.status,
      processingStage: data.processingStage.present
          ? data.processingStage.value
          : this.processingStage,
      asrTaskId: data.asrTaskId.present ? data.asrTaskId.value : this.asrTaskId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntry(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderPath: $folderPath, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('tosKey: $tosKey, ')
          ..write('audioFormat: $audioFormat, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('weatherCondition: $weatherCondition, ')
          ..write('weatherIcon: $weatherIcon, ')
          ..write('weatherText: $weatherText, ')
          ..write('temperature: $temperature, ')
          ..write('locationName: $locationName, ')
          ..write('locationLat: $locationLat, ')
          ..write('locationLon: $locationLon, ')
          ..write('status: $status, ')
          ..write('processingStage: $processingStage, ')
          ..write('asrTaskId: $asrTaskId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    folderPath,
    durationSeconds,
    createdAt,
    tosKey,
    audioFormat,
    uploadedAt,
    weatherCondition,
    weatherIcon,
    weatherText,
    temperature,
    locationName,
    locationLat,
    locationLon,
    status,
    processingStage,
    asrTaskId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryEntry &&
          other.id == this.id &&
          other.title == this.title &&
          other.folderPath == this.folderPath &&
          other.durationSeconds == this.durationSeconds &&
          other.createdAt == this.createdAt &&
          other.tosKey == this.tosKey &&
          other.audioFormat == this.audioFormat &&
          other.uploadedAt == this.uploadedAt &&
          other.weatherCondition == this.weatherCondition &&
          other.weatherIcon == this.weatherIcon &&
          other.weatherText == this.weatherText &&
          other.temperature == this.temperature &&
          other.locationName == this.locationName &&
          other.locationLat == this.locationLat &&
          other.locationLon == this.locationLon &&
          other.status == this.status &&
          other.processingStage == this.processingStage &&
          other.asrTaskId == this.asrTaskId);
}

class DiaryEntriesCompanion extends UpdateCompanion<DiaryEntry> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> folderPath;
  final Value<int> durationSeconds;
  final Value<int> createdAt;
  final Value<String?> tosKey;
  final Value<String> audioFormat;
  final Value<int?> uploadedAt;
  final Value<WeatherCondition?> weatherCondition;
  final Value<String?> weatherIcon;
  final Value<String?> weatherText;
  final Value<String?> temperature;
  final Value<String?> locationName;
  final Value<double?> locationLat;
  final Value<double?> locationLon;
  final Value<String> status;
  final Value<String> processingStage;
  final Value<String?> asrTaskId;
  final Value<int> rowid;
  const DiaryEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.folderPath = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.tosKey = const Value.absent(),
    this.audioFormat = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.weatherCondition = const Value.absent(),
    this.weatherIcon = const Value.absent(),
    this.weatherText = const Value.absent(),
    this.temperature = const Value.absent(),
    this.locationName = const Value.absent(),
    this.locationLat = const Value.absent(),
    this.locationLon = const Value.absent(),
    this.status = const Value.absent(),
    this.processingStage = const Value.absent(),
    this.asrTaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiaryEntriesCompanion.insert({
    required String id,
    required String title,
    required String folderPath,
    required int durationSeconds,
    required int createdAt,
    this.tosKey = const Value.absent(),
    this.audioFormat = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.weatherCondition = const Value.absent(),
    this.weatherIcon = const Value.absent(),
    this.weatherText = const Value.absent(),
    this.temperature = const Value.absent(),
    this.locationName = const Value.absent(),
    this.locationLat = const Value.absent(),
    this.locationLon = const Value.absent(),
    this.status = const Value.absent(),
    this.processingStage = const Value.absent(),
    this.asrTaskId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       folderPath = Value(folderPath),
       durationSeconds = Value(durationSeconds),
       createdAt = Value(createdAt);
  static Insertable<DiaryEntry> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? folderPath,
    Expression<int>? durationSeconds,
    Expression<int>? createdAt,
    Expression<String>? tosKey,
    Expression<String>? audioFormat,
    Expression<int>? uploadedAt,
    Expression<String>? weatherCondition,
    Expression<String>? weatherIcon,
    Expression<String>? weatherText,
    Expression<String>? temperature,
    Expression<String>? locationName,
    Expression<double>? locationLat,
    Expression<double>? locationLon,
    Expression<String>? status,
    Expression<String>? processingStage,
    Expression<String>? asrTaskId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (folderPath != null) 'folder_path': folderPath,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (createdAt != null) 'created_at': createdAt,
      if (tosKey != null) 'tos_key': tosKey,
      if (audioFormat != null) 'audio_format': audioFormat,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (weatherCondition != null) 'weather_condition': weatherCondition,
      if (weatherIcon != null) 'weather_icon': weatherIcon,
      if (weatherText != null) 'weather_text': weatherText,
      if (temperature != null) 'temperature': temperature,
      if (locationName != null) 'location_name': locationName,
      if (locationLat != null) 'location_lat': locationLat,
      if (locationLon != null) 'location_lon': locationLon,
      if (status != null) 'status': status,
      if (processingStage != null) 'processing_stage': processingStage,
      if (asrTaskId != null) 'asr_task_id': asrTaskId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiaryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? folderPath,
    Value<int>? durationSeconds,
    Value<int>? createdAt,
    Value<String?>? tosKey,
    Value<String>? audioFormat,
    Value<int?>? uploadedAt,
    Value<WeatherCondition?>? weatherCondition,
    Value<String?>? weatherIcon,
    Value<String?>? weatherText,
    Value<String?>? temperature,
    Value<String?>? locationName,
    Value<double?>? locationLat,
    Value<double?>? locationLon,
    Value<String>? status,
    Value<String>? processingStage,
    Value<String?>? asrTaskId,
    Value<int>? rowid,
  }) {
    return DiaryEntriesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      folderPath: folderPath ?? this.folderPath,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      tosKey: tosKey ?? this.tosKey,
      audioFormat: audioFormat ?? this.audioFormat,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      weatherCondition: weatherCondition ?? this.weatherCondition,
      weatherIcon: weatherIcon ?? this.weatherIcon,
      weatherText: weatherText ?? this.weatherText,
      temperature: temperature ?? this.temperature,
      locationName: locationName ?? this.locationName,
      locationLat: locationLat ?? this.locationLat,
      locationLon: locationLon ?? this.locationLon,
      status: status ?? this.status,
      processingStage: processingStage ?? this.processingStage,
      asrTaskId: asrTaskId ?? this.asrTaskId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (folderPath.present) {
      map['folder_path'] = Variable<String>(folderPath.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (tosKey.present) {
      map['tos_key'] = Variable<String>(tosKey.value);
    }
    if (audioFormat.present) {
      map['audio_format'] = Variable<String>(audioFormat.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<int>(uploadedAt.value);
    }
    if (weatherCondition.present) {
      map['weather_condition'] = Variable<String>(
        $DiaryEntriesTable.$converterweatherCondition.toSql(
          weatherCondition.value,
        ),
      );
    }
    if (weatherIcon.present) {
      map['weather_icon'] = Variable<String>(weatherIcon.value);
    }
    if (weatherText.present) {
      map['weather_text'] = Variable<String>(weatherText.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<String>(temperature.value);
    }
    if (locationName.present) {
      map['location_name'] = Variable<String>(locationName.value);
    }
    if (locationLat.present) {
      map['location_lat'] = Variable<double>(locationLat.value);
    }
    if (locationLon.present) {
      map['location_lon'] = Variable<double>(locationLon.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (processingStage.present) {
      map['processing_stage'] = Variable<String>(processingStage.value);
    }
    if (asrTaskId.present) {
      map['asr_task_id'] = Variable<String>(asrTaskId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('folderPath: $folderPath, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('createdAt: $createdAt, ')
          ..write('tosKey: $tosKey, ')
          ..write('audioFormat: $audioFormat, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('weatherCondition: $weatherCondition, ')
          ..write('weatherIcon: $weatherIcon, ')
          ..write('weatherText: $weatherText, ')
          ..write('temperature: $temperature, ')
          ..write('locationName: $locationName, ')
          ..write('locationLat: $locationLat, ')
          ..write('locationLon: $locationLon, ')
          ..write('status: $status, ')
          ..write('processingStage: $processingStage, ')
          ..write('asrTaskId: $asrTaskId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matchPromptMeta = const VerificationMeta(
    'matchPrompt',
  );
  @override
  late final GeneratedColumn<String> matchPrompt = GeneratedColumn<String>(
    'match_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    matchPrompt,
    color,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('match_prompt')) {
      context.handle(
        _matchPromptMeta,
        matchPrompt.isAcceptableOrUnknown(
          data['match_prompt']!,
          _matchPromptMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {name},
  ];
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      matchPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}match_prompt'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final String id;
  final String name;
  final String matchPrompt;
  final String? color;
  final int createdAt;
  const Tag({
    required this.id,
    required this.name,
    required this.matchPrompt,
    this.color,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['match_prompt'] = Variable<String>(matchPrompt);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      matchPrompt: Value(matchPrompt),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      createdAt: Value(createdAt),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      matchPrompt: serializer.fromJson<String>(json['matchPrompt']),
      color: serializer.fromJson<String?>(json['color']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'matchPrompt': serializer.toJson<String>(matchPrompt),
      'color': serializer.toJson<String?>(color),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Tag copyWith({
    String? id,
    String? name,
    String? matchPrompt,
    Value<String?> color = const Value.absent(),
    int? createdAt,
  }) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    matchPrompt: matchPrompt ?? this.matchPrompt,
    color: color.present ? color.value : this.color,
    createdAt: createdAt ?? this.createdAt,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      matchPrompt: data.matchPrompt.present
          ? data.matchPrompt.value
          : this.matchPrompt,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('matchPrompt: $matchPrompt, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, matchPrompt, color, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.matchPrompt == this.matchPrompt &&
          other.color == this.color &&
          other.createdAt == this.createdAt);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> matchPrompt;
  final Value<String?> color;
  final Value<int> createdAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.matchPrompt = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    this.matchPrompt = const Value.absent(),
    this.color = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<Tag> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? matchPrompt,
    Expression<String>? color,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (matchPrompt != null) 'match_prompt': matchPrompt,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? matchPrompt,
    Value<String?>? color,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      matchPrompt: matchPrompt ?? this.matchPrompt,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (matchPrompt.present) {
      map['match_prompt'] = Variable<String>(matchPrompt.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('matchPrompt: $matchPrompt, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiaryTagRelationsTable extends DiaryTagRelations
    with TableInfo<$DiaryTagRelationsTable, DiaryTagRelation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiaryTagRelationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _diaryIdMeta = const VerificationMeta(
    'diaryId',
  );
  @override
  late final GeneratedColumn<String> diaryId = GeneratedColumn<String>(
    'diary_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES diary_entries (id)',
    ),
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES tags (id)',
    ),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [diaryId, tagId, source, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diary_tag_relations';
  @override
  VerificationContext validateIntegrity(
    Insertable<DiaryTagRelation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('diary_id')) {
      context.handle(
        _diaryIdMeta,
        diaryId.isAcceptableOrUnknown(data['diary_id']!, _diaryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diaryIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {diaryId, tagId};
  @override
  DiaryTagRelation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiaryTagRelation(
      diaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diary_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DiaryTagRelationsTable createAlias(String alias) {
    return $DiaryTagRelationsTable(attachedDatabase, alias);
  }
}

class DiaryTagRelation extends DataClass
    implements Insertable<DiaryTagRelation> {
  final String diaryId;
  final String tagId;
  final String source;
  final int createdAt;
  const DiaryTagRelation({
    required this.diaryId,
    required this.tagId,
    required this.source,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['diary_id'] = Variable<String>(diaryId);
    map['tag_id'] = Variable<String>(tagId);
    map['source'] = Variable<String>(source);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  DiaryTagRelationsCompanion toCompanion(bool nullToAbsent) {
    return DiaryTagRelationsCompanion(
      diaryId: Value(diaryId),
      tagId: Value(tagId),
      source: Value(source),
      createdAt: Value(createdAt),
    );
  }

  factory DiaryTagRelation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiaryTagRelation(
      diaryId: serializer.fromJson<String>(json['diaryId']),
      tagId: serializer.fromJson<String>(json['tagId']),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'diaryId': serializer.toJson<String>(diaryId),
      'tagId': serializer.toJson<String>(tagId),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  DiaryTagRelation copyWith({
    String? diaryId,
    String? tagId,
    String? source,
    int? createdAt,
  }) => DiaryTagRelation(
    diaryId: diaryId ?? this.diaryId,
    tagId: tagId ?? this.tagId,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
  );
  DiaryTagRelation copyWithCompanion(DiaryTagRelationsCompanion data) {
    return DiaryTagRelation(
      diaryId: data.diaryId.present ? data.diaryId.value : this.diaryId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiaryTagRelation(')
          ..write('diaryId: $diaryId, ')
          ..write('tagId: $tagId, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(diaryId, tagId, source, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiaryTagRelation &&
          other.diaryId == this.diaryId &&
          other.tagId == this.tagId &&
          other.source == this.source &&
          other.createdAt == this.createdAt);
}

class DiaryTagRelationsCompanion extends UpdateCompanion<DiaryTagRelation> {
  final Value<String> diaryId;
  final Value<String> tagId;
  final Value<String> source;
  final Value<int> createdAt;
  final Value<int> rowid;
  const DiaryTagRelationsCompanion({
    this.diaryId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiaryTagRelationsCompanion.insert({
    required String diaryId,
    required String tagId,
    this.source = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : diaryId = Value(diaryId),
       tagId = Value(tagId),
       createdAt = Value(createdAt);
  static Insertable<DiaryTagRelation> custom({
    Expression<String>? diaryId,
    Expression<String>? tagId,
    Expression<String>? source,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (diaryId != null) 'diary_id': diaryId,
      if (tagId != null) 'tag_id': tagId,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiaryTagRelationsCompanion copyWith({
    Value<String>? diaryId,
    Value<String>? tagId,
    Value<String>? source,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return DiaryTagRelationsCompanion(
      diaryId: diaryId ?? this.diaryId,
      tagId: tagId ?? this.tagId,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (diaryId.present) {
      map['diary_id'] = Variable<String>(diaryId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiaryTagRelationsCompanion(')
          ..write('diaryId: $diaryId, ')
          ..write('tagId: $tagId, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ApiLogsTable extends ApiLogs with TableInfo<$ApiLogsTable, ApiLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ApiLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _diaryIdMeta = const VerificationMeta(
    'diaryId',
  );
  @override
  late final GeneratedColumn<String> diaryId = GeneratedColumn<String>(
    'diary_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiTypeMeta = const VerificationMeta(
    'apiType',
  );
  @override
  late final GeneratedColumn<String> apiType = GeneratedColumn<String>(
    'api_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<String> step = GeneratedColumn<String>(
    'step',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _responseSummaryMeta = const VerificationMeta(
    'responseSummary',
  );
  @override
  late final GeneratedColumn<String> responseSummary = GeneratedColumn<String>(
    'response_summary',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptTokensMeta = const VerificationMeta(
    'promptTokens',
  );
  @override
  late final GeneratedColumn<int> promptTokens = GeneratedColumn<int>(
    'prompt_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completionTokensMeta = const VerificationMeta(
    'completionTokens',
  );
  @override
  late final GeneratedColumn<int> completionTokens = GeneratedColumn<int>(
    'completion_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalTokensMeta = const VerificationMeta(
    'totalTokens',
  );
  @override
  late final GeneratedColumn<int> totalTokens = GeneratedColumn<int>(
    'total_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cachedTokensMeta = const VerificationMeta(
    'cachedTokens',
  );
  @override
  late final GeneratedColumn<int> cachedTokens = GeneratedColumn<int>(
    'cached_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasoningTokensMeta = const VerificationMeta(
    'reasoningTokens',
  );
  @override
  late final GeneratedColumn<int> reasoningTokens = GeneratedColumn<int>(
    'reasoning_tokens',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _audioDurationSecondsMeta =
      const VerificationMeta('audioDurationSeconds');
  @override
  late final GeneratedColumn<int> audioDurationSeconds = GeneratedColumn<int>(
    'audio_duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ttsCharacterCountMeta = const VerificationMeta(
    'ttsCharacterCount',
  );
  @override
  late final GeneratedColumn<int> ttsCharacterCount = GeneratedColumn<int>(
    'tts_character_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _estimatedCostMeta = const VerificationMeta(
    'estimatedCost',
  );
  @override
  late final GeneratedColumn<double> estimatedCost = GeneratedColumn<double>(
    'estimated_cost',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    diaryId,
    apiType,
    step,
    status,
    durationMs,
    errorMessage,
    responseSummary,
    promptTokens,
    completionTokens,
    totalTokens,
    cachedTokens,
    reasoningTokens,
    audioDurationSeconds,
    ttsCharacterCount,
    estimatedCost,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'api_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ApiLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('diary_id')) {
      context.handle(
        _diaryIdMeta,
        diaryId.isAcceptableOrUnknown(data['diary_id']!, _diaryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_diaryIdMeta);
    }
    if (data.containsKey('api_type')) {
      context.handle(
        _apiTypeMeta,
        apiType.isAcceptableOrUnknown(data['api_type']!, _apiTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_apiTypeMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    } else if (isInserting) {
      context.missing(_stepMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('response_summary')) {
      context.handle(
        _responseSummaryMeta,
        responseSummary.isAcceptableOrUnknown(
          data['response_summary']!,
          _responseSummaryMeta,
        ),
      );
    }
    if (data.containsKey('prompt_tokens')) {
      context.handle(
        _promptTokensMeta,
        promptTokens.isAcceptableOrUnknown(
          data['prompt_tokens']!,
          _promptTokensMeta,
        ),
      );
    }
    if (data.containsKey('completion_tokens')) {
      context.handle(
        _completionTokensMeta,
        completionTokens.isAcceptableOrUnknown(
          data['completion_tokens']!,
          _completionTokensMeta,
        ),
      );
    }
    if (data.containsKey('total_tokens')) {
      context.handle(
        _totalTokensMeta,
        totalTokens.isAcceptableOrUnknown(
          data['total_tokens']!,
          _totalTokensMeta,
        ),
      );
    }
    if (data.containsKey('cached_tokens')) {
      context.handle(
        _cachedTokensMeta,
        cachedTokens.isAcceptableOrUnknown(
          data['cached_tokens']!,
          _cachedTokensMeta,
        ),
      );
    }
    if (data.containsKey('reasoning_tokens')) {
      context.handle(
        _reasoningTokensMeta,
        reasoningTokens.isAcceptableOrUnknown(
          data['reasoning_tokens']!,
          _reasoningTokensMeta,
        ),
      );
    }
    if (data.containsKey('audio_duration_seconds')) {
      context.handle(
        _audioDurationSecondsMeta,
        audioDurationSeconds.isAcceptableOrUnknown(
          data['audio_duration_seconds']!,
          _audioDurationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('tts_character_count')) {
      context.handle(
        _ttsCharacterCountMeta,
        ttsCharacterCount.isAcceptableOrUnknown(
          data['tts_character_count']!,
          _ttsCharacterCountMeta,
        ),
      );
    }
    if (data.containsKey('estimated_cost')) {
      context.handle(
        _estimatedCostMeta,
        estimatedCost.isAcceptableOrUnknown(
          data['estimated_cost']!,
          _estimatedCostMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ApiLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ApiLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      diaryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}diary_id'],
      )!,
      apiType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_type'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      responseSummary: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}response_summary'],
      ),
      promptTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prompt_tokens'],
      ),
      completionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion_tokens'],
      ),
      totalTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_tokens'],
      ),
      cachedTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_tokens'],
      ),
      reasoningTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reasoning_tokens'],
      ),
      audioDurationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_duration_seconds'],
      ),
      ttsCharacterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tts_character_count'],
      ),
      estimatedCost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}estimated_cost'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ApiLogsTable createAlias(String alias) {
    return $ApiLogsTable(attachedDatabase, alias);
  }
}

class ApiLog extends DataClass implements Insertable<ApiLog> {
  final String id;
  final String diaryId;
  final String apiType;
  final String step;
  final String status;
  final int? durationMs;
  final String? errorMessage;
  final String? responseSummary;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final int? cachedTokens;
  final int? reasoningTokens;
  final int? audioDurationSeconds;
  final int? ttsCharacterCount;
  final double? estimatedCost;
  final int createdAt;
  const ApiLog({
    required this.id,
    required this.diaryId,
    required this.apiType,
    required this.step,
    required this.status,
    this.durationMs,
    this.errorMessage,
    this.responseSummary,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.cachedTokens,
    this.reasoningTokens,
    this.audioDurationSeconds,
    this.ttsCharacterCount,
    this.estimatedCost,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['diary_id'] = Variable<String>(diaryId);
    map['api_type'] = Variable<String>(apiType);
    map['step'] = Variable<String>(step);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    if (!nullToAbsent || responseSummary != null) {
      map['response_summary'] = Variable<String>(responseSummary);
    }
    if (!nullToAbsent || promptTokens != null) {
      map['prompt_tokens'] = Variable<int>(promptTokens);
    }
    if (!nullToAbsent || completionTokens != null) {
      map['completion_tokens'] = Variable<int>(completionTokens);
    }
    if (!nullToAbsent || totalTokens != null) {
      map['total_tokens'] = Variable<int>(totalTokens);
    }
    if (!nullToAbsent || cachedTokens != null) {
      map['cached_tokens'] = Variable<int>(cachedTokens);
    }
    if (!nullToAbsent || reasoningTokens != null) {
      map['reasoning_tokens'] = Variable<int>(reasoningTokens);
    }
    if (!nullToAbsent || audioDurationSeconds != null) {
      map['audio_duration_seconds'] = Variable<int>(audioDurationSeconds);
    }
    if (!nullToAbsent || ttsCharacterCount != null) {
      map['tts_character_count'] = Variable<int>(ttsCharacterCount);
    }
    if (!nullToAbsent || estimatedCost != null) {
      map['estimated_cost'] = Variable<double>(estimatedCost);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ApiLogsCompanion toCompanion(bool nullToAbsent) {
    return ApiLogsCompanion(
      id: Value(id),
      diaryId: Value(diaryId),
      apiType: Value(apiType),
      step: Value(step),
      status: Value(status),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      responseSummary: responseSummary == null && nullToAbsent
          ? const Value.absent()
          : Value(responseSummary),
      promptTokens: promptTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(promptTokens),
      completionTokens: completionTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(completionTokens),
      totalTokens: totalTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(totalTokens),
      cachedTokens: cachedTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(cachedTokens),
      reasoningTokens: reasoningTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoningTokens),
      audioDurationSeconds: audioDurationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(audioDurationSeconds),
      ttsCharacterCount: ttsCharacterCount == null && nullToAbsent
          ? const Value.absent()
          : Value(ttsCharacterCount),
      estimatedCost: estimatedCost == null && nullToAbsent
          ? const Value.absent()
          : Value(estimatedCost),
      createdAt: Value(createdAt),
    );
  }

  factory ApiLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ApiLog(
      id: serializer.fromJson<String>(json['id']),
      diaryId: serializer.fromJson<String>(json['diaryId']),
      apiType: serializer.fromJson<String>(json['apiType']),
      step: serializer.fromJson<String>(json['step']),
      status: serializer.fromJson<String>(json['status']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      responseSummary: serializer.fromJson<String?>(json['responseSummary']),
      promptTokens: serializer.fromJson<int?>(json['promptTokens']),
      completionTokens: serializer.fromJson<int?>(json['completionTokens']),
      totalTokens: serializer.fromJson<int?>(json['totalTokens']),
      cachedTokens: serializer.fromJson<int?>(json['cachedTokens']),
      reasoningTokens: serializer.fromJson<int?>(json['reasoningTokens']),
      audioDurationSeconds: serializer.fromJson<int?>(
        json['audioDurationSeconds'],
      ),
      ttsCharacterCount: serializer.fromJson<int?>(json['ttsCharacterCount']),
      estimatedCost: serializer.fromJson<double?>(json['estimatedCost']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'diaryId': serializer.toJson<String>(diaryId),
      'apiType': serializer.toJson<String>(apiType),
      'step': serializer.toJson<String>(step),
      'status': serializer.toJson<String>(status),
      'durationMs': serializer.toJson<int?>(durationMs),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'responseSummary': serializer.toJson<String?>(responseSummary),
      'promptTokens': serializer.toJson<int?>(promptTokens),
      'completionTokens': serializer.toJson<int?>(completionTokens),
      'totalTokens': serializer.toJson<int?>(totalTokens),
      'cachedTokens': serializer.toJson<int?>(cachedTokens),
      'reasoningTokens': serializer.toJson<int?>(reasoningTokens),
      'audioDurationSeconds': serializer.toJson<int?>(audioDurationSeconds),
      'ttsCharacterCount': serializer.toJson<int?>(ttsCharacterCount),
      'estimatedCost': serializer.toJson<double?>(estimatedCost),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ApiLog copyWith({
    String? id,
    String? diaryId,
    String? apiType,
    String? step,
    String? status,
    Value<int?> durationMs = const Value.absent(),
    Value<String?> errorMessage = const Value.absent(),
    Value<String?> responseSummary = const Value.absent(),
    Value<int?> promptTokens = const Value.absent(),
    Value<int?> completionTokens = const Value.absent(),
    Value<int?> totalTokens = const Value.absent(),
    Value<int?> cachedTokens = const Value.absent(),
    Value<int?> reasoningTokens = const Value.absent(),
    Value<int?> audioDurationSeconds = const Value.absent(),
    Value<int?> ttsCharacterCount = const Value.absent(),
    Value<double?> estimatedCost = const Value.absent(),
    int? createdAt,
  }) => ApiLog(
    id: id ?? this.id,
    diaryId: diaryId ?? this.diaryId,
    apiType: apiType ?? this.apiType,
    step: step ?? this.step,
    status: status ?? this.status,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    responseSummary: responseSummary.present
        ? responseSummary.value
        : this.responseSummary,
    promptTokens: promptTokens.present ? promptTokens.value : this.promptTokens,
    completionTokens: completionTokens.present
        ? completionTokens.value
        : this.completionTokens,
    totalTokens: totalTokens.present ? totalTokens.value : this.totalTokens,
    cachedTokens: cachedTokens.present ? cachedTokens.value : this.cachedTokens,
    reasoningTokens: reasoningTokens.present
        ? reasoningTokens.value
        : this.reasoningTokens,
    audioDurationSeconds: audioDurationSeconds.present
        ? audioDurationSeconds.value
        : this.audioDurationSeconds,
    ttsCharacterCount: ttsCharacterCount.present
        ? ttsCharacterCount.value
        : this.ttsCharacterCount,
    estimatedCost: estimatedCost.present
        ? estimatedCost.value
        : this.estimatedCost,
    createdAt: createdAt ?? this.createdAt,
  );
  ApiLog copyWithCompanion(ApiLogsCompanion data) {
    return ApiLog(
      id: data.id.present ? data.id.value : this.id,
      diaryId: data.diaryId.present ? data.diaryId.value : this.diaryId,
      apiType: data.apiType.present ? data.apiType.value : this.apiType,
      step: data.step.present ? data.step.value : this.step,
      status: data.status.present ? data.status.value : this.status,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      responseSummary: data.responseSummary.present
          ? data.responseSummary.value
          : this.responseSummary,
      promptTokens: data.promptTokens.present
          ? data.promptTokens.value
          : this.promptTokens,
      completionTokens: data.completionTokens.present
          ? data.completionTokens.value
          : this.completionTokens,
      totalTokens: data.totalTokens.present
          ? data.totalTokens.value
          : this.totalTokens,
      cachedTokens: data.cachedTokens.present
          ? data.cachedTokens.value
          : this.cachedTokens,
      reasoningTokens: data.reasoningTokens.present
          ? data.reasoningTokens.value
          : this.reasoningTokens,
      audioDurationSeconds: data.audioDurationSeconds.present
          ? data.audioDurationSeconds.value
          : this.audioDurationSeconds,
      ttsCharacterCount: data.ttsCharacterCount.present
          ? data.ttsCharacterCount.value
          : this.ttsCharacterCount,
      estimatedCost: data.estimatedCost.present
          ? data.estimatedCost.value
          : this.estimatedCost,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ApiLog(')
          ..write('id: $id, ')
          ..write('diaryId: $diaryId, ')
          ..write('apiType: $apiType, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('responseSummary: $responseSummary, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('totalTokens: $totalTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('audioDurationSeconds: $audioDurationSeconds, ')
          ..write('ttsCharacterCount: $ttsCharacterCount, ')
          ..write('estimatedCost: $estimatedCost, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    diaryId,
    apiType,
    step,
    status,
    durationMs,
    errorMessage,
    responseSummary,
    promptTokens,
    completionTokens,
    totalTokens,
    cachedTokens,
    reasoningTokens,
    audioDurationSeconds,
    ttsCharacterCount,
    estimatedCost,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ApiLog &&
          other.id == this.id &&
          other.diaryId == this.diaryId &&
          other.apiType == this.apiType &&
          other.step == this.step &&
          other.status == this.status &&
          other.durationMs == this.durationMs &&
          other.errorMessage == this.errorMessage &&
          other.responseSummary == this.responseSummary &&
          other.promptTokens == this.promptTokens &&
          other.completionTokens == this.completionTokens &&
          other.totalTokens == this.totalTokens &&
          other.cachedTokens == this.cachedTokens &&
          other.reasoningTokens == this.reasoningTokens &&
          other.audioDurationSeconds == this.audioDurationSeconds &&
          other.ttsCharacterCount == this.ttsCharacterCount &&
          other.estimatedCost == this.estimatedCost &&
          other.createdAt == this.createdAt);
}

class ApiLogsCompanion extends UpdateCompanion<ApiLog> {
  final Value<String> id;
  final Value<String> diaryId;
  final Value<String> apiType;
  final Value<String> step;
  final Value<String> status;
  final Value<int?> durationMs;
  final Value<String?> errorMessage;
  final Value<String?> responseSummary;
  final Value<int?> promptTokens;
  final Value<int?> completionTokens;
  final Value<int?> totalTokens;
  final Value<int?> cachedTokens;
  final Value<int?> reasoningTokens;
  final Value<int?> audioDurationSeconds;
  final Value<int?> ttsCharacterCount;
  final Value<double?> estimatedCost;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ApiLogsCompanion({
    this.id = const Value.absent(),
    this.diaryId = const Value.absent(),
    this.apiType = const Value.absent(),
    this.step = const Value.absent(),
    this.status = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.responseSummary = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.totalTokens = const Value.absent(),
    this.cachedTokens = const Value.absent(),
    this.reasoningTokens = const Value.absent(),
    this.audioDurationSeconds = const Value.absent(),
    this.ttsCharacterCount = const Value.absent(),
    this.estimatedCost = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ApiLogsCompanion.insert({
    required String id,
    required String diaryId,
    required String apiType,
    required String step,
    required String status,
    this.durationMs = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.responseSummary = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.totalTokens = const Value.absent(),
    this.cachedTokens = const Value.absent(),
    this.reasoningTokens = const Value.absent(),
    this.audioDurationSeconds = const Value.absent(),
    this.ttsCharacterCount = const Value.absent(),
    this.estimatedCost = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       diaryId = Value(diaryId),
       apiType = Value(apiType),
       step = Value(step),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<ApiLog> custom({
    Expression<String>? id,
    Expression<String>? diaryId,
    Expression<String>? apiType,
    Expression<String>? step,
    Expression<String>? status,
    Expression<int>? durationMs,
    Expression<String>? errorMessage,
    Expression<String>? responseSummary,
    Expression<int>? promptTokens,
    Expression<int>? completionTokens,
    Expression<int>? totalTokens,
    Expression<int>? cachedTokens,
    Expression<int>? reasoningTokens,
    Expression<int>? audioDurationSeconds,
    Expression<int>? ttsCharacterCount,
    Expression<double>? estimatedCost,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (diaryId != null) 'diary_id': diaryId,
      if (apiType != null) 'api_type': apiType,
      if (step != null) 'step': step,
      if (status != null) 'status': status,
      if (durationMs != null) 'duration_ms': durationMs,
      if (errorMessage != null) 'error_message': errorMessage,
      if (responseSummary != null) 'response_summary': responseSummary,
      if (promptTokens != null) 'prompt_tokens': promptTokens,
      if (completionTokens != null) 'completion_tokens': completionTokens,
      if (totalTokens != null) 'total_tokens': totalTokens,
      if (cachedTokens != null) 'cached_tokens': cachedTokens,
      if (reasoningTokens != null) 'reasoning_tokens': reasoningTokens,
      if (audioDurationSeconds != null)
        'audio_duration_seconds': audioDurationSeconds,
      if (ttsCharacterCount != null) 'tts_character_count': ttsCharacterCount,
      if (estimatedCost != null) 'estimated_cost': estimatedCost,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ApiLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? diaryId,
    Value<String>? apiType,
    Value<String>? step,
    Value<String>? status,
    Value<int?>? durationMs,
    Value<String?>? errorMessage,
    Value<String?>? responseSummary,
    Value<int?>? promptTokens,
    Value<int?>? completionTokens,
    Value<int?>? totalTokens,
    Value<int?>? cachedTokens,
    Value<int?>? reasoningTokens,
    Value<int?>? audioDurationSeconds,
    Value<int?>? ttsCharacterCount,
    Value<double?>? estimatedCost,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ApiLogsCompanion(
      id: id ?? this.id,
      diaryId: diaryId ?? this.diaryId,
      apiType: apiType ?? this.apiType,
      step: step ?? this.step,
      status: status ?? this.status,
      durationMs: durationMs ?? this.durationMs,
      errorMessage: errorMessage ?? this.errorMessage,
      responseSummary: responseSummary ?? this.responseSummary,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      audioDurationSeconds: audioDurationSeconds ?? this.audioDurationSeconds,
      ttsCharacterCount: ttsCharacterCount ?? this.ttsCharacterCount,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (diaryId.present) {
      map['diary_id'] = Variable<String>(diaryId.value);
    }
    if (apiType.present) {
      map['api_type'] = Variable<String>(apiType.value);
    }
    if (step.present) {
      map['step'] = Variable<String>(step.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (responseSummary.present) {
      map['response_summary'] = Variable<String>(responseSummary.value);
    }
    if (promptTokens.present) {
      map['prompt_tokens'] = Variable<int>(promptTokens.value);
    }
    if (completionTokens.present) {
      map['completion_tokens'] = Variable<int>(completionTokens.value);
    }
    if (totalTokens.present) {
      map['total_tokens'] = Variable<int>(totalTokens.value);
    }
    if (cachedTokens.present) {
      map['cached_tokens'] = Variable<int>(cachedTokens.value);
    }
    if (reasoningTokens.present) {
      map['reasoning_tokens'] = Variable<int>(reasoningTokens.value);
    }
    if (audioDurationSeconds.present) {
      map['audio_duration_seconds'] = Variable<int>(audioDurationSeconds.value);
    }
    if (ttsCharacterCount.present) {
      map['tts_character_count'] = Variable<int>(ttsCharacterCount.value);
    }
    if (estimatedCost.present) {
      map['estimated_cost'] = Variable<double>(estimatedCost.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ApiLogsCompanion(')
          ..write('id: $id, ')
          ..write('diaryId: $diaryId, ')
          ..write('apiType: $apiType, ')
          ..write('step: $step, ')
          ..write('status: $status, ')
          ..write('durationMs: $durationMs, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('responseSummary: $responseSummary, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('totalTokens: $totalTokens, ')
          ..write('cachedTokens: $cachedTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('audioDurationSeconds: $audioDurationSeconds, ')
          ..write('ttsCharacterCount: $ttsCharacterCount, ')
          ..write('estimatedCost: $estimatedCost, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailySummariesTable extends DailySummaries
    with TableInfo<$DailySummariesTable, DailySummaryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailySummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('processing'),
  );
  static const VerificationMeta _sourceEntryIdsMeta = const VerificationMeta(
    'sourceEntryIds',
  );
  @override
  late final GeneratedColumn<String> sourceEntryIds = GeneratedColumn<String>(
    'source_entry_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _entryCountMeta = const VerificationMeta(
    'entryCount',
  );
  @override
  late final GeneratedColumn<int> entryCount = GeneratedColumn<int>(
    'entry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    title,
    status,
    sourceEntryIds,
    entryCount,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailySummaryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('source_entry_ids')) {
      context.handle(
        _sourceEntryIdsMeta,
        sourceEntryIds.isAcceptableOrUnknown(
          data['source_entry_ids']!,
          _sourceEntryIdsMeta,
        ),
      );
    }
    if (data.containsKey('entry_count')) {
      context.handle(
        _entryCountMeta,
        entryCount.isAcceptableOrUnknown(data['entry_count']!, _entryCountMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DailySummaryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailySummaryRow(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      sourceEntryIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_entry_ids'],
      )!,
      entryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entry_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $DailySummariesTable createAlias(String alias) {
    return $DailySummariesTable(attachedDatabase, alias);
  }
}

class DailySummaryRow extends DataClass implements Insertable<DailySummaryRow> {
  /// 日期 'yyyy-MM-dd'，主键。
  final String date;
  final String title;

  /// processing / completed / failed（与 DiaryEntries.status 语义一致）。
  final String status;

  /// 参与总结的录音 id 列表，JSON 数组字符串，如 '["uuid1","uuid2"]'。
  final String sourceEntryIds;
  final int entryCount;
  final int createdAt;
  final int? updatedAt;
  const DailySummaryRow({
    required this.date,
    required this.title,
    required this.status,
    required this.sourceEntryIds,
    required this.entryCount,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['title'] = Variable<String>(title);
    map['status'] = Variable<String>(status);
    map['source_entry_ids'] = Variable<String>(sourceEntryIds);
    map['entry_count'] = Variable<int>(entryCount);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<int>(updatedAt);
    }
    return map;
  }

  DailySummariesCompanion toCompanion(bool nullToAbsent) {
    return DailySummariesCompanion(
      date: Value(date),
      title: Value(title),
      status: Value(status),
      sourceEntryIds: Value(sourceEntryIds),
      entryCount: Value(entryCount),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory DailySummaryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailySummaryRow(
      date: serializer.fromJson<String>(json['date']),
      title: serializer.fromJson<String>(json['title']),
      status: serializer.fromJson<String>(json['status']),
      sourceEntryIds: serializer.fromJson<String>(json['sourceEntryIds']),
      entryCount: serializer.fromJson<int>(json['entryCount']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'title': serializer.toJson<String>(title),
      'status': serializer.toJson<String>(status),
      'sourceEntryIds': serializer.toJson<String>(sourceEntryIds),
      'entryCount': serializer.toJson<int>(entryCount),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int?>(updatedAt),
    };
  }

  DailySummaryRow copyWith({
    String? date,
    String? title,
    String? status,
    String? sourceEntryIds,
    int? entryCount,
    int? createdAt,
    Value<int?> updatedAt = const Value.absent(),
  }) => DailySummaryRow(
    date: date ?? this.date,
    title: title ?? this.title,
    status: status ?? this.status,
    sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
    entryCount: entryCount ?? this.entryCount,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  DailySummaryRow copyWithCompanion(DailySummariesCompanion data) {
    return DailySummaryRow(
      date: data.date.present ? data.date.value : this.date,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      sourceEntryIds: data.sourceEntryIds.present
          ? data.sourceEntryIds.value
          : this.sourceEntryIds,
      entryCount: data.entryCount.present
          ? data.entryCount.value
          : this.entryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailySummaryRow(')
          ..write('date: $date, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('sourceEntryIds: $sourceEntryIds, ')
          ..write('entryCount: $entryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    title,
    status,
    sourceEntryIds,
    entryCount,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailySummaryRow &&
          other.date == this.date &&
          other.title == this.title &&
          other.status == this.status &&
          other.sourceEntryIds == this.sourceEntryIds &&
          other.entryCount == this.entryCount &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DailySummariesCompanion extends UpdateCompanion<DailySummaryRow> {
  final Value<String> date;
  final Value<String> title;
  final Value<String> status;
  final Value<String> sourceEntryIds;
  final Value<int> entryCount;
  final Value<int> createdAt;
  final Value<int?> updatedAt;
  final Value<int> rowid;
  const DailySummariesCompanion({
    this.date = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.sourceEntryIds = const Value.absent(),
    this.entryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailySummariesCompanion.insert({
    required String date,
    required String title,
    this.status = const Value.absent(),
    this.sourceEntryIds = const Value.absent(),
    this.entryCount = const Value.absent(),
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<DailySummaryRow> custom({
    Expression<String>? date,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? sourceEntryIds,
    Expression<int>? entryCount,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (sourceEntryIds != null) 'source_entry_ids': sourceEntryIds,
      if (entryCount != null) 'entry_count': entryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailySummariesCompanion copyWith({
    Value<String>? date,
    Value<String>? title,
    Value<String>? status,
    Value<String>? sourceEntryIds,
    Value<int>? entryCount,
    Value<int>? createdAt,
    Value<int?>? updatedAt,
    Value<int>? rowid,
  }) {
    return DailySummariesCompanion(
      date: date ?? this.date,
      title: title ?? this.title,
      status: status ?? this.status,
      sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
      entryCount: entryCount ?? this.entryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sourceEntryIds.present) {
      map['source_entry_ids'] = Variable<String>(sourceEntryIds.value);
    }
    if (entryCount.present) {
      map['entry_count'] = Variable<int>(entryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailySummariesCompanion(')
          ..write('date: $date, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('sourceEntryIds: $sourceEntryIds, ')
          ..write('entryCount: $entryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProcessingTasksTable extends ProcessingTasks
    with TableInfo<$ProcessingTasksTable, ProcessingTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessingTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taskTypeMeta = const VerificationMeta(
    'taskType',
  );
  @override
  late final GeneratedColumn<String> taskType = GeneratedColumn<String>(
    'task_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failedMessageMeta = const VerificationMeta(
    'failedMessage',
  );
  @override
  late final GeneratedColumn<String> failedMessage = GeneratedColumn<String>(
    'failed_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Map<String, dynamic>, String>
  meta = GeneratedColumn<String>(
    'meta',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  ).withConverter<Map<String, dynamic>>($ProcessingTasksTable.$convertermeta);
  static const VerificationMeta _queuedAtMeta = const VerificationMeta(
    'queuedAt',
  );
  @override
  late final GeneratedColumn<int> queuedAt = GeneratedColumn<int>(
    'queued_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<int> finishedAt = GeneratedColumn<int>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    taskType,
    refId,
    status,
    stage,
    failedMessage,
    meta,
    queuedAt,
    startedAt,
    finishedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processing_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProcessingTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_type')) {
      context.handle(
        _taskTypeMeta,
        taskType.isAcceptableOrUnknown(data['task_type']!, _taskTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_taskTypeMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    }
    if (data.containsKey('failed_message')) {
      context.handle(
        _failedMessageMeta,
        failedMessage.isAcceptableOrUnknown(
          data['failed_message']!,
          _failedMessageMeta,
        ),
      );
    }
    if (data.containsKey('queued_at')) {
      context.handle(
        _queuedAtMeta,
        queuedAt.isAcceptableOrUnknown(data['queued_at']!, _queuedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_queuedAtMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProcessingTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessingTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      taskType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_type'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      ),
      failedMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failed_message'],
      ),
      meta: $ProcessingTasksTable.$convertermeta.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}meta'],
        )!,
      ),
      queuedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}queued_at'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finished_at'],
      ),
    );
  }

  @override
  $ProcessingTasksTable createAlias(String alias) {
    return $ProcessingTasksTable(attachedDatabase, alias);
  }

  static TypeConverter<Map<String, dynamic>, String> $convertermeta =
      const MapConverter();
}

class ProcessingTaskRow extends DataClass
    implements Insertable<ProcessingTaskRow> {
  /// 任务 id（UUID）。
  final String id;

  /// 'diary' | 'daily_summary'（可扩展）。
  final String taskType;

  /// diary 的 entryId，或 daily_summary 的日期 'yyyy-MM-dd'。
  final String refId;

  /// 'queued' | 'running' | 'completed' | 'failed'。
  final String status;

  /// 通用调度字段，FGS 续跑用。diary: uploading/asr/llm/tagging；daily_summary 可 null。
  final String? stage;

  /// task 进入 failed 时的原因（异常 toString）。只在 failed 时写。
  final String? failedMessage;

  /// 任务专有数据（JSON）。diary 的 {"asrTaskId":"..."}；daily_summary 的 {}。
  final Map<String, dynamic> meta;

  /// 入队时间（毫秒）。
  final int queuedAt;

  /// FGS 开始处理时间。
  final int? startedAt;

  /// 完成/失败时间。
  final int? finishedAt;
  const ProcessingTaskRow({
    required this.id,
    required this.taskType,
    required this.refId,
    required this.status,
    this.stage,
    this.failedMessage,
    required this.meta,
    required this.queuedAt,
    this.startedAt,
    this.finishedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_type'] = Variable<String>(taskType);
    map['ref_id'] = Variable<String>(refId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || stage != null) {
      map['stage'] = Variable<String>(stage);
    }
    if (!nullToAbsent || failedMessage != null) {
      map['failed_message'] = Variable<String>(failedMessage);
    }
    {
      map['meta'] = Variable<String>(
        $ProcessingTasksTable.$convertermeta.toSql(meta),
      );
    }
    map['queued_at'] = Variable<int>(queuedAt);
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<int>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<int>(finishedAt);
    }
    return map;
  }

  ProcessingTasksCompanion toCompanion(bool nullToAbsent) {
    return ProcessingTasksCompanion(
      id: Value(id),
      taskType: Value(taskType),
      refId: Value(refId),
      status: Value(status),
      stage: stage == null && nullToAbsent
          ? const Value.absent()
          : Value(stage),
      failedMessage: failedMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(failedMessage),
      meta: Value(meta),
      queuedAt: Value(queuedAt),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
    );
  }

  factory ProcessingTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessingTaskRow(
      id: serializer.fromJson<String>(json['id']),
      taskType: serializer.fromJson<String>(json['taskType']),
      refId: serializer.fromJson<String>(json['refId']),
      status: serializer.fromJson<String>(json['status']),
      stage: serializer.fromJson<String?>(json['stage']),
      failedMessage: serializer.fromJson<String?>(json['failedMessage']),
      meta: serializer.fromJson<Map<String, dynamic>>(json['meta']),
      queuedAt: serializer.fromJson<int>(json['queuedAt']),
      startedAt: serializer.fromJson<int?>(json['startedAt']),
      finishedAt: serializer.fromJson<int?>(json['finishedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskType': serializer.toJson<String>(taskType),
      'refId': serializer.toJson<String>(refId),
      'status': serializer.toJson<String>(status),
      'stage': serializer.toJson<String?>(stage),
      'failedMessage': serializer.toJson<String?>(failedMessage),
      'meta': serializer.toJson<Map<String, dynamic>>(meta),
      'queuedAt': serializer.toJson<int>(queuedAt),
      'startedAt': serializer.toJson<int?>(startedAt),
      'finishedAt': serializer.toJson<int?>(finishedAt),
    };
  }

  ProcessingTaskRow copyWith({
    String? id,
    String? taskType,
    String? refId,
    String? status,
    Value<String?> stage = const Value.absent(),
    Value<String?> failedMessage = const Value.absent(),
    Map<String, dynamic>? meta,
    int? queuedAt,
    Value<int?> startedAt = const Value.absent(),
    Value<int?> finishedAt = const Value.absent(),
  }) => ProcessingTaskRow(
    id: id ?? this.id,
    taskType: taskType ?? this.taskType,
    refId: refId ?? this.refId,
    status: status ?? this.status,
    stage: stage.present ? stage.value : this.stage,
    failedMessage: failedMessage.present
        ? failedMessage.value
        : this.failedMessage,
    meta: meta ?? this.meta,
    queuedAt: queuedAt ?? this.queuedAt,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
  );
  ProcessingTaskRow copyWithCompanion(ProcessingTasksCompanion data) {
    return ProcessingTaskRow(
      id: data.id.present ? data.id.value : this.id,
      taskType: data.taskType.present ? data.taskType.value : this.taskType,
      refId: data.refId.present ? data.refId.value : this.refId,
      status: data.status.present ? data.status.value : this.status,
      stage: data.stage.present ? data.stage.value : this.stage,
      failedMessage: data.failedMessage.present
          ? data.failedMessage.value
          : this.failedMessage,
      meta: data.meta.present ? data.meta.value : this.meta,
      queuedAt: data.queuedAt.present ? data.queuedAt.value : this.queuedAt,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessingTaskRow(')
          ..write('id: $id, ')
          ..write('taskType: $taskType, ')
          ..write('refId: $refId, ')
          ..write('status: $status, ')
          ..write('stage: $stage, ')
          ..write('failedMessage: $failedMessage, ')
          ..write('meta: $meta, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    taskType,
    refId,
    status,
    stage,
    failedMessage,
    meta,
    queuedAt,
    startedAt,
    finishedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessingTaskRow &&
          other.id == this.id &&
          other.taskType == this.taskType &&
          other.refId == this.refId &&
          other.status == this.status &&
          other.stage == this.stage &&
          other.failedMessage == this.failedMessage &&
          other.meta == this.meta &&
          other.queuedAt == this.queuedAt &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt);
}

class ProcessingTasksCompanion extends UpdateCompanion<ProcessingTaskRow> {
  final Value<String> id;
  final Value<String> taskType;
  final Value<String> refId;
  final Value<String> status;
  final Value<String?> stage;
  final Value<String?> failedMessage;
  final Value<Map<String, dynamic>> meta;
  final Value<int> queuedAt;
  final Value<int?> startedAt;
  final Value<int?> finishedAt;
  final Value<int> rowid;
  const ProcessingTasksCompanion({
    this.id = const Value.absent(),
    this.taskType = const Value.absent(),
    this.refId = const Value.absent(),
    this.status = const Value.absent(),
    this.stage = const Value.absent(),
    this.failedMessage = const Value.absent(),
    this.meta = const Value.absent(),
    this.queuedAt = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessingTasksCompanion.insert({
    required String id,
    required String taskType,
    required String refId,
    this.status = const Value.absent(),
    this.stage = const Value.absent(),
    this.failedMessage = const Value.absent(),
    this.meta = const Value.absent(),
    required int queuedAt,
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       taskType = Value(taskType),
       refId = Value(refId),
       queuedAt = Value(queuedAt);
  static Insertable<ProcessingTaskRow> custom({
    Expression<String>? id,
    Expression<String>? taskType,
    Expression<String>? refId,
    Expression<String>? status,
    Expression<String>? stage,
    Expression<String>? failedMessage,
    Expression<String>? meta,
    Expression<int>? queuedAt,
    Expression<int>? startedAt,
    Expression<int>? finishedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskType != null) 'task_type': taskType,
      if (refId != null) 'ref_id': refId,
      if (status != null) 'status': status,
      if (stage != null) 'stage': stage,
      if (failedMessage != null) 'failed_message': failedMessage,
      if (meta != null) 'meta': meta,
      if (queuedAt != null) 'queued_at': queuedAt,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessingTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? taskType,
    Value<String>? refId,
    Value<String>? status,
    Value<String?>? stage,
    Value<String?>? failedMessage,
    Value<Map<String, dynamic>>? meta,
    Value<int>? queuedAt,
    Value<int?>? startedAt,
    Value<int?>? finishedAt,
    Value<int>? rowid,
  }) {
    return ProcessingTasksCompanion(
      id: id ?? this.id,
      taskType: taskType ?? this.taskType,
      refId: refId ?? this.refId,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      failedMessage: failedMessage ?? this.failedMessage,
      meta: meta ?? this.meta,
      queuedAt: queuedAt ?? this.queuedAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskType.present) {
      map['task_type'] = Variable<String>(taskType.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (failedMessage.present) {
      map['failed_message'] = Variable<String>(failedMessage.value);
    }
    if (meta.present) {
      map['meta'] = Variable<String>(
        $ProcessingTasksTable.$convertermeta.toSql(meta.value),
      );
    }
    if (queuedAt.present) {
      map['queued_at'] = Variable<int>(queuedAt.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<int>(finishedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessingTasksCompanion(')
          ..write('id: $id, ')
          ..write('taskType: $taskType, ')
          ..write('refId: $refId, ')
          ..write('status: $status, ')
          ..write('stage: $stage, ')
          ..write('failedMessage: $failedMessage, ')
          ..write('meta: $meta, ')
          ..write('queuedAt: $queuedAt, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DiaryEntriesTable diaryEntries = $DiaryEntriesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $DiaryTagRelationsTable diaryTagRelations =
      $DiaryTagRelationsTable(this);
  late final $ApiLogsTable apiLogs = $ApiLogsTable(this);
  late final $DailySummariesTable dailySummaries = $DailySummariesTable(this);
  late final $ProcessingTasksTable processingTasks = $ProcessingTasksTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    diaryEntries,
    tags,
    diaryTagRelations,
    apiLogs,
    dailySummaries,
    processingTasks,
  ];
}

typedef $$DiaryEntriesTableCreateCompanionBuilder =
    DiaryEntriesCompanion Function({
      required String id,
      required String title,
      required String folderPath,
      required int durationSeconds,
      required int createdAt,
      Value<String?> tosKey,
      Value<String> audioFormat,
      Value<int?> uploadedAt,
      Value<WeatherCondition?> weatherCondition,
      Value<String?> weatherIcon,
      Value<String?> weatherText,
      Value<String?> temperature,
      Value<String?> locationName,
      Value<double?> locationLat,
      Value<double?> locationLon,
      Value<String> status,
      Value<String> processingStage,
      Value<String?> asrTaskId,
      Value<int> rowid,
    });
typedef $$DiaryEntriesTableUpdateCompanionBuilder =
    DiaryEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> folderPath,
      Value<int> durationSeconds,
      Value<int> createdAt,
      Value<String?> tosKey,
      Value<String> audioFormat,
      Value<int?> uploadedAt,
      Value<WeatherCondition?> weatherCondition,
      Value<String?> weatherIcon,
      Value<String?> weatherText,
      Value<String?> temperature,
      Value<String?> locationName,
      Value<double?> locationLat,
      Value<double?> locationLon,
      Value<String> status,
      Value<String> processingStage,
      Value<String?> asrTaskId,
      Value<int> rowid,
    });

final class $$DiaryEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $DiaryEntriesTable, DiaryEntry> {
  $$DiaryEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiaryTagRelationsTable, List<DiaryTagRelation>>
  _diaryTagRelationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.diaryTagRelations,
        aliasName: 'diary_entries__id__diary_tag_relations__diary_id',
      );

  $$DiaryTagRelationsTableProcessedTableManager get diaryTagRelationsRefs {
    final manager = $$DiaryTagRelationsTableTableManager(
      $_db,
      $_db.diaryTagRelations,
    ).filter((f) => f.diaryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diaryTagRelationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DiaryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tosKey => $composableBuilder(
    column: $table.tosKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<WeatherCondition?, WeatherCondition, String>
  get weatherCondition => $composableBuilder(
    column: $table.weatherCondition,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get weatherIcon => $composableBuilder(
    column: $table.weatherIcon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weatherText => $composableBuilder(
    column: $table.weatherText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationLat => $composableBuilder(
    column: $table.locationLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationLon => $composableBuilder(
    column: $table.locationLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processingStage => $composableBuilder(
    column: $table.processingStage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get asrTaskId => $composableBuilder(
    column: $table.asrTaskId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diaryTagRelationsRefs(
    Expression<bool> Function($$DiaryTagRelationsTableFilterComposer f) f,
  ) {
    final $$DiaryTagRelationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryTagRelations,
      getReferencedColumn: (t) => t.diaryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryTagRelationsTableFilterComposer(
            $db: $db,
            $table: $db.diaryTagRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DiaryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tosKey => $composableBuilder(
    column: $table.tosKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weatherCondition => $composableBuilder(
    column: $table.weatherCondition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weatherIcon => $composableBuilder(
    column: $table.weatherIcon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weatherText => $composableBuilder(
    column: $table.weatherText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationLat => $composableBuilder(
    column: $table.locationLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationLon => $composableBuilder(
    column: $table.locationLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processingStage => $composableBuilder(
    column: $table.processingStage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get asrTaskId => $composableBuilder(
    column: $table.asrTaskId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DiaryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryEntriesTable> {
  $$DiaryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get tosKey =>
      $composableBuilder(column: $table.tosKey, builder: (column) => column);

  GeneratedColumn<String> get audioFormat => $composableBuilder(
    column: $table.audioFormat,
    builder: (column) => column,
  );

  GeneratedColumn<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<WeatherCondition?, String>
  get weatherCondition => $composableBuilder(
    column: $table.weatherCondition,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weatherIcon => $composableBuilder(
    column: $table.weatherIcon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weatherText => $composableBuilder(
    column: $table.weatherText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get locationLat => $composableBuilder(
    column: $table.locationLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get locationLon => $composableBuilder(
    column: $table.locationLon,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get processingStage => $composableBuilder(
    column: $table.processingStage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get asrTaskId =>
      $composableBuilder(column: $table.asrTaskId, builder: (column) => column);

  Expression<T> diaryTagRelationsRefs<T extends Object>(
    Expression<T> Function($$DiaryTagRelationsTableAnnotationComposer a) f,
  ) {
    final $$DiaryTagRelationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.diaryTagRelations,
          getReferencedColumn: (t) => t.diaryId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DiaryTagRelationsTableAnnotationComposer(
                $db: $db,
                $table: $db.diaryTagRelations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DiaryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryEntriesTable,
          DiaryEntry,
          $$DiaryEntriesTableFilterComposer,
          $$DiaryEntriesTableOrderingComposer,
          $$DiaryEntriesTableAnnotationComposer,
          $$DiaryEntriesTableCreateCompanionBuilder,
          $$DiaryEntriesTableUpdateCompanionBuilder,
          (DiaryEntry, $$DiaryEntriesTableReferences),
          DiaryEntry,
          PrefetchHooks Function({bool diaryTagRelationsRefs})
        > {
  $$DiaryEntriesTableTableManager(_$AppDatabase db, $DiaryEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> folderPath = const Value.absent(),
                Value<int> durationSeconds = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> tosKey = const Value.absent(),
                Value<String> audioFormat = const Value.absent(),
                Value<int?> uploadedAt = const Value.absent(),
                Value<WeatherCondition?> weatherCondition =
                    const Value.absent(),
                Value<String?> weatherIcon = const Value.absent(),
                Value<String?> weatherText = const Value.absent(),
                Value<String?> temperature = const Value.absent(),
                Value<String?> locationName = const Value.absent(),
                Value<double?> locationLat = const Value.absent(),
                Value<double?> locationLon = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> processingStage = const Value.absent(),
                Value<String?> asrTaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntriesCompanion(
                id: id,
                title: title,
                folderPath: folderPath,
                durationSeconds: durationSeconds,
                createdAt: createdAt,
                tosKey: tosKey,
                audioFormat: audioFormat,
                uploadedAt: uploadedAt,
                weatherCondition: weatherCondition,
                weatherIcon: weatherIcon,
                weatherText: weatherText,
                temperature: temperature,
                locationName: locationName,
                locationLat: locationLat,
                locationLon: locationLon,
                status: status,
                processingStage: processingStage,
                asrTaskId: asrTaskId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String folderPath,
                required int durationSeconds,
                required int createdAt,
                Value<String?> tosKey = const Value.absent(),
                Value<String> audioFormat = const Value.absent(),
                Value<int?> uploadedAt = const Value.absent(),
                Value<WeatherCondition?> weatherCondition =
                    const Value.absent(),
                Value<String?> weatherIcon = const Value.absent(),
                Value<String?> weatherText = const Value.absent(),
                Value<String?> temperature = const Value.absent(),
                Value<String?> locationName = const Value.absent(),
                Value<double?> locationLat = const Value.absent(),
                Value<double?> locationLon = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> processingStage = const Value.absent(),
                Value<String?> asrTaskId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryEntriesCompanion.insert(
                id: id,
                title: title,
                folderPath: folderPath,
                durationSeconds: durationSeconds,
                createdAt: createdAt,
                tosKey: tosKey,
                audioFormat: audioFormat,
                uploadedAt: uploadedAt,
                weatherCondition: weatherCondition,
                weatherIcon: weatherIcon,
                weatherText: weatherText,
                temperature: temperature,
                locationName: locationName,
                locationLat: locationLat,
                locationLon: locationLon,
                status: status,
                processingStage: processingStage,
                asrTaskId: asrTaskId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiaryEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diaryTagRelationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (diaryTagRelationsRefs) db.diaryTagRelations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (diaryTagRelationsRefs)
                    await $_getPrefetchedData<
                      DiaryEntry,
                      $DiaryEntriesTable,
                      DiaryTagRelation
                    >(
                      currentTable: table,
                      referencedTable: $$DiaryEntriesTableReferences
                          ._diaryTagRelationsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$DiaryEntriesTableReferences(
                            db,
                            table,
                            p0,
                          ).diaryTagRelationsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.diaryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DiaryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryEntriesTable,
      DiaryEntry,
      $$DiaryEntriesTableFilterComposer,
      $$DiaryEntriesTableOrderingComposer,
      $$DiaryEntriesTableAnnotationComposer,
      $$DiaryEntriesTableCreateCompanionBuilder,
      $$DiaryEntriesTableUpdateCompanionBuilder,
      (DiaryEntry, $$DiaryEntriesTableReferences),
      DiaryEntry,
      PrefetchHooks Function({bool diaryTagRelationsRefs})
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      Value<String> matchPrompt,
      Value<String?> color,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> matchPrompt,
      Value<String?> color,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$TagsTableReferences
    extends BaseReferences<_$AppDatabase, $TagsTable, Tag> {
  $$TagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DiaryTagRelationsTable, List<DiaryTagRelation>>
  _diaryTagRelationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.diaryTagRelations,
        aliasName: 'tags__id__diary_tag_relations__tag_id',
      );

  $$DiaryTagRelationsTableProcessedTableManager get diaryTagRelationsRefs {
    final manager = $$DiaryTagRelationsTableTableManager(
      $_db,
      $_db.diaryTagRelations,
    ).filter((f) => f.tagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _diaryTagRelationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matchPrompt => $composableBuilder(
    column: $table.matchPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> diaryTagRelationsRefs(
    Expression<bool> Function($$DiaryTagRelationsTableFilterComposer f) f,
  ) {
    final $$DiaryTagRelationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.diaryTagRelations,
      getReferencedColumn: (t) => t.tagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryTagRelationsTableFilterComposer(
            $db: $db,
            $table: $db.diaryTagRelations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matchPrompt => $composableBuilder(
    column: $table.matchPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get matchPrompt => $composableBuilder(
    column: $table.matchPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> diaryTagRelationsRefs<T extends Object>(
    Expression<T> Function($$DiaryTagRelationsTableAnnotationComposer a) f,
  ) {
    final $$DiaryTagRelationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.diaryTagRelations,
          getReferencedColumn: (t) => t.tagId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DiaryTagRelationsTableAnnotationComposer(
                $db: $db,
                $table: $db.diaryTagRelations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, $$TagsTableReferences),
          Tag,
          PrefetchHooks Function({bool diaryTagRelationsRefs})
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> matchPrompt = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                matchPrompt: matchPrompt,
                color: color,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> matchPrompt = const Value.absent(),
                Value<String?> color = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                matchPrompt: matchPrompt,
                color: color,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$TagsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({diaryTagRelationsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (diaryTagRelationsRefs) db.diaryTagRelations,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (diaryTagRelationsRefs)
                    await $_getPrefetchedData<
                      Tag,
                      $TagsTable,
                      DiaryTagRelation
                    >(
                      currentTable: table,
                      referencedTable: $$TagsTableReferences
                          ._diaryTagRelationsRefsTable(db),
                      managerFromTypedResult: (p0) => $$TagsTableReferences(
                        db,
                        table,
                        p0,
                      ).diaryTagRelationsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.tagId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, $$TagsTableReferences),
      Tag,
      PrefetchHooks Function({bool diaryTagRelationsRefs})
    >;
typedef $$DiaryTagRelationsTableCreateCompanionBuilder =
    DiaryTagRelationsCompanion Function({
      required String diaryId,
      required String tagId,
      Value<String> source,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$DiaryTagRelationsTableUpdateCompanionBuilder =
    DiaryTagRelationsCompanion Function({
      Value<String> diaryId,
      Value<String> tagId,
      Value<String> source,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$DiaryTagRelationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $DiaryTagRelationsTable,
          DiaryTagRelation
        > {
  $$DiaryTagRelationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DiaryEntriesTable _diaryIdTable(_$AppDatabase db) => db.diaryEntries
      .createAlias('diary_tag_relations__diary_id__diary_entries__id');

  $$DiaryEntriesTableProcessedTableManager get diaryId {
    final $_column = $_itemColumn<String>('diary_id')!;

    final manager = $$DiaryEntriesTableTableManager(
      $_db,
      $_db.diaryEntries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_diaryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $TagsTable _tagIdTable(_$AppDatabase db) =>
      db.tags.createAlias('diary_tag_relations__tag_id__tags__id');

  $$TagsTableProcessedTableManager get tagId {
    final $_column = $_itemColumn<String>('tag_id')!;

    final manager = $$TagsTableTableManager(
      $_db,
      $_db.tags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_tagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DiaryTagRelationsTableFilterComposer
    extends Composer<_$AppDatabase, $DiaryTagRelationsTable> {
  $$DiaryTagRelationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DiaryEntriesTableFilterComposer get diaryId {
    final $$DiaryEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diaryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableFilterComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableFilterComposer get tagId {
    final $$TagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableFilterComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryTagRelationsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiaryTagRelationsTable> {
  $$DiaryTagRelationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DiaryEntriesTableOrderingComposer get diaryId {
    final $$DiaryEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diaryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableOrderingComposer get tagId {
    final $$TagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableOrderingComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryTagRelationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiaryTagRelationsTable> {
  $$DiaryTagRelationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$DiaryEntriesTableAnnotationComposer get diaryId {
    final $$DiaryEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.diaryId,
      referencedTable: $db.diaryEntries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DiaryEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.diaryEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$TagsTableAnnotationComposer get tagId {
    final $$TagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.tagId,
      referencedTable: $db.tags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TagsTableAnnotationComposer(
            $db: $db,
            $table: $db.tags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DiaryTagRelationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DiaryTagRelationsTable,
          DiaryTagRelation,
          $$DiaryTagRelationsTableFilterComposer,
          $$DiaryTagRelationsTableOrderingComposer,
          $$DiaryTagRelationsTableAnnotationComposer,
          $$DiaryTagRelationsTableCreateCompanionBuilder,
          $$DiaryTagRelationsTableUpdateCompanionBuilder,
          (DiaryTagRelation, $$DiaryTagRelationsTableReferences),
          DiaryTagRelation,
          PrefetchHooks Function({bool diaryId, bool tagId})
        > {
  $$DiaryTagRelationsTableTableManager(
    _$AppDatabase db,
    $DiaryTagRelationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiaryTagRelationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiaryTagRelationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiaryTagRelationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> diaryId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DiaryTagRelationsCompanion(
                diaryId: diaryId,
                tagId: tagId,
                source: source,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String diaryId,
                required String tagId,
                Value<String> source = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DiaryTagRelationsCompanion.insert(
                diaryId: diaryId,
                tagId: tagId,
                source: source,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DiaryTagRelationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({diaryId = false, tagId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (diaryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.diaryId,
                                referencedTable:
                                    $$DiaryTagRelationsTableReferences
                                        ._diaryIdTable(db),
                                referencedColumn:
                                    $$DiaryTagRelationsTableReferences
                                        ._diaryIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (tagId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.tagId,
                                referencedTable:
                                    $$DiaryTagRelationsTableReferences
                                        ._tagIdTable(db),
                                referencedColumn:
                                    $$DiaryTagRelationsTableReferences
                                        ._tagIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DiaryTagRelationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DiaryTagRelationsTable,
      DiaryTagRelation,
      $$DiaryTagRelationsTableFilterComposer,
      $$DiaryTagRelationsTableOrderingComposer,
      $$DiaryTagRelationsTableAnnotationComposer,
      $$DiaryTagRelationsTableCreateCompanionBuilder,
      $$DiaryTagRelationsTableUpdateCompanionBuilder,
      (DiaryTagRelation, $$DiaryTagRelationsTableReferences),
      DiaryTagRelation,
      PrefetchHooks Function({bool diaryId, bool tagId})
    >;
typedef $$ApiLogsTableCreateCompanionBuilder =
    ApiLogsCompanion Function({
      required String id,
      required String diaryId,
      required String apiType,
      required String step,
      required String status,
      Value<int?> durationMs,
      Value<String?> errorMessage,
      Value<String?> responseSummary,
      Value<int?> promptTokens,
      Value<int?> completionTokens,
      Value<int?> totalTokens,
      Value<int?> cachedTokens,
      Value<int?> reasoningTokens,
      Value<int?> audioDurationSeconds,
      Value<int?> ttsCharacterCount,
      Value<double?> estimatedCost,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ApiLogsTableUpdateCompanionBuilder =
    ApiLogsCompanion Function({
      Value<String> id,
      Value<String> diaryId,
      Value<String> apiType,
      Value<String> step,
      Value<String> status,
      Value<int?> durationMs,
      Value<String?> errorMessage,
      Value<String?> responseSummary,
      Value<int?> promptTokens,
      Value<int?> completionTokens,
      Value<int?> totalTokens,
      Value<int?> cachedTokens,
      Value<int?> reasoningTokens,
      Value<int?> audioDurationSeconds,
      Value<int?> ttsCharacterCount,
      Value<double?> estimatedCost,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$ApiLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ApiLogsTable> {
  $$ApiLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get diaryId => $composableBuilder(
    column: $table.diaryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiType => $composableBuilder(
    column: $table.apiType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get responseSummary => $composableBuilder(
    column: $table.responseSummary,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedTokens => $composableBuilder(
    column: $table.cachedTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioDurationSeconds => $composableBuilder(
    column: $table.audioDurationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ttsCharacterCount => $composableBuilder(
    column: $table.ttsCharacterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get estimatedCost => $composableBuilder(
    column: $table.estimatedCost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ApiLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ApiLogsTable> {
  $$ApiLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get diaryId => $composableBuilder(
    column: $table.diaryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiType => $composableBuilder(
    column: $table.apiType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get responseSummary => $composableBuilder(
    column: $table.responseSummary,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedTokens => $composableBuilder(
    column: $table.cachedTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioDurationSeconds => $composableBuilder(
    column: $table.audioDurationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ttsCharacterCount => $composableBuilder(
    column: $table.ttsCharacterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get estimatedCost => $composableBuilder(
    column: $table.estimatedCost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ApiLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ApiLogsTable> {
  $$ApiLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get diaryId =>
      $composableBuilder(column: $table.diaryId, builder: (column) => column);

  GeneratedColumn<String> get apiType =>
      $composableBuilder(column: $table.apiType, builder: (column) => column);

  GeneratedColumn<String> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get responseSummary => $composableBuilder(
    column: $table.responseSummary,
    builder: (column) => column,
  );

  GeneratedColumn<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cachedTokens => $composableBuilder(
    column: $table.cachedTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get audioDurationSeconds => $composableBuilder(
    column: $table.audioDurationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get ttsCharacterCount => $composableBuilder(
    column: $table.ttsCharacterCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get estimatedCost => $composableBuilder(
    column: $table.estimatedCost,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ApiLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ApiLogsTable,
          ApiLog,
          $$ApiLogsTableFilterComposer,
          $$ApiLogsTableOrderingComposer,
          $$ApiLogsTableAnnotationComposer,
          $$ApiLogsTableCreateCompanionBuilder,
          $$ApiLogsTableUpdateCompanionBuilder,
          (ApiLog, BaseReferences<_$AppDatabase, $ApiLogsTable, ApiLog>),
          ApiLog,
          PrefetchHooks Function()
        > {
  $$ApiLogsTableTableManager(_$AppDatabase db, $ApiLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ApiLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ApiLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ApiLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> diaryId = const Value.absent(),
                Value<String> apiType = const Value.absent(),
                Value<String> step = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> responseSummary = const Value.absent(),
                Value<int?> promptTokens = const Value.absent(),
                Value<int?> completionTokens = const Value.absent(),
                Value<int?> totalTokens = const Value.absent(),
                Value<int?> cachedTokens = const Value.absent(),
                Value<int?> reasoningTokens = const Value.absent(),
                Value<int?> audioDurationSeconds = const Value.absent(),
                Value<int?> ttsCharacterCount = const Value.absent(),
                Value<double?> estimatedCost = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ApiLogsCompanion(
                id: id,
                diaryId: diaryId,
                apiType: apiType,
                step: step,
                status: status,
                durationMs: durationMs,
                errorMessage: errorMessage,
                responseSummary: responseSummary,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens,
                reasoningTokens: reasoningTokens,
                audioDurationSeconds: audioDurationSeconds,
                ttsCharacterCount: ttsCharacterCount,
                estimatedCost: estimatedCost,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String diaryId,
                required String apiType,
                required String step,
                required String status,
                Value<int?> durationMs = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<String?> responseSummary = const Value.absent(),
                Value<int?> promptTokens = const Value.absent(),
                Value<int?> completionTokens = const Value.absent(),
                Value<int?> totalTokens = const Value.absent(),
                Value<int?> cachedTokens = const Value.absent(),
                Value<int?> reasoningTokens = const Value.absent(),
                Value<int?> audioDurationSeconds = const Value.absent(),
                Value<int?> ttsCharacterCount = const Value.absent(),
                Value<double?> estimatedCost = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ApiLogsCompanion.insert(
                id: id,
                diaryId: diaryId,
                apiType: apiType,
                step: step,
                status: status,
                durationMs: durationMs,
                errorMessage: errorMessage,
                responseSummary: responseSummary,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedTokens: cachedTokens,
                reasoningTokens: reasoningTokens,
                audioDurationSeconds: audioDurationSeconds,
                ttsCharacterCount: ttsCharacterCount,
                estimatedCost: estimatedCost,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ApiLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ApiLogsTable,
      ApiLog,
      $$ApiLogsTableFilterComposer,
      $$ApiLogsTableOrderingComposer,
      $$ApiLogsTableAnnotationComposer,
      $$ApiLogsTableCreateCompanionBuilder,
      $$ApiLogsTableUpdateCompanionBuilder,
      (ApiLog, BaseReferences<_$AppDatabase, $ApiLogsTable, ApiLog>),
      ApiLog,
      PrefetchHooks Function()
    >;
typedef $$DailySummariesTableCreateCompanionBuilder =
    DailySummariesCompanion Function({
      required String date,
      required String title,
      Value<String> status,
      Value<String> sourceEntryIds,
      Value<int> entryCount,
      required int createdAt,
      Value<int?> updatedAt,
      Value<int> rowid,
    });
typedef $$DailySummariesTableUpdateCompanionBuilder =
    DailySummariesCompanion Function({
      Value<String> date,
      Value<String> title,
      Value<String> status,
      Value<String> sourceEntryIds,
      Value<int> entryCount,
      Value<int> createdAt,
      Value<int?> updatedAt,
      Value<int> rowid,
    });

class $$DailySummariesTableFilterComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceEntryIds => $composableBuilder(
    column: $table.sourceEntryIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailySummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceEntryIds => $composableBuilder(
    column: $table.sourceEntryIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailySummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailySummariesTable> {
  $$DailySummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sourceEntryIds => $composableBuilder(
    column: $table.sourceEntryIds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entryCount => $composableBuilder(
    column: $table.entryCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailySummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailySummariesTable,
          DailySummaryRow,
          $$DailySummariesTableFilterComposer,
          $$DailySummariesTableOrderingComposer,
          $$DailySummariesTableAnnotationComposer,
          $$DailySummariesTableCreateCompanionBuilder,
          $$DailySummariesTableUpdateCompanionBuilder,
          (
            DailySummaryRow,
            BaseReferences<
              _$AppDatabase,
              $DailySummariesTable,
              DailySummaryRow
            >,
          ),
          DailySummaryRow,
          PrefetchHooks Function()
        > {
  $$DailySummariesTableTableManager(
    _$AppDatabase db,
    $DailySummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailySummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailySummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailySummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> sourceEntryIds = const Value.absent(),
                Value<int> entryCount = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailySummariesCompanion(
                date: date,
                title: title,
                status: status,
                sourceEntryIds: sourceEntryIds,
                entryCount: entryCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required String title,
                Value<String> status = const Value.absent(),
                Value<String> sourceEntryIds = const Value.absent(),
                Value<int> entryCount = const Value.absent(),
                required int createdAt,
                Value<int?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DailySummariesCompanion.insert(
                date: date,
                title: title,
                status: status,
                sourceEntryIds: sourceEntryIds,
                entryCount: entryCount,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailySummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailySummariesTable,
      DailySummaryRow,
      $$DailySummariesTableFilterComposer,
      $$DailySummariesTableOrderingComposer,
      $$DailySummariesTableAnnotationComposer,
      $$DailySummariesTableCreateCompanionBuilder,
      $$DailySummariesTableUpdateCompanionBuilder,
      (
        DailySummaryRow,
        BaseReferences<_$AppDatabase, $DailySummariesTable, DailySummaryRow>,
      ),
      DailySummaryRow,
      PrefetchHooks Function()
    >;
typedef $$ProcessingTasksTableCreateCompanionBuilder =
    ProcessingTasksCompanion Function({
      required String id,
      required String taskType,
      required String refId,
      Value<String> status,
      Value<String?> stage,
      Value<String?> failedMessage,
      Value<Map<String, dynamic>> meta,
      required int queuedAt,
      Value<int?> startedAt,
      Value<int?> finishedAt,
      Value<int> rowid,
    });
typedef $$ProcessingTasksTableUpdateCompanionBuilder =
    ProcessingTasksCompanion Function({
      Value<String> id,
      Value<String> taskType,
      Value<String> refId,
      Value<String> status,
      Value<String?> stage,
      Value<String?> failedMessage,
      Value<Map<String, dynamic>> meta,
      Value<int> queuedAt,
      Value<int?> startedAt,
      Value<int?> finishedAt,
      Value<int> rowid,
    });

class $$ProcessingTasksTableFilterComposer
    extends Composer<_$AppDatabase, $ProcessingTasksTable> {
  $$ProcessingTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failedMessage => $composableBuilder(
    column: $table.failedMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    Map<String, dynamic>,
    Map<String, dynamic>,
    String
  >
  get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProcessingTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $ProcessingTasksTable> {
  $$ProcessingTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get taskType => $composableBuilder(
    column: $table.taskType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failedMessage => $composableBuilder(
    column: $table.failedMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get meta => $composableBuilder(
    column: $table.meta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get queuedAt => $composableBuilder(
    column: $table.queuedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProcessingTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProcessingTasksTable> {
  $$ProcessingTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskType =>
      $composableBuilder(column: $table.taskType, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get failedMessage => $composableBuilder(
    column: $table.failedMessage,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Map<String, dynamic>, String> get meta =>
      $composableBuilder(column: $table.meta, builder: (column) => column);

  GeneratedColumn<int> get queuedAt =>
      $composableBuilder(column: $table.queuedAt, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );
}

class $$ProcessingTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProcessingTasksTable,
          ProcessingTaskRow,
          $$ProcessingTasksTableFilterComposer,
          $$ProcessingTasksTableOrderingComposer,
          $$ProcessingTasksTableAnnotationComposer,
          $$ProcessingTasksTableCreateCompanionBuilder,
          $$ProcessingTasksTableUpdateCompanionBuilder,
          (
            ProcessingTaskRow,
            BaseReferences<
              _$AppDatabase,
              $ProcessingTasksTable,
              ProcessingTaskRow
            >,
          ),
          ProcessingTaskRow,
          PrefetchHooks Function()
        > {
  $$ProcessingTasksTableTableManager(
    _$AppDatabase db,
    $ProcessingTasksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessingTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessingTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessingTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> taskType = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<String?> failedMessage = const Value.absent(),
                Value<Map<String, dynamic>> meta = const Value.absent(),
                Value<int> queuedAt = const Value.absent(),
                Value<int?> startedAt = const Value.absent(),
                Value<int?> finishedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessingTasksCompanion(
                id: id,
                taskType: taskType,
                refId: refId,
                status: status,
                stage: stage,
                failedMessage: failedMessage,
                meta: meta,
                queuedAt: queuedAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String taskType,
                required String refId,
                Value<String> status = const Value.absent(),
                Value<String?> stage = const Value.absent(),
                Value<String?> failedMessage = const Value.absent(),
                Value<Map<String, dynamic>> meta = const Value.absent(),
                required int queuedAt,
                Value<int?> startedAt = const Value.absent(),
                Value<int?> finishedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProcessingTasksCompanion.insert(
                id: id,
                taskType: taskType,
                refId: refId,
                status: status,
                stage: stage,
                failedMessage: failedMessage,
                meta: meta,
                queuedAt: queuedAt,
                startedAt: startedAt,
                finishedAt: finishedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProcessingTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProcessingTasksTable,
      ProcessingTaskRow,
      $$ProcessingTasksTableFilterComposer,
      $$ProcessingTasksTableOrderingComposer,
      $$ProcessingTasksTableAnnotationComposer,
      $$ProcessingTasksTableCreateCompanionBuilder,
      $$ProcessingTasksTableUpdateCompanionBuilder,
      (
        ProcessingTaskRow,
        BaseReferences<_$AppDatabase, $ProcessingTasksTable, ProcessingTaskRow>,
      ),
      ProcessingTaskRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DiaryEntriesTableTableManager get diaryEntries =>
      $$DiaryEntriesTableTableManager(_db, _db.diaryEntries);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$DiaryTagRelationsTableTableManager get diaryTagRelations =>
      $$DiaryTagRelationsTableTableManager(_db, _db.diaryTagRelations);
  $$ApiLogsTableTableManager get apiLogs =>
      $$ApiLogsTableTableManager(_db, _db.apiLogs);
  $$DailySummariesTableTableManager get dailySummaries =>
      $$DailySummariesTableTableManager(_db, _db.dailySummaries);
  $$ProcessingTasksTableTableManager get processingTasks =>
      $$ProcessingTasksTableTableManager(_db, _db.processingTasks);
}
