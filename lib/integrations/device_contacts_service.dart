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

class DeviceContactsService {
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

  void _ensureHandlerRegistered() {
    if (_handlerRegistered) {
      return;
    }
    _channel.setMethodCallHandler((MethodCall call) async {
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
      Map<String, dynamic>.from(raw as Map<dynamic, dynamic>),
    );
  }
}
