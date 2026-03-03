import 'dart:io';

import 'package:flutter/services.dart';

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
}
