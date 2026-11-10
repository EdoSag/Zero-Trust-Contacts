import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/phone_sync/phone_contacts_bridge.dart';

/// Which details of each contact leave the vault for the phone's own
/// contacts (where the dialer, caller ID and messaging apps can read them).
/// The name always goes; everything else is the user's choice.
class PhoneSyncFields {
  const PhoneSyncFields({
    this.phones = true,
    this.emails = false,
    this.photos = true,
    this.company = false,
    this.addresses = false,
    this.birthdays = false,
    this.notes = false,
    this.favourites = true,
    this.blockedToVoicemail = true,
  });

  final bool phones;
  final bool emails;
  final bool photos;
  final bool company;
  final bool addresses;
  final bool birthdays;
  final bool notes;

  /// Starred in the phone's contacts too.
  final bool favourites;

  /// Calls from contacts blocked in the vault go straight to voicemail.
  final bool blockedToVoicemail;

  PhoneSyncFields copyWith({
    bool? phones,
    bool? emails,
    bool? photos,
    bool? company,
    bool? addresses,
    bool? birthdays,
    bool? notes,
    bool? favourites,
    bool? blockedToVoicemail,
  }) =>
      PhoneSyncFields(
        phones: phones ?? this.phones,
        emails: emails ?? this.emails,
        photos: photos ?? this.photos,
        company: company ?? this.company,
        addresses: addresses ?? this.addresses,
        birthdays: birthdays ?? this.birthdays,
        notes: notes ?? this.notes,
        favourites: favourites ?? this.favourites,
        blockedToVoicemail: blockedToVoicemail ?? this.blockedToVoicemail,
      );

  /// Only what both this and [other] show. A change made on the phone is
  /// read with this while the choice of details is being switched, when
  /// some copies were written the old way and some the new: a detail
  /// counts as "on the phone" only if both ways put it there.
  PhoneSyncFields intersect(PhoneSyncFields other) => PhoneSyncFields(
        phones: phones && other.phones,
        emails: emails && other.emails,
        photos: photos && other.photos,
        company: company && other.company,
        addresses: addresses && other.addresses,
        birthdays: birthdays && other.birthdays,
        notes: notes && other.notes,
        favourites: favourites && other.favourites,
        blockedToVoicemail: blockedToVoicemail && other.blockedToVoicemail,
      );

  Map<String, bool> toJson() => <String, bool>{
        'phones': phones,
        'emails': emails,
        'photos': photos,
        'company': company,
        'addresses': addresses,
        'birthdays': birthdays,
        'notes': notes,
        'favourites': favourites,
        'blockedToVoicemail': blockedToVoicemail,
      };

  static PhoneSyncFields fromJson(Map<String, Object?> json) {
    const PhoneSyncFields d = PhoneSyncFields();
    bool read(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;
    return PhoneSyncFields(
      phones: read('phones', d.phones),
      emails: read('emails', d.emails),
      photos: read('photos', d.photos),
      company: read('company', d.company),
      addresses: read('addresses', d.addresses),
      birthdays: read('birthdays', d.birthdays),
      notes: read('notes', d.notes),
      favourites: read('favourites', d.favourites),
      blockedToVoicemail: read('blockedToVoicemail', d.blockedToVoicemail),
    );
  }
}

/// One contact as written to the phone (photo bytes are added separately,
/// only for entries that change).
class PhoneSyncEntry {
  PhoneSyncEntry({required this.id, required this.fields, required this.hash});

  final String id;

  /// Everything written except the photo; `photoId` names the photo.
  final Map<String, Object?> fields;

  /// Hash of [fields]: unchanged hash, nothing to rewrite.
  final String hash;

  String? get photoId => fields['photoId'] as String?;
}

/// What to write to and remove from the phone's contacts.
class PhoneSyncPlan {
  PhoneSyncPlan({required this.upserts, required this.deletes});

  final List<PhoneSyncEntry> upserts;
  final List<String> deletes;

  bool get isEmpty => upserts.isEmpty && deletes.isEmpty;
}

/// Works out the phone's copy of the vault. Pure Dart, so it is tested
/// without a phone.
class PhoneSyncPlanner {
  const PhoneSyncPlanner();

  PhoneSyncEntry entryFor(VaultContact c, PhoneSyncFields f) {
    final String? photoId =
        f.photos && c.photo != null ? '${c.photo!['id']}' : null;
    final Map<String, Object?> fields = <String, Object?>{
      'displayName': c.displayName,
      'firstName': c.firstName,
      'lastName': c.lastName,
      'phones': f.phones ? c.phones : const <String>[],
      'emails': f.emails ? c.emails : const <String>[],
      'company': f.company ? c.company : '',
      'addresses': f.addresses ? c.addresses : const <String>[],
      'birthdays': f.birthdays
          ? c.birthdays.map(_androidDate).whereType<String>().toList()
          : const <String>[],
      'notes': f.notes ? c.notes : '',
      'starred': f.favourites && c.isFavorite,
      'sendToVoicemail': f.blockedToVoicemail && f.phones && c.isBlocked,
      'photoId': photoId,
    };
    // The kinds (Mobile, Work…) go along only for contacts that have some,
    // so contacts without them keep the hash they were written with.
    void addTypes(String key, String field, bool on, List<String> values) {
      if (!on) return;
      final List<String> types = <String>[
        for (final String v in values) c.typeOf(field, v) ?? '',
      ];
      if (types.any((String t) => t.isNotEmpty)) fields[key] = types;
    }

    addTypes('phoneTypes', 'phone', f.phones, c.phones);
    addTypes('emailTypes', 'email', f.emails, c.emails);
    addTypes('addressTypes', 'address', f.addresses, c.addresses);
    final List<int> digest =
        const DartSha256().hashSync(utf8.encode(jsonEncode(fields))).bytes;
    final String hash = digest
        .take(16)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return PhoneSyncEntry(id: c.id, fields: fields, hash: hash);
  }

  /// [onPhone] is what the phone holds now (vault id -> hash).
  PhoneSyncPlan plan({
    required List<VaultContact> contacts,
    required PhoneSyncFields fields,
    required Map<String, String> onPhone,
  }) {
    final Set<String> keep = <String>{};
    final List<PhoneSyncEntry> upserts = <PhoneSyncEntry>[];
    for (final VaultContact contact in contacts) {
      if (!keep.add(contact.id)) continue;
      final PhoneSyncEntry entry = entryFor(contact, fields);
      if (onPhone[contact.id] != entry.hash) upserts.add(entry);
    }
    return PhoneSyncPlan(
      upserts: upserts,
      deletes: <String>[
        for (final String id in onPhone.keys)
          if (!keep.contains(id)) id,
      ],
    );
  }

  /// The vault contact after a change made to its copy in the phone's
  /// contacts ([change], from a contacts app), or a new vault contact when
  /// [current] is null (it was created on the phone).
  ///
  /// Details that are shown on the phone ([f]) become what the phone has
  /// now, so removing a number there removes it here. Details that are not
  /// shown on the phone can only be added to, never removed, since the
  /// phone never had them. Returns [current] itself when nothing changed.
  VaultContact mergePhoneEdit(
    VaultContact? current,
    PhoneChange change,
    PhoneSyncFields f,
  ) {
    final Map<String, Object?> p = change.fields;
    final Map<String, String> types = <String, String>{};
    List<String> typed(String key, String field) {
      final List<String> values = <String>[];
      final Object? rows = p[key];
      if (rows is List) {
        for (final Object? row in rows) {
          if (row is! Map) continue;
          final String value = '${row['value'] ?? ''}'.trim();
          if (value.isEmpty || values.contains(value)) continue;
          values.add(value);
          types[VaultContact.typeKey(field, value)] = '${row['type'] ?? ''}';
        }
      }
      return values;
    }

    String text(String key) => '${p[key] ?? ''}'.trim();
    final List<String> phones = typed('phones', 'phone');
    final List<String> emails = typed('emails', 'email');
    final List<String> addresses = typed('addresses', 'address');
    final List<String> birthdays = <String>[
      if (p['birthdays'] case final List<Object?> rows)
        for (final Object? row in rows)
          if ('${row ?? ''}'.trim().isNotEmpty) '$row'.trim(),
    ];
    String firstName = text('firstName');
    String lastName = text('lastName');
    final String displayName = text('displayName');
    if (firstName.isEmpty && lastName.isEmpty) {
      firstName = displayName;
    }

    if (current == null) {
      final DateTime now = DateTime.now().toUtc();
      return VaultContact.fromLegacyPayload(<String, dynamic>{
        'id': VaultContact.generateId(),
        'displayName': displayName,
        'firstName': firstName,
        'lastName': lastName,
        'company': text('company'),
        'notes': text('notes'),
        'phones': phones,
        'emails': emails,
        'addresses': addresses,
        'birthdays': birthdays,
        'isFavorite': p['starred'] == true,
        'valueTypes': <String, String>{
          for (final MapEntry<String, String> e in types.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        },
        'source': 'Saved',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
    }

    final Map<String, Object?> written = entryFor(current, f).fields;
    bool same(List<String> a, Object? b) =>
        b is List && a.length == b.length && a.join('\n') == b.join('\n');

    /// The new list for a detail, or null to leave it alone.
    List<String>? list(
      bool shown,
      List<String> onPhone,
      List<String> inVault,
      String writtenKey,
    ) {
      if (shown) {
        return same(onPhone, written[writtenKey]) ? null : onPhone;
      }
      final Set<String> have = inVault
          .map((String v) => v.trim().toLowerCase())
          .toSet();
      final List<String> extra = onPhone
          .where((String v) => have.add(v.trim().toLowerCase()))
          .toList();
      return extra.isEmpty ? null : <String>[...inVault, ...extra];
    }

    String? single(bool shown, String onPhone, String inVault) {
      if (shown) {
        return onPhone == inVault ? null : onPhone;
      }
      return inVault.isEmpty && onPhone.isNotEmpty ? onPhone : null;
    }

    // Android fills in first and last name by splitting the full name, so
    // only a different full name counts as a change made on the phone.
    final String phoneName = VaultContact.normalizedName(
      displayName.isNotEmpty ? displayName : '$firstName $lastName',
    );
    final bool nameChanged =
        phoneName.isNotEmpty &&
        phoneName != VaultContact.normalizedName(current.displayName);
    final List<String>? newPhones = list(
      f.phones,
      phones,
      current.phones,
      'phones',
    );
    final List<String>? newEmails = list(
      f.emails,
      emails,
      current.emails,
      'emails',
    );
    final List<String>? newAddresses = list(
      f.addresses,
      addresses,
      current.addresses,
      'addresses',
    );
    final List<String>? newBirthdays = list(
      f.birthdays,
      birthdays,
      current.birthdays,
      'birthdays',
    );
    final String? company = single(f.company, text('company'), current.company);
    final String? notes = single(f.notes, text('notes'), current.notes);
    final bool? favourite =
        f.favourites && (p['starred'] == true) != current.isFavorite
        ? p['starred'] == true
        : null;
    // Kinds only for values the phone has; '' clears one removed there.
    final Map<String, String> newTypes = <String, String>{
      for (final MapEntry<String, String> e in types.entries)
        if ((current.valueTypes[e.key] ?? '') != e.value) e.key: e.value,
    };

    final bool changed =
        nameChanged ||
        newTypes.isNotEmpty ||
        <Object?>[
          newPhones,
          newEmails,
          newAddresses,
          newBirthdays,
          company,
          notes,
          favourite,
        ].any((Object? v) => v != null);
    if (!changed) {
      return current;
    }
    return current.applyEdits(
      displayName: nameChanged
          ? (displayName.isNotEmpty
                ? displayName
                : '$firstName $lastName'.trim())
          : null,
      firstName: nameChanged ? firstName : null,
      lastName: nameChanged ? lastName : null,
      phones: newPhones,
      emails: newEmails,
      addresses: newAddresses,
      birthdays: newBirthdays,
      company: company,
      notes: notes,
      isFavorite: favourite,
      valueTypes: newTypes.isEmpty ? null : newTypes,
    );
  }

  /// Android wants `yyyy-MM-dd`, or `--MM-dd` without a year.
  static String? _androidDate(String raw) {
    final String v = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ||
        RegExp(r'^--\d{2}-\d{2}$').hasMatch(v)) {
      return v;
    }
    final DateTime? parsed = DateTime.tryParse(v);
    if (parsed == null) return null;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)}';
  }
}
