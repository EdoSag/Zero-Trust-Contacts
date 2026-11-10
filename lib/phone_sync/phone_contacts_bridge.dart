import 'dart:io';

import 'package:flutter/services.dart';

/// What the phone's contacts hold from the vault right now.
class PhoneContactsState {
  const PhoneContactsState({required this.accountExists, required this.hashes});

  /// Whether the "ZT Contacts" account is on the phone.
  final bool accountExists;

  /// Vault contact id -> hash of what was written for it.
  final Map<String, String> hashes;
}

/// A contact in the phone's ZT Contacts account that a contacts app
/// changed, added or deleted.
class PhoneChange {
  const PhoneChange({
    required this.rawId,
    required this.sourceId,
    required this.deleted,
    this.fields = const <String, Object?>{},
  });

  /// The phone's id of the row.
  final int rawId;

  /// The vault contact it is a copy of; null when it was created on the
  /// phone.
  final String? sourceId;
  final bool deleted;

  /// displayName, firstName, lastName, company, notes, starred, birthdays
  /// (strings) and phones, emails, addresses (lists of `{value, type}`).
  final Map<String, Object?> fields;

  static PhoneChange? fromMap(Object? raw) {
    if (raw is! Map || raw['rawId'] is! int) {
      return null;
    }
    return PhoneChange(
      rawId: raw['rawId'] as int,
      sourceId: raw['sourceId'] as String?,
      deleted: raw['deleted'] == true,
      fields: <String, Object?>{
        for (final MapEntry<Object?, Object?> e in raw.entries) '${e.key}': e.value,
      },
    );
  }
}

/// The Android side of "Show in Phone and Messages" (PhoneContactsSync.kt).
abstract interface class PhoneContactsBridge {
  /// Whether this platform can do it at all (Android only).
  bool get isSupported;

  /// Asks for permission to read and write the phone's contacts.
  Future<bool> requestPermission();

  Future<PhoneContactsState> state();

  /// Writes [upserts] (field maps with `id`, `hash` and optional `photo`
  /// bytes) and removes the contacts with ids in [deletes].
  Future<void> apply(
      List<Map<String, Object?>> upserts, List<String> deletes);

  /// Removes the account and every contact it holds.
  Future<void> disable();

  /// What contacts apps changed in the account since the last
  /// [acknowledge].
  Future<List<PhoneChange>> changes();

  /// Marks [change] as taken into the vault: a deleted row is removed for
  /// good, any other is tied to the vault contact [vaultId] and rewritten
  /// from the vault by the next [apply].
  Future<void> acknowledge(PhoneChange change, {String? vaultId});
}

class MethodChannelPhoneContactsBridge implements PhoneContactsBridge {
  const MethodChannelPhoneContactsBridge();

  static const MethodChannel _channel =
      MethodChannel('zerotrust_contacts/device_contacts');

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestWriteContactsPermission') ??
      false;

  @override
  Future<PhoneContactsState> state() async {
    final Map<Object?, Object?> raw =
        await _channel.invokeMapMethod<Object?, Object?>('phoneSync.state') ??
            const <Object?, Object?>{};
    final Object? hashes = raw['hashes'];
    return PhoneContactsState(
      accountExists: raw['enabled'] == true,
      hashes: <String, String>{
        if (hashes is Map)
          for (final MapEntry<Object?, Object?> e in hashes.entries)
            '${e.key}': '${e.value}',
      },
    );
  }

  @override
  Future<void> apply(
          List<Map<String, Object?>> upserts, List<String> deletes) =>
      _channel.invokeMethod<int>('phoneSync.apply', <String, Object?>{
        'upserts': upserts,
        'deletes': deletes,
      });

  @override
  Future<void> disable() => _channel.invokeMethod<bool>('phoneSync.disable');

  @override
  Future<List<PhoneChange>> changes() async {
    final List<Object?> raw =
        await _channel.invokeListMethod<Object?>('phoneSync.changes') ??
            const <Object?>[];
    return raw.map(PhoneChange.fromMap).whereType<PhoneChange>().toList();
  }

  @override
  Future<void> acknowledge(PhoneChange change, {String? vaultId}) =>
      _channel.invokeMethod<int>('phoneSync.acknowledge', <String, Object?>{
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'rawId': change.rawId,
            'deleted': change.deleted || vaultId == null,
            'sourceId': vaultId,
          },
        ],
      });
}
