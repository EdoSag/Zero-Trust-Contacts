import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// How Contacts encrypted data before it moved onto Zero-Trust-Core.
///
/// The key was PBKDF2-HMAC-SHA256 (600,000 rounds) of
/// `"<password>:<app pepper>"` with the account's `profiles.salt`. The core
/// upgrades pre-core accounts with PBKDF2 of the password alone (what the
/// other apps used), so `VaultUnlocked.legacyKey` is not this key and
/// Contacts derives its own.
abstract final class LegacyContactsCrypto {
  /// `APP_INTERNAL_SALT` from the `.env` every pre-core build shipped with.
  /// Not a secret (it was inside every APK and in this public repo's
  /// history); it is only needed to rebuild the old key.
  static const String pepper = '6f8d2b3e9a1c4f5b7d9e0a2c4b6d8f0a1b2c';

  static const KdfParams params = KdfParams(iterations: 600000);

  /// The pre-core Contacts key for [password] and the account's
  /// `profiles.salt` (any base64 dialect). Runs on a background isolate.
  static Future<Uint8List> deriveKey({
    required String password,
    required String legacySalt,
    KdfParams kdf = params,
  }) =>
      Kdf.deriveMasterKey(
        password: '$password:$pepper',
        salt: ZtBase64.decode(legacySalt),
        params: kdf,
      );

  /// Whether [blob] (`encrypted_contacts.data_blob`) is encrypted, rather
  /// than the plain JSON the earliest versions uploaded.
  static bool isEncrypted(Map<String, dynamic> blob) =>
      blob['format'] == 'ztc_cloud_cipher_v1' ||
      (blob.containsKey('nonce') &&
          blob.containsKey('cipherText') &&
          blob.containsKey('mac'));

  /// Decrypts an encrypted cloud blob; null when [key] doesn't open it.
  static Future<String?> decryptBlob(
      Map<String, dynamic> blob, List<int> key) async {
    try {
      final List<int> plain = await AesGcm.with256bits().decrypt(
        SecretBox(
          ZtBase64.decode(blob['cipherText'] as String),
          nonce: ZtBase64.decode(blob['nonce'] as String),
          mac: Mac(ZtBase64.decode(blob['mac'] as String)),
        ),
        secretKey: SecretKey(key),
      );
      return utf8.decode(plain);
    } on Object {
      return null;
    }
  }

  /// The inverse of [decryptBlob], as pre-core versions wrote it. For tests.
  static Future<String> encryptBlob(String plainText, List<int> key) async {
    final SecretBox box = await AesGcm.with256bits().encrypt(
      utf8.encode(plainText),
      secretKey: SecretKey(key),
    );
    return jsonEncode(<String, dynamic>{
      'format': 'ztc_cloud_cipher_v1',
      'alg': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }
}
