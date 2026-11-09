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
}
