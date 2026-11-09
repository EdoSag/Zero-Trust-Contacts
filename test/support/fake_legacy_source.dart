import 'dart:typed_data';

import 'package:zerotrust_contacts/legacy/legacy_contacts_source.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// The pre-core data of one account on one device, in memory.
class FakeLegacySource implements LegacyContactsSource {
  FakeLegacySource({
    this.cloudBlob,
    this.legacySalt,
    this.deviceKey,
    this.localContacts,
    this.offline = false,
    Map<String, Uint8List>? photos,
  }) : photos = photos ?? <String, Uint8List>{};

  String? cloudBlob;
  String? legacySalt;
  Uint8List? deviceKey;

  /// Null: no old database on this device.
  List<VaultContact>? localContacts;
  final Map<String, Uint8List> photos;
  bool forgotten = false;
  bool offline;

  @override
  Future<String?> fetchCloudBlob() async {
    if (offline) throw StateError('offline');
    return cloudBlob;
  }

  @override
  Future<String?> fetchLegacySalt() async => legacySalt;

  @override
  Future<Uint8List?> readDeviceKey() async => deviceKey;

  @override
  Future<bool> hasLocalDatabase() async => localContacts != null;

  @override
  Future<List<VaultContact>> readLocalContacts({Uint8List? key}) async =>
      localContacts ?? const <VaultContact>[];

  @override
  Future<void> forgetDeviceData() async {
    forgotten = true;
    localContacts = null;
    deviceKey = null;
  }

  @override
  Future<Uint8List?> readPhoto(String contactId) async {
    if (offline) throw const LegacyPhotoUnavailable('offline');
    return photos[contactId];
  }
}
