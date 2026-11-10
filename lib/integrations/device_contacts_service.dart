import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

class DeviceContact {
  DeviceContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.source,
  });

  final String id;
  final String name;
  final String phone;
  final String source;

  factory DeviceContact.fromMap(Map<dynamic, dynamic> map) {
    return DeviceContact(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      source: (map['source'] ?? 'Phone').toString(),
    );
  }
}

class ContactSourceStats {
  ContactSourceStats({
    required this.accountCount,
    required this.simCount,
    required this.phoneCount,
  });

  final int accountCount;
  final int simCount;
  final int phoneCount;

  int get totalCount => accountCount + simCount + phoneCount;

  factory ContactSourceStats.empty() {
    return ContactSourceStats(
      accountCount: 0,
      simCount: 0,
      phoneCount: 0,
    );
  }

  factory ContactSourceStats.fromMap(Map<dynamic, dynamic> map) {
    return ContactSourceStats(
      accountCount: _toCount(map['accountCount'] ?? map['googleCount']),
      simCount: _toCount(map['simCount']),
      phoneCount: _toCount(map['phoneCount']),
    );
  }

  static int _toCount(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return int.tryParse(rawValue?.toString() ?? '') ?? 0;
  }
}

/// A Google (or other) account whose contacts are synced to this phone.
class ImportAccount {
  ImportAccount({required this.name, required this.contactCount});

  final String name;
  final int contactCount;
}

/// Something another app handed to ZT Contacts.
sealed class IncomingRequest {
  const IncomingRequest();

  static IncomingRequest? fromMap(Map<Object?, Object?> map) {
    switch (map['kind']) {
      case 'vcard':
        final Object? bytes = map['bytes'];
        if (bytes is! List<int>) {
          return null;
        }
        return IncomingVCard(
          text: utf8.decode(bytes, allowMalformed: true),
          name: '${map['name'] ?? 'contacts.vcf'}',
        );
      case 'insert':
        return IncomingNewContact(
          contact: contactFromInsertRequest(map),
          allowExisting: map['allowExisting'] == true,
        );
    }
    return null;
  }

  /// The contact an "add a contact" request describes.
  static VaultContact contactFromInsertRequest(Map<Object?, Object?> map) {
    final Map<String, String> types = <String, String>{};
    List<String> typed(String key, String field) {
      final List<String> values = <String>[];
      final Object? rows = map[key];
      if (rows is List) {
        for (final Object? row in rows) {
          if (row is! Map) continue;
          final String value = '${row['value'] ?? ''}'.trim();
          if (value.isEmpty) continue;
          values.add(value);
          final String type = '${row['type'] ?? ''}';
          if (type.isNotEmpty) {
            types[VaultContact.typeKey(field, value)] = type;
          }
        }
      }
      return values;
    }

    List<String> plain(String key) => <String>[
      if (map[key] case final List<Object?> rows)
        for (final Object? row in rows)
          if ('${row ?? ''}'.trim().isNotEmpty) '$row'.trim(),
    ];

    String text(String key) => '${map[key] ?? ''}'.trim();

    String firstName = text('firstName');
    String lastName = text('lastName');
    final String displayName = text('displayName');
    if (firstName.isEmpty && lastName.isEmpty && displayName.isNotEmpty) {
      // Only a full name was given: the last word is the last name.
      final List<String> words = displayName.split(RegExp(r'\s+'));
      firstName = words.length == 1
          ? displayName
          : words.take(words.length - 1).join(' ');
      lastName = words.length == 1 ? '' : words.last;
    }
    final DateTime now = DateTime.now().toUtc();
    return VaultContact.fromLegacyPayload(<String, dynamic>{
      'id': VaultContact.generateId(),
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'company': text('company'),
      'notes': text('notes'),
      'phones': typed('phones', 'phone'),
      'emails': typed('emails', 'email'),
      'addresses': typed('addresses', 'address'),
      'other': plain('other'),
      'birthdays': plain('birthdays'),
      'valueTypes': types,
      'source': 'Saved',
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }
}

/// A .vcf file opened with, or shared to, the app.
class IncomingVCard extends IncomingRequest {
  const IncomingVCard({required this.text, required this.name});

  final String text;
  final String name;
}

/// "Create new contact" or "Add to contacts" from another app.
class IncomingNewContact extends IncomingRequest {
  const IncomingNewContact({required this.contact, required this.allowExisting});

  /// The details the other app filled in.
  final VaultContact contact;

  /// Whether the user may add them to a contact they already have.
  final bool allowExisting;
}

class DeviceContactsService {
  static const String googleAccountType = 'com.google';

  static const MethodChannel _channel = MethodChannel(
    'zerotrust_contacts/device_contacts',
  );
  static final StreamController<VaultContact> _openedContactsController =
      StreamController<VaultContact>.broadcast();
  static bool _handlerRegistered = false;

  DeviceContactsService() {
    _ensureHandlerRegistered();
  }

  Stream<VaultContact> get openedContacts => _openedContactsController.stream;

  static final StreamController<void> _incomingController =
      StreamController<void>.broadcast();

  /// Fires when another app hands over something while the app is open
  /// (see [consumePendingIncoming]).
  Stream<void> get incoming => _incomingController.stream;

  /// What another app handed over, if anything: a vCard file opened with
  /// or shared to the app, or an "add a contact" request. Each is returned
  /// once.
  Future<IncomingRequest?> consumePendingIncoming() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final Object? raw = await _channel.invokeMethod<Object?>(
      'consumePendingIncoming',
    );
    return raw is Map ? IncomingRequest.fromMap(raw) : null;
  }

  void _ensureHandlerRegistered() {
    if (_handlerRegistered) {
      return;
    }
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'incomingReceived') {
        if (!_incomingController.isClosed) {
          _incomingController.add(null);
        }
        return;
      }
      if (call.method != 'contactIntentReceived') {
        return;
      }
      final VaultContact? contact = _vaultContactFromDynamic(call.arguments);
      if (contact != null && !_openedContactsController.isClosed) {
        _openedContactsController.add(contact);
      }
    });
    _handlerRegistered = true;
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final bool? granted = await _channel.invokeMethod<bool>(
      'requestContactsPermission',
    );
    return granted ?? false;
  }

  Future<List<DeviceContact>> loadContacts({String? selectedAccount}) async {
    if (!Platform.isAndroid) {
      return [];
    }
    final List<dynamic>? response = await _channel.invokeMethod<List<dynamic>>(
      'getDeviceContacts',
      <String, dynamic>{'selectedAccount': selectedAccount},
    );
    if (response == null) {
      return [];
    }

    return response
        .whereType<Map<dynamic, dynamic>>()
        .map(DeviceContact.fromMap)
        .toList();
  }

  Future<ContactSourceStats> loadSourceStats({String? selectedAccount}) async {
    if (!Platform.isAndroid) {
      return ContactSourceStats.empty();
    }
    final Map<dynamic, dynamic>? response =
        await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getContactSourceStats',
      <String, dynamic>{'selectedAccount': selectedAccount},
    );
    if (response == null) {
      return ContactSourceStats.empty();
    }
    return ContactSourceStats.fromMap(response);
  }

  /// Google accounts that have contacts on this phone (Android only).
  Future<List<ImportAccount>> loadImportAccounts({
    String accountType = googleAccountType,
  }) async {
    if (!Platform.isAndroid) {
      return <ImportAccount>[];
    }
    final List<dynamic>? response = await _channel.invokeMethod<List<dynamic>>(
      'getImportAccounts',
      <String, dynamic>{'accountType': accountType},
    );
    return (response ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => ImportAccount(
              name: (item['name'] ?? '').toString(),
              contactCount: ContactSourceStats._toCount(item['count']),
            ))
        .where((ImportAccount account) => account.name.isNotEmpty)
        .toList();
  }

  /// Every contact in one account with all its details, as raw field maps.
  /// Read on the phone from Android's contacts database, never from Google.
  Future<List<Map<String, dynamic>>> loadAccountContacts(
    String accountName, {
    String accountType = googleAccountType,
  }) async {
    if (!Platform.isAndroid) {
      return <Map<String, dynamic>>[];
    }
    final List<dynamic>? response = await _channel.invokeMethod<List<dynamic>>(
      'getAccountContacts',
      <String, dynamic>{
        'accountType': accountType,
        'accountName': accountName,
      },
    );
    return (response ?? <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// The photo of one raw contact (from [loadAccountContacts]' `rawId`),
  /// as a JPEG scaled down to at most 800 px, or null when it has none.
  /// Read from the phone's contacts database, not from Google.
  Future<Uint8List?> loadRawContactPhoto(int rawContactId) async {
    if (!Platform.isAndroid) {
      return null;
    }
    return _channel.invokeMethod<Uint8List>(
      'getRawContactPhoto',
      <String, dynamic>{'rawContactId': rawContactId},
    );
  }

  Future<void> launchDialer(String phoneNumber) async {
    if (phoneNumber.trim().isEmpty) {
      return;
    }
    await _channel.invokeMethod<void>(
      'launchDialer',
      <String, dynamic>{'phoneNumber': phoneNumber},
    );
  }

  Future<void> launchSms(String phoneNumber) async {
    if (phoneNumber.trim().isEmpty) {
      return;
    }
    await _channel.invokeMethod<void>(
      'launchSms',
      <String, dynamic>{'phoneNumber': phoneNumber},
    );
  }

  Future<VaultContact?> consumePendingOpenedContact() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final dynamic response = await _channel.invokeMethod<dynamic>(
      'consumePendingOpenedContact',
    );
    return _vaultContactFromDynamic(response);
  }

  VaultContact? _vaultContactFromDynamic(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    return VaultContact.fromLegacyPayload(
      Map<String, dynamic>.from(raw),
    );
  }
}
