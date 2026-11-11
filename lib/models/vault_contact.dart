import 'dart:convert';
import 'dart:math';
import 'package:zerotrust_contacts/l10n/l10n.dart';

// Sentinel used in copyWith to distinguish "not provided" from explicit null.
class _Absent {
  const _Absent();
}

const _absent = _Absent();

class VaultContact {
  VaultContact({
    required this.id,
    required this.displayName,
    required this.firstName,
    required this.lastName,
    required this.company,
    required this.notes,
    required this.phones,
    required this.emails,
    required this.addresses,
    required this.labels,
    required this.birthdays,
    required this.other,
    required this.source,
    required this.isFavorite,
    required this.isPinned,
    required this.isBlocked,
    this.blockReason,
    required this.interactionCount,
    required this.createdAt,
    required this.updatedAt,
    required this.fieldUpdatedAt,
    this.lastContactedAt,
    this.photoPath,
    this.photo,
    this.valueTypes = const <String, String>{},
  });

  final String id;
  final String displayName;
  final String firstName;
  final String lastName;
  final String company;
  final String notes;
  final List<String> phones;
  final List<String> emails;
  final List<String> addresses;
  final List<String> labels;
  final List<String> birthdays;
  final List<String> other;
  final String source;
  final bool isFavorite;
  final bool isPinned;
  final bool isBlocked;
  final String? blockReason;
  final int interactionCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastContactedAt;
  final Map<String, DateTime> fieldUpdatedAt;

  /// Set by versions before the core: the contact had a photo stored as a
  /// plain file (on the phone and in the `contactsProfilePictures` bucket).
  /// Cleared once that photo has been moved into [photo].
  final String? photoPath;

  /// The contact's photo: an encrypted attachment (`ZtAttachmentRef` JSON,
  /// which holds the photo's own key).
  final Map<String, Object?>? photo;

  bool get hasPhoto => photo != null || photoPath != null;

  /// The kind of each phone, email and address (`mobile`, `work`, `home`…),
  /// keyed by [typeKey]. Kept beside the plain value lists, so app versions
  /// from before typed fields still read every value.
  final Map<String, String> valueTypes;

  static const List<String> phoneTypes = <String>[
    'mobile', 'home', 'work', 'main', 'other', //
  ];
  static const List<String> emailTypes = <String>['home', 'work', 'other'];
  static const List<String> addressTypes = <String>['home', 'work', 'other'];

  /// The key of a value in [valueTypes]. [field] is `phone`, `email` or
  /// `address`.
  static String typeKey(String field, String value) => switch (field) {
        'phone' => 'phone:${normalizedPhone(value)}',
        'email' => 'email:${normalizedEmail(value)}',
        _ => '$field:${value.trim().toLowerCase()}',
      };

  /// `mobile`, `work`…, or null when the value has no kind.
  String? typeOf(String field, String value) =>
      valueTypes[typeKey(field, value)];

  /// "Mobile", "Work"… for showing, or [fallback].
  String typeLabel(String field, String value, {required String fallback}) {
    final String? type = typeOf(field, value);
    return type == null || type.isEmpty
        ? fallback
        : fieldTypeLabel(type);
  }

  /// [valueTypes] without entries for values the contact no longer has.
  Map<String, String> _prunedTypes(Map<String, String> types,
      List<String> phones, List<String> emails, List<String> addresses) {
    final Set<String> keep = <String>{
      for (final String v in phones) typeKey('phone', v),
      for (final String v in emails) typeKey('email', v),
      for (final String v in addresses) typeKey('address', v),
    };
    return <String, String>{
      for (final MapEntry<String, String> e in types.entries)
        if (keep.contains(e.key) && e.value.isNotEmpty) e.key: e.value,
    };
  }

  static const List<String> mergeableFields = <String>[
    'displayName',
    'firstName',
    'lastName',
    'company',
    'notes',
    'phones',
    'emails',
    'addresses',
    'labels',
    'birthdays',
    'other',
    'source',
    'isFavorite',
    'isPinned',
    'isBlocked',
    'blockReason',
    'interactionCount',
    'lastContactedAt',
    'photoPath',
    'photo',
    'valueTypes',
  ];

  static VaultContact fromJson(Map<String, dynamic> json) {
    final DateTime now = DateTime.now().toUtc();
    final DateTime createdAt = _parseDate(json['createdAt']) ?? now;
    final DateTime updatedAt = _parseDate(json['updatedAt']) ?? createdAt;
    final DateTime? lastContactedAt = _parseDate(json['lastContactedAt']);

    final Map<String, DateTime> fieldUpdatedAt = <String, DateTime>{};
    final dynamic rawFieldUpdates = json['fieldUpdatedAt'];
    if (rawFieldUpdates is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawFieldUpdates.entries) {
        final String key = entry.key.toString();
        final DateTime? value = _parseDate(entry.value);
        if (value != null) {
          fieldUpdatedAt[key] = value.toUtc();
        }
      }
    }

    final String firstName = _readString(json['firstName']);
    final String lastName = _readString(json['lastName']);
    final String company = _readString(json['company']);
    final List<String> phones = _readStringList(json['phones']);
    final String displayName = _buildDisplayName(
      explicitDisplayName: _readString(json['displayName']),
      firstName: firstName,
      lastName: lastName,
      company: company,
      phones: phones,
    );

    return VaultContact(
      id: _readString(json['id']).isEmpty
          ? generateId()
          : _readString(json['id']),
      displayName: displayName,
      firstName: firstName,
      lastName: lastName,
      company: company,
      notes: _readString(json['notes']),
      phones: phones,
      emails: _readStringList(json['emails']),
      addresses: _readStringList(json['addresses']),
      labels: _readStringList(json['labels']),
      birthdays: _readStringList(json['birthdays']),
      other: _readStringList(json['other']),
      source: _readString(json['source']).isEmpty
          ? 'Saved'
          : _readString(json['source']),
      isFavorite: json['isFavorite'] == true,
      isPinned: json['isPinned'] == true,
      isBlocked: json['isBlocked'] == true,
      blockReason: json['blockReason'] as String?,
      interactionCount: _readInt(json['interactionCount']),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      lastContactedAt: lastContactedAt?.toUtc(),
      fieldUpdatedAt: fieldUpdatedAt,
      photoPath: json['photoPath'] as String?,
      photo: _readMap(json['photo']),
      valueTypes: _readTypes(json['valueTypes']),
    )._withDefaultFieldTimestamps();
  }

  static VaultContact fromLegacyPayload(Map<String, dynamic> payload) {
    final DateTime now = DateTime.now().toUtc();
    return VaultContact(
      id: _readString(payload['id']).isEmpty
          ? generateId()
          : _readString(payload['id']),
      displayName: _buildDisplayName(
        explicitDisplayName: _readString(payload['displayName']),
        firstName: _readString(payload['firstName']),
        lastName: _readString(payload['lastName']),
        company: _readString(payload['company']),
        phones: _readStringList(payload['phones']),
      ),
      firstName: _readString(payload['firstName']),
      lastName: _readString(payload['lastName']),
      company: _readString(payload['company']),
      notes: _readString(payload['notes']),
      phones: _readStringList(payload['phones']),
      emails: _readStringList(payload['emails']),
      addresses: _readStringList(payload['addresses']),
      labels: _readStringList(payload['labels']),
      birthdays: _readStringList(payload['birthdays']),
      other: _readStringList(payload['other']),
      source: _readString(payload['source']).isEmpty
          ? 'Saved'
          : _readString(payload['source']),
      isFavorite: payload['isFavorite'] == true,
      isPinned: payload['isPinned'] == true,
      isBlocked: false,
      blockReason: null,
      interactionCount: _readInt(payload['interactionCount']),
      createdAt: _parseDate(payload['createdAt'])?.toUtc() ?? now,
      updatedAt: _parseDate(payload['updatedAt'])?.toUtc() ?? now,
      lastContactedAt: _parseDate(payload['lastContactedAt'])?.toUtc(),
      fieldUpdatedAt: <String, DateTime>{},
      photoPath: payload['photoPath'] as String?,
      photo: _readMap(payload['photo']),
      valueTypes: _readTypes(payload['valueTypes']),
    )._withDefaultFieldTimestamps();
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'company': company,
      'notes': notes,
      'phones': phones,
      'emails': emails,
      'addresses': addresses,
      'labels': labels,
      'birthdays': birthdays,
      'other': other,
      'source': source,
      'isFavorite': isFavorite,
      'isPinned': isPinned,
      'isBlocked': isBlocked,
      'blockReason': blockReason,
      'interactionCount': interactionCount,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'lastContactedAt': lastContactedAt?.toUtc().toIso8601String(),
      'photoPath': photoPath,
      'photo': photo,
      'valueTypes': valueTypes,
      'fieldUpdatedAt': fieldUpdatedAt.map(
        (String key, DateTime value) => MapEntry<String, String>(
          key,
          value.toUtc().toIso8601String(),
        ),
      ),
    };
  }

  String toStoragePayload() {
    return jsonEncode(toJson());
  }

  VaultContact copyWith({
    String? id,
    String? displayName,
    String? firstName,
    String? lastName,
    String? company,
    String? notes,
    List<String>? phones,
    List<String>? emails,
    List<String>? addresses,
    List<String>? labels,
    List<String>? birthdays,
    List<String>? other,
    String? source,
    bool? isFavorite,
    bool? isPinned,
    bool? isBlocked,
    Object? blockReason = _absent,
    int? interactionCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastContactedAt,
    Map<String, DateTime>? fieldUpdatedAt,
    // Use Object? + sentinel so callers can pass explicit null to clear photoPath.
    Object? photoPath = _absent,
    Object? photo = _absent,
    Map<String, String>? valueTypes,
  }) {
    return VaultContact(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      company: company ?? this.company,
      notes: notes ?? this.notes,
      phones: phones ?? this.phones,
      emails: emails ?? this.emails,
      addresses: addresses ?? this.addresses,
      labels: labels ?? this.labels,
      birthdays: birthdays ?? this.birthdays,
      other: other ?? this.other,
      source: source ?? this.source,
      isFavorite: isFavorite ?? this.isFavorite,
      isPinned: isPinned ?? this.isPinned,
      isBlocked: isBlocked ?? this.isBlocked,
      blockReason: identical(blockReason, _absent) ? this.blockReason : blockReason as String?,
      interactionCount: interactionCount ?? this.interactionCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      fieldUpdatedAt: fieldUpdatedAt ?? this.fieldUpdatedAt,
      photoPath: identical(photoPath, _absent) ? this.photoPath : photoPath as String?,
      photo: identical(photo, _absent)
          ? this.photo
          : photo as Map<String, Object?>?,
      valueTypes: valueTypes ?? this.valueTypes,
    );
  }

  VaultContact applyEdits({
    String? displayName,
    String? firstName,
    String? lastName,
    String? company,
    String? notes,
    List<String>? phones,
    List<String>? emails,
    List<String>? addresses,
    List<String>? labels,
    List<String>? birthdays,
    List<String>? other,
    bool? isFavorite,
    bool? isPinned,
    bool? isBlocked,
    String? blockReason,
    bool clearBlockReason = false,
    String? source,
    /// Provide the contact id to set/keep a photo, or use [clearPhoto] to remove it.
    String? photoPath,
    bool clearPhoto = false,
    /// A new photo (`ZtAttachmentRef` JSON). Replaces any earlier one.
    Map<String, Object?>? photo,
    /// Kinds to set, by [typeKey]. Merged over the current ones; kinds of
    /// values the contact no longer has are dropped.
    Map<String, String>? valueTypes,
  }) {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, DateTime> updates =
        Map<String, DateTime>.from(fieldUpdatedAt);

    void touch(String key) {
      updates[key] = now;
    }

    final String nextDisplayName = displayName ?? this.displayName;
    final String nextFirstName = firstName ?? this.firstName;
    final String nextLastName = lastName ?? this.lastName;
    final String nextCompany = company ?? this.company;
    final String nextNotes = notes ?? this.notes;
    final List<String> nextPhones = phones ?? this.phones;
    final List<String> nextEmails = emails ?? this.emails;
    final List<String> nextAddresses = addresses ?? this.addresses;
    final List<String> nextLabels = labels ?? this.labels;
    final List<String> nextBirthdays = birthdays ?? this.birthdays;
    final List<String> nextOther = other ?? this.other;
    final bool nextFavorite = isFavorite ?? this.isFavorite;
    final bool nextPinned = isPinned ?? this.isPinned;
    final bool nextBlocked = isBlocked ?? this.isBlocked;
    final String? nextBlockReason = clearBlockReason ? null : (blockReason ?? this.blockReason);
    final String nextSource = source ?? this.source;
    final String? nextPhotoPath = clearPhoto || photo != null
        ? null
        : (photoPath ?? this.photoPath);
    final Map<String, Object?>? nextPhoto =
        clearPhoto ? null : (photo ?? this.photo);

    final Map<String, String> nextTypes = _prunedTypes(
      <String, String>{...this.valueTypes, ...?valueTypes},
      nextPhones,
      nextEmails,
      nextAddresses,
    );
    if (!_equalMaps(nextTypes, this.valueTypes)) touch('valueTypes');

    if (nextDisplayName != this.displayName) touch('displayName');
    if (nextFirstName != this.firstName) touch('firstName');
    if (nextLastName != this.lastName) touch('lastName');
    if (nextCompany != this.company) touch('company');
    if (nextNotes != this.notes) touch('notes');
    if (!_equalLists(nextPhones, this.phones)) touch('phones');
    if (!_equalLists(nextEmails, this.emails)) touch('emails');
    if (!_equalLists(nextAddresses, this.addresses)) touch('addresses');
    if (!_equalLists(nextLabels, this.labels)) touch('labels');
    if (!_equalLists(nextBirthdays, this.birthdays)) touch('birthdays');
    if (!_equalLists(nextOther, this.other)) touch('other');
    if (nextFavorite != this.isFavorite) touch('isFavorite');
    if (nextPinned != this.isPinned) touch('isPinned');
    if (nextBlocked != this.isBlocked) touch('isBlocked');
    if (nextBlockReason != this.blockReason) touch('blockReason');
    if (nextSource != this.source) touch('source');
    if (nextPhotoPath != this.photoPath) touch('photoPath');
    if (!identical(nextPhoto, this.photo)) touch('photo');

    final String computedDisplayName = _buildDisplayName(
      explicitDisplayName: nextDisplayName,
      firstName: nextFirstName,
      lastName: nextLastName,
      company: nextCompany,
      phones: nextPhones,
    );

    return copyWith(
      displayName: computedDisplayName,
      firstName: nextFirstName,
      lastName: nextLastName,
      company: nextCompany,
      notes: nextNotes,
      phones: nextPhones,
      emails: nextEmails,
      addresses: nextAddresses,
      labels: nextLabels,
      birthdays: nextBirthdays,
      other: nextOther,
      source: nextSource,
      isFavorite: nextFavorite,
      isPinned: nextPinned,
      isBlocked: nextBlocked,
      blockReason: nextBlockReason,
      updatedAt: now,
      fieldUpdatedAt: updates,
      photoPath: nextPhotoPath,
      photo: nextPhoto,
      valueTypes: nextTypes,
    )._withDefaultFieldTimestamps();
  }

  /// This contact saved as a brand-new edit of every field, so it wins over
  /// the current version on every device (used to undo changes).
  VaultContact asNewEdit() {
    final DateTime now = DateTime.now().toUtc();
    return copyWith(
      updatedAt: now,
      fieldUpdatedAt: <String, DateTime>{
        for (final String field in mergeableFields) field: now,
      },
    );
  }

  /// Whether [other] holds the same details as this contact, ignoring edit
  /// times, interaction counts and the photo.
  bool sameDetailsAs(VaultContact other) {
    Map<String, dynamic> details(VaultContact c) => c.toJson()
      ..remove('updatedAt')
      ..remove('fieldUpdatedAt')
      ..remove('interactionCount')
      ..remove('lastContactedAt')
      ..remove('photo')
      ..remove('photoPath');
    return jsonEncode(details(this)) == jsonEncode(details(other));
  }

  VaultContact registerInteraction() {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, DateTime> updates =
        Map<String, DateTime>.from(fieldUpdatedAt)
          ..['interactionCount'] = now
          ..['lastContactedAt'] = now;
    return copyWith(
      interactionCount: interactionCount + 1,
      lastContactedAt: now,
      updatedAt: now,
      fieldUpdatedAt: updates,
    );
  }

  VaultContact mergeWith(VaultContact other) {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, DateTime> mergedFieldTimes = <String, DateTime>{};

    T choose<T>({
      required String field,
      required T localValue,
      required T remoteValue,
    }) {
      final DateTime localTime = fieldUpdatedAt[field] ?? updatedAt;
      final DateTime remoteTime =
          other.fieldUpdatedAt[field] ?? other.updatedAt;
      final bool useRemote = remoteTime.isAfter(localTime);
      mergedFieldTimes[field] = useRemote ? remoteTime : localTime;
      return useRemote ? remoteValue : localValue;
    }

    List<String> mergeList({
      required String field,
      required List<String> localValue,
      required List<String> remoteValue,
      String Function(String)? normalizer,
    }) {
      final DateTime localTime = fieldUpdatedAt[field] ?? updatedAt;
      final DateTime remoteTime =
          other.fieldUpdatedAt[field] ?? other.updatedAt;
      mergedFieldTimes[field] =
          localTime.isAfter(remoteTime) ? localTime : remoteTime;

      final bool remoteNewer = remoteTime.isAfter(localTime);
      final List<String> merged = <String>[];
      final Set<String> seen = <String>{};

      void addValues(List<String> values) {
        for (final String raw in values) {
          final String trimmed = raw.trim();
          if (trimmed.isEmpty) {
            continue;
          }
          final String key =
              (normalizer?.call(trimmed) ?? trimmed.toLowerCase());
          if (seen.add(key)) {
            merged.add(trimmed);
          }
        }
      }

      if (remoteNewer) {
        addValues(remoteValue);
        addValues(localValue);
      } else {
        addValues(localValue);
        addValues(remoteValue);
      }

      return merged;
    }

    final DateTime myTypesTime = fieldUpdatedAt['valueTypes'] ?? updatedAt;
    final DateTime otherTypesTime =
        other.fieldUpdatedAt['valueTypes'] ?? other.updatedAt;
    mergedFieldTimes['valueTypes'] =
        myTypesTime.isAfter(otherTypesTime) ? myTypesTime : otherTypesTime;

    final DateTime mergedCreatedAt =
        createdAt.isBefore(other.createdAt) ? createdAt : other.createdAt;
    final DateTime mergedUpdatedAt =
        updatedAt.isAfter(other.updatedAt) ? updatedAt : other.updatedAt;

    return VaultContact(
      id: id,
      displayName: choose<String>(
        field: 'displayName',
        localValue: displayName,
        remoteValue: other.displayName,
      ),
      firstName: choose<String>(
        field: 'firstName',
        localValue: firstName,
        remoteValue: other.firstName,
      ),
      lastName: choose<String>(
        field: 'lastName',
        localValue: lastName,
        remoteValue: other.lastName,
      ),
      company: choose<String>(
        field: 'company',
        localValue: company,
        remoteValue: other.company,
      ),
      notes: choose<String>(
        field: 'notes',
        localValue: notes,
        remoteValue: other.notes,
      ),
      phones: mergeList(
        field: 'phones',
        localValue: phones,
        remoteValue: other.phones,
        normalizer: normalizedPhone,
      ),
      emails: mergeList(
        field: 'emails',
        localValue: emails,
        remoteValue: other.emails,
        normalizer: normalizedEmail,
      ),
      addresses: mergeList(
        field: 'addresses',
        localValue: addresses,
        remoteValue: other.addresses,
      ),
      labels: mergeList(
        field: 'labels',
        localValue: labels,
        remoteValue: other.labels,
        normalizer: (String value) => value.toLowerCase(),
      ),
      birthdays: mergeList(
        field: 'birthdays',
        localValue: birthdays,
        remoteValue: other.birthdays,
      ),
      other: mergeList(
        field: 'other',
        localValue: this.other,
        remoteValue: other.other,
      ),
      source: choose<String>(
        field: 'source',
        localValue: source,
        remoteValue: other.source,
      ),
      isFavorite: choose<bool>(
        field: 'isFavorite',
        localValue: isFavorite,
        remoteValue: other.isFavorite,
      ),
      isPinned: choose<bool>(
        field: 'isPinned',
        localValue: isPinned,
        remoteValue: other.isPinned,
      ),
      isBlocked: choose<bool>(
        field: 'isBlocked',
        localValue: isBlocked,
        remoteValue: other.isBlocked,
      ),
      blockReason: choose<String?>(
        field: 'blockReason',
        localValue: blockReason,
        remoteValue: other.blockReason,
      ),
      interactionCount: choose<int>(
        field: 'interactionCount',
        localValue: interactionCount,
        remoteValue: other.interactionCount,
      ),
      createdAt: mergedCreatedAt,
      updatedAt: mergedUpdatedAt.isAfter(now) ? mergedUpdatedAt : now,
      lastContactedAt: choose<DateTime?>(
        field: 'lastContactedAt',
        localValue: lastContactedAt,
        remoteValue: other.lastContactedAt,
      ),
      fieldUpdatedAt: mergedFieldTimes,
      photoPath: choose<String?>(
        field: 'photoPath',
        localValue: photoPath,
        remoteValue: other.photoPath,
      ),
      photo: choose<Map<String, Object?>?>(
        field: 'photo',
        localValue: photo,
        remoteValue: other.photo,
      ),
      // Both sides' kinds, the newer side winning where they differ.
      valueTypes: (fieldUpdatedAt['valueTypes'] ?? updatedAt).isBefore(
              other.fieldUpdatedAt['valueTypes'] ?? other.updatedAt)
          ? <String, String>{...valueTypes, ...other.valueTypes}
          : <String, String>{...other.valueTypes, ...valueTypes},
    )._withDefaultFieldTimestamps();
  }

  bool get isSavedContact => source == 'Saved';

  String get searchableText {
    final List<String> parts = <String>[
      displayName,
      firstName,
      lastName,
      company,
      notes,
      phones.join(' '),
      emails.join(' '),
      labels.join(' '),
      other.join(' '),
    ];
    return parts.join(' ').toLowerCase();
  }

  DateTime? get nextBirthday {
    if (birthdays.isEmpty) {
      return null;
    }
    final DateTime now = DateTime.now();
    DateTime? closest;
    for (final String raw in birthdays) {
      final DateTime? parsed = _parseDate(raw) ?? _parseYearlessDate(raw);
      if (parsed == null) {
        continue;
      }
      final DateTime candidate = DateTime(now.year, parsed.month, parsed.day);
      final DateTime normalized =
          candidate.isBefore(DateTime(now.year, now.month, now.day))
              ? DateTime(now.year + 1, parsed.month, parsed.day)
              : candidate;
      if (closest == null || normalized.isBefore(closest)) {
        closest = normalized;
      }
    }
    return closest;
  }

  int? get daysUntilBirthday {
    final DateTime? date = nextBirthday;
    if (date == null) {
      return null;
    }
    return date
        .difference(DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day))
        .inDays;
  }

  bool get isStale {
    final DateTime threshold =
        DateTime.now().toUtc().subtract(const Duration(days: 90));
    final DateTime activity = lastContactedAt ?? updatedAt;
    return activity.isBefore(threshold);
  }

  String get fingerprint => jsonEncode(toJson());

  VaultContact _withDefaultFieldTimestamps() {
    final Map<String, DateTime> updated =
        Map<String, DateTime>.from(fieldUpdatedAt);
    for (final String field in mergeableFields) {
      updated[field] = updated[field] ?? updatedAt;
    }
    return copyWith(fieldUpdatedAt: updated);
  }

  static String generateId() {
    final Random random = Random.secure();
    return 'c_${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
  }

  static String normalizedName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String normalizedPhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  static String normalizedEmail(String value) {
    return value.trim().toLowerCase();
  }

  static String _buildDisplayName({
    required String explicitDisplayName,
    required String firstName,
    required String lastName,
    required String company,
    required List<String> phones,
  }) {
    if (explicitDisplayName.trim().isNotEmpty) {
      return explicitDisplayName.trim();
    }
    final String fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    if (company.trim().isNotEmpty) {
      return company.trim();
    }
    if (phones.isNotEmpty) {
      return phones.first;
    }
    return 'Unnamed Contact';
  }

  static String _readString(dynamic value) {
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }

  static Map<String, Object?>? _readMap(dynamic value) =>
      value is Map ? Map<String, Object?>.from(value) : null;

  static Map<String, String> _readTypes(dynamic value) => value is Map
      ? <String, String>{
          for (final MapEntry<dynamic, dynamic> e in value.entries)
            if (e.value != null && '${e.value}'.isNotEmpty)
              '${e.key}': '${e.value}'.toLowerCase(),
        }
      : const <String, String>{};

  static bool _equalMaps(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((MapEntry<String, String> e) => b[e.key] == e.value);

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return <String>[];
    }
    return value
        .map((dynamic entry) => entry.toString().trim())
        .where((String entry) => entry.isNotEmpty)
        .toList();
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  /// Parses `--MM-DD`, the format Google and vCard use for birthdays
  /// without a year.
  static DateTime? _parseYearlessDate(String value) {
    final RegExpMatch? match =
        RegExp(r'^--(\d{2})-?(\d{2})$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final int month = int.parse(match.group(1)!);
    final int day = int.parse(match.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return DateTime(2000, month, day);
  }

  static bool _equalLists(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

class ContactDuplicateGroup {
  ContactDuplicateGroup({
    required this.reason,
    required this.contacts,
  });

  final String reason;
  final List<VaultContact> contacts;
}

class ContactHealthSummary {
  ContactHealthSummary({
    required this.upcomingBirthdays,
    required this.staleContacts,
    required this.missingPhoneContacts,
  });

  final List<VaultContact> upcomingBirthdays;
  final List<VaultContact> staleContacts;
  final List<VaultContact> missingPhoneContacts;
}
