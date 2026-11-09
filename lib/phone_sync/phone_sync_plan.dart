import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

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
