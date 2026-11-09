import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Thrown when an old photo can't be fetched right now (offline, server
/// error); the move is retried later. A photo that is simply gone is not an
/// error ([LegacyContactsSource.readPhoto] returns null).
class LegacyPhotoUnavailable implements Exception {
  const LegacyPhotoUnavailable(this.cause);
  final Object cause;
  @override
  String toString() => 'LegacyPhotoUnavailable($cause)';
}

/// Where Contacts kept data before it moved onto the core.
abstract interface class LegacyContactsSource {
  /// Contacts in the old on-device database, or empty when there is none.
  /// [key] is this device's old key, for a database that was encrypted.
  Future<List<VaultContact>> readLocalContacts({Uint8List? key});

  /// Whether the old on-device database exists.
  Future<bool> hasLocalDatabase();

  /// The account's `encrypted_contacts.data_blob`, or null without one.
  Future<String?> fetchCloudBlob();

  /// The account's pre-core `profiles.salt`.
  Future<String?> fetchLegacySalt();

  /// The old key this device kept in secure storage, if the app was
  /// updated in place.
  Future<Uint8List?> readDeviceKey();

  /// Deletes the old on-device database and the secrets the old version
  /// kept (its key, cached blob, restore points), once imported.
  Future<void> forgetDeviceData();

  /// An old photo: from this device's old photo folder, else from the old
  /// `contactsProfilePictures` bucket. Null when neither has it.
  Future<Uint8List?> readPhoto(String contactId);
}

class DeviceLegacyContactsSource implements LegacyContactsSource {
  DeviceLegacyContactsSource({
    required this.userId,
    SupabaseClient? client,
    FlutterSecureStorage? secureStorage,
  })  : _client = client ?? Supabase.instance.client,
        _secure = secureStorage ?? const FlutterSecureStorage();

  final String userId;
  final SupabaseClient _client;
  final FlutterSecureStorage _secure;

  static const String _dbName = 'vault_contacts.db';
  static const String _photoBucket = 'contactsProfilePictures';

  /// Secure-storage keys the pre-core version wrote.
  static const List<String> _oldSecureKeys = <String>[
    'vault_pbkdf2_salt',
    'encrypted_db_key',
    'biometric_enabled',
    'cached_cloud_vault_blob',
    'security_activity_log_v1',
    'vault_snapshots_v1',
    'vault_last_sync_at',
    'vault_pending_conflicts_v1',
  ];

  /// sqflite's database folder: `<data>/databases` on Android, the
  /// Documents folder on iOS.
  Future<File?> _databaseFile() async {
    final List<String> candidates = <String>[];
    if (Platform.isAndroid) {
      final Directory support = await getApplicationSupportDirectory();
      candidates.add('${support.parent.path}/databases/$_dbName');
    }
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      candidates.add('${docs.path}/$_dbName');
    } on Object {
      // No documents folder on this platform.
    }
    for (final String path in candidates) {
      final File file = File(path);
      if (await file.exists()) return file;
    }
    return null;
  }

  @override
  Future<bool> hasLocalDatabase() async => await _databaseFile() != null;

  @override
  Future<List<VaultContact>> readLocalContacts({Uint8List? key}) async {
    final File? file = await _databaseFile();
    if (file == null) return const <VaultContact>[];
    return readContactsDatabase(file.path, key: key);
  }

  /// Reads the old `contacts(payload)` table. Old versions asked for
  /// SQLCipher, but sqflite runs on the platform's own SQLite, which
  /// ignores `PRAGMA key`, so the file is normally plain SQLite; a
  /// SQLCipher file is opened with [key] as a fallback.
  static List<VaultContact> readContactsDatabase(String path,
      {Uint8List? key}) {
    List<VaultContact> query(Database db) => <VaultContact>[
          for (final Row row
              in db.select('select payload from contacts order by id desc'))
            if (_decode(row['payload']) case final VaultContact contact)
              contact,
        ];

    final Database plain = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return query(plain);
    } on SqliteException {
      if (key == null) rethrow;
    } finally {
      plain.close();
    }
    final Database cipher = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      cipher.execute("PRAGMA cipher = 'sqlcipher'");
      cipher.execute('PRAGMA legacy = 4');
      cipher.execute("PRAGMA key = '${ZtBase64.encode(key)}'");
      return query(cipher);
    } finally {
      cipher.close();
    }
  }

  static VaultContact? _decode(Object? payload) {
    if (payload is! String || payload.trim().isEmpty) return null;
    try {
      final Object? json = jsonDecode(payload);
      if (json is! Map) return null;
      final Map<String, dynamic> map = Map<String, dynamic>.from(json);
      return map.containsKey('fieldUpdatedAt')
          ? VaultContact.fromJson(map)
          : VaultContact.fromLegacyPayload(map);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<String?> fetchCloudBlob() async {
    final Map<String, dynamic>? row = await _client
        .from('encrypted_contacts')
        .select('data_blob')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['data_blob'] as String?;
  }

  @override
  Future<String?> fetchLegacySalt() async {
    final Map<String, dynamic>? row = await _client
        .from('profiles')
        .select('salt')
        .eq('id', userId)
        .maybeSingle();
    return row?['salt'] as String?;
  }

  @override
  Future<Uint8List?> readDeviceKey() async {
    try {
      final String? encoded = await _secure.read(key: 'encrypted_db_key');
      if (encoded == null || encoded.isEmpty) return null;
      return ZtBase64.decode(encoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> forgetDeviceData() async {
    final File? file = await _databaseFile();
    if (file != null) {
      for (final String suffix in <String>['', '-journal', '-wal', '-shm']) {
        final File part = File('${file.path}$suffix');
        if (await part.exists()) await part.delete();
      }
    }
    for (final String key in _oldSecureKeys) {
      try {
        await _secure.delete(key: key);
      } on Object {
        // Best effort.
      }
    }
  }

  @override
  Future<Uint8List?> readPhoto(String contactId) async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final File local = File('${docs.path}/contact_photos/$contactId.jpg');
      if (await local.exists()) return await local.readAsBytes();
    } on Object {
      // Fall through to the bucket.
    }
    try {
      return await _client.storage
          .from(_photoBucket)
          .download('$userId/$contactId.jpg');
    } on StorageException catch (e) {
      final String status = e.statusCode ?? '';
      if (status == '400' || status == '404') return null; // Not there.
      throw LegacyPhotoUnavailable(e);
    } on Object catch (e) {
      throw LegacyPhotoUnavailable(e);
    }
  }

  /// Removes an old photo file from this device once it has been moved.
  static Future<void> deleteLocalPhoto(String contactId) async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final File local = File('${docs.path}/contact_photos/$contactId.jpg');
      if (await local.exists()) await local.delete();
    } on Object {
      // Best effort.
    }
  }
}
