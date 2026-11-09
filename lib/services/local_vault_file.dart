import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// Device-only data that never syncs: restore points and the activity log.
///
/// Kept as one JSON document, sealed (AES-256-GCM) under a key derived from
/// the app key, so it is unreadable while the vault is locked and belongs to
/// one account.
abstract class LocalVaultFile {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> data);

  Future<void> _queue = Future<void>.value();

  /// Reads, changes and writes the document as one step. Updates run one
  /// after another, so two at once (a save while old photos move over, say)
  /// can't drop each other's entries or collide on the file.
  Future<void> update(void Function(Map<String, Object?> data) change) {
    final Future<void> next = _queue.then((_) async {
      final Map<String, Object?> data = await read();
      change(data);
      await write(data);
    });
    _queue = next.catchError((Object _) {});
    return next;
  }
}

class SealedLocalVaultFile extends LocalVaultFile {
  SealedLocalVaultFile._(this._file, this._key);

  final File _file;
  final Uint8List _key;

  static const _aad = 'zt/contacts/local-file/v1';

  static Future<SealedLocalVaultFile> open({
    required Uint8List appKey,
    required String userId,
  }) async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final key = await Kdf.hkdf(appKey, _aad);
    return SealedLocalVaultFile._(
        File('${dir.path}/zt_contacts_local_$userId.bin'), key);
  }

  @override
  Future<Map<String, Object?>> read() async {
    if (!await _file.exists()) return {};
    try {
      final text = await SealedBox.openString(
          await _file.readAsBytes(), _key,
          aad: utf8.encode(_aad));
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on Object {
      // Damaged, or written under another key: restore points are a
      // convenience, so start over rather than block the app.
      return {};
    }
  }

  @override
  Future<void> write(Map<String, Object?> data) async {
    final sealed = await SealedBox.sealString(jsonEncode(data), _key,
        aad: utf8.encode(_aad));
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);
    await tmp.rename(_file.path);
  }

  void close() => _key.fillRange(0, _key.length, 0);
}

class InMemoryLocalVaultFile extends LocalVaultFile {
  Map<String, Object?> data = {};

  @override
  Future<Map<String, Object?>> read() async =>
      jsonDecode(jsonEncode(data)) as Map<String, Object?>;

  @override
  Future<void> write(Map<String, Object?> value) async =>
      data = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
}
