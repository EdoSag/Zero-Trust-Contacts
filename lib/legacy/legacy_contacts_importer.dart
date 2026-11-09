import 'dart:convert';
import 'dart:typed_data';

import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_crypto.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_source.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';

/// The earlier contacts can't be read without the account password as it
/// was before the update (the device doesn't have the old key).
class LegacyPasswordNeeded implements Exception {
  const LegacyPasswordNeeded({this.wrongPassword = false});

  /// A password was given and it doesn't open the old contacts.
  final bool wrongPassword;

  @override
  String toString() => 'LegacyPasswordNeeded(wrong: $wrongPassword)';
}

/// Moves contacts saved before the update into the account's synced store,
/// once per device:
///
/// - the cloud copy (`encrypted_contacts`), decrypted with the old key;
/// - this device's old database, which may hold edits never uploaded, but
///   only when this device's old key is proven to be this account's (the old
///   version kept one database for whoever signed in last);
///
/// merged field by field as the old sync did. Like the core's
/// `LegacyImporter`, it syncs first and never replaces a contact that is
/// already in the store (another device imported it, maybe edited it since),
/// and imported contacts are dated before any real edit.
class LegacyContactsImporter {
  LegacyContactsImporter({
    required this.source,
    required this.engine,
    required this.ledger,
    this.kdf = LegacyContactsCrypto.params,
  });

  static const String sourceId = 'contacts-v1';

  final LegacyContactsSource source;
  final ItemSyncEngine engine;
  final LegacyImportLedger ledger;
  final KdfParams kdf;

  Future<bool> isDone() => ledger.legacyImportDone(sourceId);

  /// Imports, and returns how many contacts were added. [preCoreAccount] is
  /// whether the account was made before the core (it unlocked with a
  /// legacy key); other accounts have nothing to import. Throws
  /// [LegacyPasswordNeeded] when [password] is needed or wrong; network
  /// errors leave the import to run again later.
  Future<int> run({required bool preCoreAccount, String? password}) async {
    if (await isDone()) return 0;
    if (!preCoreAccount) {
      await ledger.markLegacyImportDone(sourceId);
      return 0;
    }

    final String? rawBlob = await source.fetchCloudBlob();
    final Map<String, dynamic>? blob = _jsonMap(rawBlob);
    final bool hasLocal = await source.hasLocalDatabase();
    if (blob == null && !hasLocal) {
      await ledger.markLegacyImportDone(sourceId);
      return 0;
    }

    final Uint8List? deviceKey = await source.readDeviceKey();
    Uint8List? typedKey;
    if (password != null) {
      final String? salt = await source.fetchLegacySalt();
      if (salt == null) throw const LegacyPasswordNeeded(wrongPassword: true);
      typedKey = await LegacyContactsCrypto.deriveKey(
          password: password, legacySalt: salt, kdf: kdf);
    }

    // Which old key is this account's: the one that opens its cloud copy,
    // else the one derived from the password just typed.
    final bool encrypted =
        blob != null && LegacyContactsCrypto.isEncrypted(blob);
    Uint8List? accountKey;
    List<VaultContact> cloud = const <VaultContact>[];
    if (encrypted) {
      for (final Uint8List? key in <Uint8List?>[typedKey, deviceKey]) {
        if (key == null) continue;
        final String? plain = await LegacyContactsCrypto.decryptBlob(blob, key);
        if (plain != null) {
          accountKey = key;
          cloud = _contactsIn(_jsonMap(plain));
          break;
        }
      }
      if (accountKey == null) {
        throw LegacyPasswordNeeded(wrongPassword: password != null);
      }
    } else {
      accountKey = typedKey;
      cloud = _contactsIn(blob);
    }

    final bool localIsThisAccounts = hasLocal &&
        deviceKey != null &&
        accountKey != null &&
        _sameBytes(deviceKey, accountKey);
    if (hasLocal && !localIsThisAccounts && password == null) {
      // Can't tell whose the old on-device contacts are, and they may hold
      // edits that never reached the cloud: ask once for the password.
      throw const LegacyPasswordNeeded();
    }
    final List<VaultContact> local = localIsThisAccounts
        ? await source.readLocalContacts(key: deviceKey)
        : const <VaultContact>[];

    final List<VaultContact> merged = mergeLegacy(cloud, local);
    await engine.sync();
    var imported = 0;
    for (final VaultContact contact in merged) {
      if (await engine.store.get(contact.id) != null) continue;
      await engine.save(contact.id, contactsCollection.encode(contact),
          at: LegacyImporter.importedAt);
      imported++;
    }
    await ledger.markLegacyImportDone(sourceId);
    if (localIsThisAccounts || !hasLocal) await source.forgetDeviceData();
    return imported;
  }

  /// The old sync's merge: union by id, field-level newest wins.
  static List<VaultContact> mergeLegacy(
      List<VaultContact> cloud, List<VaultContact> local) {
    final Map<String, VaultContact> byId = <String, VaultContact>{
      for (final VaultContact c in cloud) c.id: c,
    };
    for (final VaultContact c in local) {
      final VaultContact? other = byId[c.id];
      byId[c.id] = other == null || other.fingerprint == c.fingerprint
          ? c
          : c.mergeWith(other);
    }
    return byId.values.toList();
  }

  static List<VaultContact> _contactsIn(Map<String, dynamic>? root) {
    final Object? raw = root?['contacts'];
    if (raw is! List) return const <VaultContact>[];
    return <VaultContact>[
      for (final Object? item in raw)
        if (item is Map)
          if (Map<String, dynamic>.from(item) case final map)
            map.containsKey('fieldUpdatedAt')
                ? VaultContact.fromJson(map)
                : VaultContact.fromLegacyPayload(map),
    ];
  }

  static Map<String, dynamic>? _jsonMap(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Moves photos stored the old way (a plain JPEG on the phone and in the
/// `contactsProfilePictures` bucket) into encrypted attachments. Runs after
/// every unlock until no contact has an old photo left; the old bucket
/// files are left in place for now.
class LegacyPhotoMover {
  LegacyPhotoMover({
    required this.source,
    required this.photos,
    required this.load,
    required this.find,
    required this.save,
  });

  final LegacyContactsSource source;
  final ContactPhotos photos;
  final Future<List<VaultContact>> Function() load;
  final Future<VaultContact?> Function(String id) find;
  final Future<void> Function(VaultContact contact) save;

  /// Returns how many photos were moved. Stops at the first photo that
  /// can't be fetched right now, to try again later.
  Future<int> run() async {
    var moved = 0;
    for (final VaultContact contact in await load()) {
      if (contact.photoPath == null || contact.photo != null) continue;
      final Uint8List? bytes;
      try {
        bytes = await source.readPhoto(contact.id);
      } on LegacyPhotoUnavailable {
        break;
      }
      final Map<String, Object?>? stored =
          bytes == null ? null : await photos.store(bytes);
      // The list stays usable meanwhile: apply the move to the contact as
      // it is now, so an edit made during the upload isn't overwritten.
      final VaultContact? current = await find(contact.id);
      if (current == null ||
          current.photoPath == null ||
          current.photo != null) {
        // Deleted, or given a new photo, in the meantime.
        if (stored != null) {
          await photos.deletePhotoOf(current?.copyWith(photo: stored) ??
              contact.copyWith(photo: stored));
        }
        await DeviceLegacyContactsSource.deleteLocalPhoto(contact.id);
        continue;
      }
      // A photo gone everywhere just stops being looked for.
      await save(current.copyWith(photo: stored, photoPath: null));
      if (stored != null) moved++;
      await DeviceLegacyContactsSource.deleteLocalPhoto(contact.id);
    }
    return moved;
  }
}
