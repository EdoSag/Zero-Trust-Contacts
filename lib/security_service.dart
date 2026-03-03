import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:zerotrust_contacts/config/app_config.dart';
import 'package:zerotrust_contacts/utils/base64_url_codec.dart';

class KeyDerivationService {
  static const int pbkdf2Iterations = 600000;
  static const int keySizeBits = 256;
  static const int saltLength = 16;

  final Pbkdf2 _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: keySizeBits,
  );

  Future<Uint8List> deriveKey({
    required String password,
    required List<int> salt,
  }) async {
    if (salt.length != saltLength) {
      throw StateError('PBKDF2 salt must be exactly $saltLength bytes.');
    }

    final pepperedPassword = '$password:${AppConfig.appInternalSalt}';
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pepperedPassword)),
      nonce: salt,
    );
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  Uint8List generateRandomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(saltLength, (_) => random.nextInt(256)),
    );
  }
}

class LocalSecurityRepository {
  LocalSecurityRepository._();

  factory LocalSecurityRepository() {
    return _instance;
  }

  static final LocalSecurityRepository _instance = LocalSecurityRepository._();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String saltStorageKey = 'vault_pbkdf2_salt';
  static const String encryptedDbKeyStorageKey = 'encrypted_db_key';
  static const String biometricEnabledStorageKey = 'biometric_enabled';
  static const String cachedCloudBlobStorageKey = 'cached_cloud_vault_blob';

  Future<Uint8List> getOrCreateSalt() async {
    final existing = await _secureStorage.read(key: saltStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return decodeBase64Url(existing);
    }

    final salt = KeyDerivationService().generateRandomSalt();
    await saveSalt(salt);
    return salt;
  }

  Future<void> saveSalt(List<int> salt) async {
    if (salt.length != KeyDerivationService.saltLength) {
      throw StateError(
        'Salt must be exactly ${KeyDerivationService.saltLength} bytes.',
      );
    }
    await _secureStorage.write(key: saltStorageKey, value: encodeBase64Url(salt));
  }

  Future<Uint8List?> readSalt() async {
    final encoded = await _secureStorage.read(key: saltStorageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    return decodeBase64Url(encoded);
  }

  Future<void> saveEncryptedDbKey(List<int> derivedKey) async {
    await _secureStorage.write(
      key: encryptedDbKeyStorageKey,
      value: encodeBase64Url(derivedKey),
    );
  }

  Future<Uint8List?> readEncryptedDbKey() async {
    final encoded = await _secureStorage.read(key: encryptedDbKeyStorageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    return decodeBase64Url(encoded);
  }

  Future<bool> hasEncryptedDbKey() async {
    final encoded = await _secureStorage.read(key: encryptedDbKeyStorageKey);
    return encoded != null && encoded.isNotEmpty;
  }

  Future<void> clearEncryptedDbKey() async {
    await _secureStorage.delete(key: encryptedDbKeyStorageKey);
  }

  Future<void> saveBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: biometricEnabledStorageKey,
      value: enabled.toString(),
    );
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _secureStorage.read(key: biometricEnabledStorageKey);
    return value == 'true';
  }

  Future<void> saveCachedCloudBlob(String dataBlob) async {
    await _secureStorage.write(key: cachedCloudBlobStorageKey, value: dataBlob);
  }

  Future<String?> readCachedCloudBlob() async {
    return _secureStorage.read(key: cachedCloudBlobStorageKey);
  }

  Future<void> clearCachedCloudBlob() async {
    await _secureStorage.delete(key: cachedCloudBlobStorageKey);
  }
}

class LocalEncryptedDatabaseService {
  LocalEncryptedDatabaseService._();

  factory LocalEncryptedDatabaseService() {
    return _instance;
  }

  static final LocalEncryptedDatabaseService _instance =
      LocalEncryptedDatabaseService._();

  Database? _database;

  bool get isOpen {
    return _database?.isOpen ?? false;
  }

  Future<void> openWithDerivedKey(List<int> derivedKey) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'vault_contacts.db');
    final sqlCipherKey = encodeBase64Url(derivedKey);

    _database = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute("PRAGMA key = '$sqlCipherKey';");
        await db.execute('PRAGMA foreign_keys = ON;');
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS contacts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payload TEXT NOT NULL
          );
        ''');
      },
    );
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

@NowaGenerated()
class SecurityService {
  SecurityService({
    LocalSecurityRepository? localSecurityRepository,
    KeyDerivationService? keyDerivationService,
  })  : _localSecurityRepository = localSecurityRepository ??
            LocalSecurityRepository(),
        _keyDerivationService = keyDerivationService ?? KeyDerivationService();

  final LocalSecurityRepository _localSecurityRepository;
  final KeyDerivationService _keyDerivationService;

  Uint8List? _derivedKey;

  Future<void> initializeFirstTime() async {
    await _localSecurityRepository.getOrCreateSalt();
  }

  Future<bool> isInitialized() async {
    final salt = await _localSecurityRepository.readSalt();
    return salt != null;
  }

  Future<void> deriveKeyFromPassword(String masterPassword) async {
    final salt = await _localSecurityRepository.readSalt();
    if (salt == null) {
      throw StateError('PBKDF2 salt not found. Please setup first.');
    }
    _derivedKey = await _keyDerivationService.deriveKey(
      password: masterPassword,
      salt: salt,
    );
  }

  Future<String> encrypt(String plainText) async {
    if (_derivedKey == null) {
      throw StateError('Encryption key is not available.');
    }

    final algorithm = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final box = await algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(_derivedKey!),
      nonce: nonce,
    );

    return jsonEncode({
      'nonce': encodeBase64Url(box.nonce),
      'cipherText': encodeBase64Url(box.cipherText),
      'mac': encodeBase64Url(box.mac.bytes),
    });
  }

  Future<String> decrypt(String encryptedData) async {
    if (_derivedKey == null) {
      throw StateError('Encryption key is not available.');
    }

    final payload = jsonDecode(encryptedData) as Map<String, dynamic>;
    final nonce = decodeBase64Url(payload['nonce'] as String);
    final cipherText = decodeBase64Url(payload['cipherText'] as String);
    final mac = Mac(decodeBase64Url(payload['mac'] as String));
    final algorithm = AesGcm.with256bits();

    final plainBytes = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: SecretKey(_derivedKey!),
    );

    return utf8.decode(plainBytes);
  }

  void clearKey() {
    _derivedKey = null;
  }

  bool isKeyAvailable() {
    return _derivedKey != null;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
