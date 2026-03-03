import 'dart:convert';
import 'dart:math';

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
    required this.interactionCount,
    required this.createdAt,
    required this.updatedAt,
    required this.fieldUpdatedAt,
    this.lastContactedAt,
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
  final int interactionCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastContactedAt;
  final Map<String, DateTime> fieldUpdatedAt;

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
    'interactionCount',
    'lastContactedAt',
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
      interactionCount: _readInt(json['interactionCount']),
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      lastContactedAt: lastContactedAt?.toUtc(),
      fieldUpdatedAt: fieldUpdatedAt,
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
      interactionCount: _readInt(payload['interactionCount']),
      createdAt: _parseDate(payload['createdAt'])?.toUtc() ?? now,
      updatedAt: _parseDate(payload['updatedAt'])?.toUtc() ?? now,
      lastContactedAt: _parseDate(payload['lastContactedAt'])?.toUtc(),
      fieldUpdatedAt: <String, DateTime>{},
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
      'interactionCount': interactionCount,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'lastContactedAt': lastContactedAt?.toUtc().toIso8601String(),
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
    int? interactionCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastContactedAt,
    Map<String, DateTime>? fieldUpdatedAt,
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
      interactionCount: interactionCount ?? this.interactionCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      fieldUpdatedAt: fieldUpdatedAt ?? this.fieldUpdatedAt,
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
    String? source,
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
    final String nextSource = source ?? this.source;

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
    if (nextSource != this.source) touch('source');

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
      updatedAt: now,
      fieldUpdatedAt: updates,
    )._withDefaultFieldTimestamps();
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
      final DateTime? parsed = _parseDate(raw);
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
