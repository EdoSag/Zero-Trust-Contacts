import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/security_service.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';

enum ContactSortMode {
  alphabetical,
  recent,
  source,
}

class SecurityActivityEntry {
  SecurityActivityEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    required this.details,
    required this.isError,
  });

  final String id;
  final String action;
  final DateTime createdAt;
  final String details;
  final bool isError;

  factory SecurityActivityEntry.fromJson(Map<String, dynamic> json) {
    return SecurityActivityEntry(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      details: (json['details'] ?? '').toString(),
      isError: json['isError'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'action': action,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'details': details,
      'isError': isError,
    };
  }
}

class VaultSnapshot {
  VaultSnapshot({
    required this.id,
    required this.createdAt,
    required this.reason,
    required this.cadence,
    required this.contacts,
  });

  final String id;
  final DateTime createdAt;
  final String reason;
  final String cadence;
  final List<VaultContact> contacts;

  factory VaultSnapshot.fromJson(Map<String, dynamic> json) {
    final List<VaultContact> contacts = <VaultContact>[];
    final dynamic rawContacts = json['contacts'];
    if (rawContacts is List) {
      for (final dynamic entry in rawContacts) {
        if (entry is Map) {
          contacts.add(
            VaultContact.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }
    return VaultSnapshot(
      id: (json['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toUtc() ??
              DateTime.now().toUtc(),
      reason: (json['reason'] ?? '').toString(),
      cadence: (json['cadence'] ?? 'manual').toString(),
      contacts: contacts,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'reason': reason,
      'cadence': cadence,
      'contacts': contacts.map((VaultContact item) => item.toJson()).toList(),
    };
  }
}

class ContactMergeConflict {
  ContactMergeConflict({
    required this.contactId,
    required this.local,
    required this.remote,
    required this.merged,
  });

  final String contactId;
  final VaultContact local;
  final VaultContact remote;
  final VaultContact merged;

  factory ContactMergeConflict.fromJson(Map<String, dynamic> json) {
    return ContactMergeConflict(
      contactId: (json['contactId'] ?? '').toString(),
      local: VaultContact.fromJson(
        Map<String, dynamic>.from(
            (json['local'] ?? <String, dynamic>{}) as Map),
      ),
      remote: VaultContact.fromJson(
        Map<String, dynamic>.from(
            (json['remote'] ?? <String, dynamic>{}) as Map),
      ),
      merged: VaultContact.fromJson(
        Map<String, dynamic>.from(
            (json['merged'] ?? <String, dynamic>{}) as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'contactId': contactId,
      'local': local.toJson(),
      'remote': remote.toJson(),
      'merged': merged.toJson(),
    };
  }
}

class SyncResult {
  SyncResult({
    required this.localCount,
    required this.cloudCount,
    required this.mergedCount,
    required this.conflicts,
    required this.pushedToCloud,
    required this.pulledFromCloud,
    required this.skipped,
  });

  final int localCount;
  final int cloudCount;
  final int mergedCount;
  final List<ContactMergeConflict> conflicts;
  final bool pushedToCloud;
  final bool pulledFromCloud;
  final bool skipped;
}

class SecureSharePackage {
  SecureSharePackage({
    required this.payload,
    required this.passphrase,
    required this.expiresAt,
  });

  final String payload;
  final String passphrase;
  final DateTime expiresAt;
}

class _CloudBlobParseResult {
  _CloudBlobParseResult({
    required this.contacts,
    required this.wasEncrypted,
  });

  final List<VaultContact> contacts;
  final bool wasEncrypted;
}

class VaultRepository {
  VaultRepository._();

  static final VaultRepository _instance = VaultRepository._();

  factory VaultRepository() {
    return _instance;
  }

  static const int _maxActivityEntries = 200;
  static const int _maxSnapshots = 40;

  final LocalEncryptedDatabaseService _database =
      LocalEncryptedDatabaseService();
  final LocalSecurityRepository _securityRepository = LocalSecurityRepository();
  final SupabaseService _supabaseService = SupabaseService();
  final ContactPhotoService _photoService = ContactPhotoService();

  Future<List<VaultContact>> loadSavedContacts() async {
    if (!_database.isOpen) {
      throw StateError(
        'Local vault is not open on this device. Please sign out and sign in again.',
      );
    }

    final List<String> payloads = await _database.readAllContactPayloads();
    final Map<String, VaultContact> contactsById = <String, VaultContact>{};
    bool payloadNeedsRefresh = false;

    for (final String payload in payloads) {
      final Map<String, dynamic>? decoded = _readJsonMap(payload);
      if (decoded == null) {
        continue;
      }
      final VaultContact contact = _decodeContact(decoded);
      final VaultContact? existing = contactsById[contact.id];
      if (existing == null || contact.updatedAt.isAfter(existing.updatedAt)) {
        contactsById[contact.id] = contact;
      }
      if (decoded['id'] == null ||
          decoded['createdAt'] == null ||
          decoded['updatedAt'] == null ||
          decoded['fieldUpdatedAt'] == null) {
        payloadNeedsRefresh = true;
      }
    }

    final List<VaultContact> contacts = contactsById.values.toList()
      ..sort((VaultContact a, VaultContact b) =>
          b.updatedAt.compareTo(a.updatedAt));

    if (payloadNeedsRefresh) {
      await _replaceSavedContacts(
        contacts,
        shouldCreateSnapshot: false,
      );
    }
    return contacts;
  }

  Future<VaultContact?> findSavedContactById(String id) async {
    final List<VaultContact> contacts = await loadSavedContacts();
    for (final VaultContact contact in contacts) {
      if (contact.id == id) {
        return contact;
      }
    }
    return null;
  }

  Future<void> upsertSavedContact(
    VaultContact contact, {
    String activity = 'contact_upsert',
  }) async {
    final List<VaultContact> contacts = await loadSavedContacts();
    bool replaced = false;
    final List<VaultContact> updated = contacts.map((VaultContact current) {
      if (current.id == contact.id) {
        replaced = true;
        return contact;
      }
      return current;
    }).toList();
    if (!replaced) {
      updated.add(contact);
    }
    await _replaceSavedContacts(updated, shouldCreateSnapshot: true);
    await maybeCreateCadenceSnapshots();
    await logActivity(
      activity,
      details: '${replaced ? 'Updated' : 'Created'} ${contact.displayName}',
    );
  }

  Future<bool> deleteSavedContact(String contactId) async {
    final List<VaultContact> contacts = await loadSavedContacts();
    final int initialLength = contacts.length;
    final VaultContact? target = contacts
        .where((VaultContact c) => c.id == contactId)
        .firstOrNull;
    contacts.removeWhere((VaultContact contact) => contact.id == contactId);
    if (contacts.length == initialLength) {
      return false;
    }
    await _replaceSavedContacts(contacts, shouldCreateSnapshot: true);
    // Clean up local photo file if one exists.
    if (target?.photoPath != null) {
      await _photoService.deleteLocally(contactId);
      final String? userId = _supabaseService.currentUser?.id;
      if (userId != null) {
        await _photoService.deleteFromCloud(userId, contactId);
      }
    }
    await logActivity('contact_delete', details: 'Deleted contact $contactId');
    return true;
  }

  Future<void> toggleFavorite(String contactId) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return;
    }
    await upsertSavedContact(
      target.applyEdits(isFavorite: !target.isFavorite),
      activity: 'contact_toggle_favorite',
    );
  }

  Future<void> togglePinned(String contactId) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return;
    }
    await upsertSavedContact(
      target.applyEdits(isPinned: !target.isPinned),
      activity: 'contact_toggle_pinned',
    );
  }

  Future<void> markContactInteraction(String contactId) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return;
    }
    await upsertSavedContact(
      target.registerInteraction(),
      activity: 'contact_interaction',
    );
  }

  List<VaultContact> filterAndSortContacts({
    required List<VaultContact> contacts,
    required String query,
    required String sourceFilter,
    required ContactSortMode sortMode,
    String? labelFilter,
  }) {
    final String normalizedQuery = query.trim().toLowerCase();
    final String normalizedSource = sourceFilter.trim().toLowerCase();
    final String normalizedLabel = labelFilter?.trim().toLowerCase() ?? '';

    final List<VaultContact> filtered = contacts.where((VaultContact contact) {
      final bool sourceMatches = normalizedSource == 'all'
          ? true
          : contact.source.toLowerCase() == normalizedSource;
      if (!sourceMatches) {
        return false;
      }

      if (normalizedLabel.isNotEmpty &&
          !contact.labels
              .map((String label) => label.toLowerCase())
              .contains(normalizedLabel)) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }
      return contact.searchableText.contains(normalizedQuery);
    }).toList();

    sortContactsInPlace(filtered, sortMode);
    return filtered;
  }

  void sortContactsInPlace(
      List<VaultContact> contacts, ContactSortMode sortMode) {
    switch (sortMode) {
      case ContactSortMode.alphabetical:
        contacts.sort(
          (VaultContact a, VaultContact b) =>
              a.displayName.toLowerCase().compareTo(
                    b.displayName.toLowerCase(),
                  ),
        );
      case ContactSortMode.recent:
        contacts.sort((VaultContact a, VaultContact b) =>
            b.updatedAt.compareTo(a.updatedAt));
      case ContactSortMode.source:
        contacts.sort((VaultContact a, VaultContact b) {
          final int sourceCompare =
              a.source.toLowerCase().compareTo(b.source.toLowerCase());
          if (sourceCompare != 0) {
            return sourceCompare;
          }
          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
        });
    }
  }

  Future<List<ContactDuplicateGroup>> findDuplicateGroups(
      List<VaultContact> contacts) async {
    final List<ContactDuplicateGroup> groups = <ContactDuplicateGroup>[];
    final Map<String, List<VaultContact>> buckets =
        <String, List<VaultContact>>{};
    final Set<String> seenGroupKeys = <String>{};

    void addToBucket(String key, VaultContact contact) {
      if (key.trim().isEmpty) {
        return;
      }
      final List<VaultContact> list =
          buckets.putIfAbsent(key, () => <VaultContact>[]);
      list.add(contact);
    }

    for (final VaultContact contact in contacts) {
      for (final String phone in contact.phones) {
        addToBucket('phone:${VaultContact.normalizedPhone(phone)}', contact);
      }
      for (final String email in contact.emails) {
        addToBucket('email:${VaultContact.normalizedEmail(email)}', contact);
      }
      addToBucket(
          'name:${VaultContact.normalizedName(contact.displayName)}', contact);
    }

    for (final MapEntry<String, List<VaultContact>> entry in buckets.entries) {
      if (entry.value.length < 2) {
        continue;
      }
      final List<VaultContact> uniqueContacts = <VaultContact>[];
      final Set<String> ids = <String>{};
      for (final VaultContact contact in entry.value) {
        if (ids.add(contact.id)) {
          uniqueContacts.add(contact);
        }
      }
      if (uniqueContacts.length < 2) {
        continue;
      }

      final List<String> sortedIds =
          uniqueContacts.map((VaultContact e) => e.id).toList()..sort();
      final String dedupeKey = '${entry.key}:${sortedIds.join(',')}';
      if (!seenGroupKeys.add(dedupeKey)) {
        continue;
      }

      String reason = 'Similar contacts';
      if (entry.key.startsWith('phone:')) {
        reason = 'Same phone number';
      } else if (entry.key.startsWith('email:')) {
        reason = 'Same email';
      } else if (entry.key.startsWith('name:')) {
        reason = 'Same display name';
      }
      groups
          .add(ContactDuplicateGroup(reason: reason, contacts: uniqueContacts));
    }

    groups.sort((ContactDuplicateGroup a, ContactDuplicateGroup b) {
      return b.contacts.length.compareTo(a.contacts.length);
    });
    return groups;
  }

  Future<VaultContact?> mergeDuplicateContacts(
      List<VaultContact> duplicates) async {
    if (duplicates.isEmpty) {
      return null;
    }
    VaultContact merged = duplicates.first;
    for (int i = 1; i < duplicates.length; i += 1) {
      merged = merged.mergeWith(duplicates[i]);
    }

    final List<VaultContact> saved = await loadSavedContacts();
    saved.removeWhere((VaultContact item) =>
        duplicates.any((VaultContact dup) => dup.id == item.id));
    saved.add(merged);
    await _replaceSavedContacts(saved, shouldCreateSnapshot: true);
    await logActivity(
      'contact_duplicates_merged',
      details:
          'Merged ${duplicates.length} contacts into ${merged.displayName}',
    );
    return merged;
  }

  ContactHealthSummary buildHealthSummary(List<VaultContact> contacts) {
    final List<VaultContact> upcomingBirthdays =
        contacts.where((VaultContact contact) {
      final int? days = contact.daysUntilBirthday;
      return days != null && days >= 0 && days <= 30;
    }).toList()
          ..sort((VaultContact a, VaultContact b) {
            return (a.daysUntilBirthday ?? 9999)
                .compareTo(b.daysUntilBirthday ?? 9999);
          });

    final List<VaultContact> staleContacts = contacts
        .where((VaultContact contact) => contact.isStale)
        .toList()
      ..sort((VaultContact a, VaultContact b) =>
          a.updatedAt.compareTo(b.updatedAt));

    final List<VaultContact> missingPhoneContacts = contacts
        .where((VaultContact contact) => contact.phones.isEmpty)
        .toList()
      ..sort((VaultContact a, VaultContact b) =>
          a.displayName.compareTo(b.displayName));

    return ContactHealthSummary(
      upcomingBirthdays: upcomingBirthdays,
      staleContacts: staleContacts,
      missingPhoneContacts: missingPhoneContacts,
    );
  }

  Map<String, int> labelCounts(List<VaultContact> contacts) {
    final Map<String, int> counts = <String, int>{};
    for (final VaultContact contact in contacts) {
      for (final String label in contact.labels) {
        final String normalized = label.trim();
        if (normalized.isEmpty) {
          continue;
        }
        counts[normalized] = (counts[normalized] ?? 0) + 1;
      }
    }
    final List<String> keys = counts.keys.toList()
      ..sort((String a, String b) => counts[b]!.compareTo(counts[a]!));
    final Map<String, int> sorted = <String, int>{};
    for (final String key in keys) {
      sorted[key] = counts[key]!;
    }
    return sorted;
  }

  Future<void> logActivity(
    String action, {
    String details = '',
    bool isError = false,
  }) async {
    final List<SecurityActivityEntry> current = await readActivityEntries();
    current.insert(
      0,
      SecurityActivityEntry(
        id: VaultContact.generateId(),
        action: action,
        createdAt: DateTime.now().toUtc(),
        details: details,
        isError: isError,
      ),
    );
    final List<SecurityActivityEntry> trimmed =
        current.take(_maxActivityEntries).toList();
    final String encoded = jsonEncode(
      trimmed.map((SecurityActivityEntry item) => item.toJson()).toList(),
    );
    await _securityRepository.writeString(
      key: LocalSecurityRepository.securityActivityLogStorageKey,
      value: encoded,
    );
  }

  Future<List<SecurityActivityEntry>> readActivityEntries(
      {int limit = 100}) async {
    final String? raw = await _securityRepository.readString(
      LocalSecurityRepository.securityActivityLogStorageKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return <SecurityActivityEntry>[];
    }
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <SecurityActivityEntry>[];
    }
    final List<SecurityActivityEntry> entries = <SecurityActivityEntry>[];
    for (final dynamic item in decoded) {
      final Map<String, dynamic>? map = _readJsonMap(item);
      if (map == null) {
        continue;
      }
      entries.add(SecurityActivityEntry.fromJson(map));
    }
    return entries.take(limit).toList();
  }

  Future<VaultSnapshot> createSnapshot({
    required String reason,
    String cadence = 'manual',
  }) async {
    final List<VaultContact> contacts = await loadSavedContacts();
    final VaultSnapshot snapshot = VaultSnapshot(
      id: VaultContact.generateId(),
      createdAt: DateTime.now().toUtc(),
      reason: reason,
      cadence: cadence,
      contacts: contacts,
    );
    final List<VaultSnapshot> current = await readSnapshots();
    current.insert(0, snapshot);
    final List<VaultSnapshot> trimmed = current.take(_maxSnapshots).toList();
    await _writeSnapshots(trimmed);
    return snapshot;
  }

  Future<void> maybeCreateCadenceSnapshots() async {
    final List<VaultSnapshot> snapshots = await readSnapshots();
    final DateTime now = DateTime.now().toUtc();
    DateTime? lastDaily;
    DateTime? lastWeekly;

    for (final VaultSnapshot snapshot in snapshots) {
      if (snapshot.cadence == 'daily' && lastDaily == null) {
        lastDaily = snapshot.createdAt;
      }
      if (snapshot.cadence == 'weekly' && lastWeekly == null) {
        lastWeekly = snapshot.createdAt;
      }
      if (lastDaily != null && lastWeekly != null) {
        break;
      }
    }

    if (lastDaily == null || now.difference(lastDaily).inHours >= 24) {
      await createSnapshot(
          reason: 'Automatic daily restore point', cadence: 'daily');
    }
    if (lastWeekly == null || now.difference(lastWeekly).inDays >= 7) {
      await createSnapshot(
          reason: 'Automatic weekly restore point', cadence: 'weekly');
    }
  }

  Future<List<VaultSnapshot>> readSnapshots({int limit = _maxSnapshots}) async {
    final String? raw = await _securityRepository.readString(
      LocalSecurityRepository.snapshotStorageKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return <VaultSnapshot>[];
    }
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <VaultSnapshot>[];
    }
    final List<VaultSnapshot> snapshots = <VaultSnapshot>[];
    for (final dynamic entry in decoded) {
      final Map<String, dynamic>? map = _readJsonMap(entry);
      if (map == null) {
        continue;
      }
      snapshots.add(VaultSnapshot.fromJson(map));
    }
    snapshots.sort((VaultSnapshot a, VaultSnapshot b) =>
        b.createdAt.compareTo(a.createdAt));
    return snapshots.take(limit).toList();
  }

  Future<int> restoreSnapshot(String snapshotId) async {
    final List<VaultSnapshot> snapshots = await readSnapshots();
    final VaultSnapshot? selected = snapshots
        .where((VaultSnapshot item) => item.id == snapshotId)
        .firstOrNull;
    if (selected == null) {
      return 0;
    }
    await _replaceSavedContacts(
      selected.contacts,
      shouldCreateSnapshot: true,
      snapshotReason: 'Before restoring snapshot ${selected.id}',
    );
    await logActivity(
      'snapshot_restore',
      details:
          'Restored snapshot ${selected.id} (${selected.contacts.length} contacts)',
    );
    return selected.contacts.length;
  }

  Future<String> exportEncryptedJson({required String passphrase}) async {
    final List<VaultContact> contacts = await loadSavedContacts();
    final String plain = jsonEncode(<String, dynamic>{
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'contacts': contacts.map((VaultContact item) => item.toJson()).toList(),
    });

    final Map<String, dynamic> encrypted = await _encryptTextWithPassphrase(
      plainText: plain,
      passphrase: passphrase,
    );
    final String payload = jsonEncode(<String, dynamic>{
      'kind': 'vault_export',
      'version': 2,
      'cipher': encrypted,
    });
    await logActivity('vault_export',
        details: 'Exported ${contacts.length} contacts');
    return payload;
  }

  Future<int> importEncryptedJson({
    required String encryptedPackage,
    required String passphrase,
  }) async {
    final Map<String, dynamic>? packageMap = _readJsonMap(encryptedPackage);
    if (packageMap == null) {
      throw StateError('Invalid encrypted package format.');
    }
    final Map<String, dynamic>? cipher = _readJsonMap(packageMap['cipher']);
    if (cipher == null) {
      throw StateError('Encrypted package is missing cipher payload.');
    }

    final String plain = await _decryptTextWithPassphrase(
      encrypted: cipher,
      passphrase: passphrase,
    );
    final Map<String, dynamic>? decoded = _readJsonMap(plain);
    if (decoded == null) {
      throw StateError('Decrypted package is not valid JSON.');
    }
    final List<VaultContact> imported =
        _contactsFromDynamic(decoded['contacts']);
    if (imported.isEmpty) {
      return 0;
    }

    final List<VaultContact> local = await loadSavedContacts();
    final Map<String, VaultContact> merged = <String, VaultContact>{
      for (final VaultContact item in local) item.id: item,
    };
    for (final VaultContact item in imported) {
      final VaultContact? existing = merged[item.id];
      merged[item.id] = existing == null ? item : existing.mergeWith(item);
    }

    await _replaceSavedContacts(merged.values.toList(),
        shouldCreateSnapshot: true);
    await logActivity('vault_import',
        details: 'Imported ${imported.length} contacts');
    return imported.length;
  }

  String exportVCard(List<VaultContact> contacts) {
    final StringBuffer buffer = StringBuffer();
    for (final VaultContact contact in contacts) {
      buffer.writeln('BEGIN:VCARD');
      buffer.writeln('VERSION:3.0');
      buffer.writeln('FN:${_escapeVCard(contact.displayName)}');
      buffer.writeln(
        'N:${_escapeVCard(contact.lastName)};${_escapeVCard(contact.firstName)};;;',
      );
      for (final String phone in contact.phones) {
        buffer.writeln('TEL;TYPE=CELL:${_escapeVCard(phone)}');
      }
      for (final String email in contact.emails) {
        buffer.writeln('EMAIL;TYPE=INTERNET:${_escapeVCard(email)}');
      }
      if (contact.company.trim().isNotEmpty) {
        buffer.writeln('ORG:${_escapeVCard(contact.company)}');
      }
      if (contact.notes.trim().isNotEmpty) {
        buffer.writeln('NOTE:${_escapeVCard(contact.notes)}');
      }
      if (contact.birthdays.isNotEmpty) {
        buffer.writeln('BDAY:${_escapeVCard(contact.birthdays.first)}');
      }
      buffer.writeln('END:VCARD');
    }
    return buffer.toString();
  }

  Future<int> importVCard(String rawVCard) async {
    final List<VaultContact> parsed = _parseVCard(rawVCard);
    if (parsed.isEmpty) {
      return 0;
    }
    final List<VaultContact> local = await loadSavedContacts();
    final Map<String, VaultContact> byId = <String, VaultContact>{
      for (final VaultContact item in local) item.id: item,
    };
    for (final VaultContact contact in parsed) {
      byId[contact.id] = contact;
    }
    await _replaceSavedContacts(byId.values.toList(),
        shouldCreateSnapshot: true);
    await logActivity('vcard_import',
        details: 'Imported ${parsed.length} contacts from vCard');
    return parsed.length;
  }

  Future<SecureSharePackage> createSecureSharePackage({
    required VaultContact contact,
    Duration ttl = const Duration(hours: 24),
  }) async {
    final DateTime expiresAt = DateTime.now().toUtc().add(ttl);
    final String passphrase = _generatePassphrase();
    final String plain = jsonEncode(<String, dynamic>{
      'type': 'secure_share',
      'expiresAt': expiresAt.toIso8601String(),
      'contact': contact.toJson(),
    });
    final Map<String, dynamic> cipher = await _encryptTextWithPassphrase(
      plainText: plain,
      passphrase: passphrase,
    );
    final String payload = jsonEncode(<String, dynamic>{
      'kind': 'secure_share',
      'version': 1,
      'cipher': cipher,
    });
    await logActivity('contact_secure_share',
        details: 'Prepared secure share for ${contact.id}');
    return SecureSharePackage(
      payload: payload,
      passphrase: passphrase,
      expiresAt: expiresAt,
    );
  }

  Future<VaultContact> importSecureSharePackage({
    required String payload,
    required String passphrase,
  }) async {
    final Map<String, dynamic>? package = _readJsonMap(payload);
    if (package == null) {
      throw StateError('Invalid secure share payload.');
    }
    final Map<String, dynamic>? cipher = _readJsonMap(package['cipher']);
    if (cipher == null) {
      throw StateError('Secure share payload is missing cipher data.');
    }
    final String plain = await _decryptTextWithPassphrase(
      encrypted: cipher,
      passphrase: passphrase,
    );
    final Map<String, dynamic>? decoded = _readJsonMap(plain);
    if (decoded == null) {
      throw StateError('Invalid secure share content.');
    }
    final DateTime? expiresAt =
        DateTime.tryParse((decoded['expiresAt'] ?? '').toString())?.toUtc();
    if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
      throw StateError('This secure share package has expired.');
    }
    final Map<String, dynamic>? contactJson = _readJsonMap(decoded['contact']);
    if (contactJson == null) {
      throw StateError('Shared package does not include a contact.');
    }
    final VaultContact imported = VaultContact.fromJson(contactJson);
    await upsertSavedContact(imported, activity: 'contact_secure_share_import');
    return imported;
  }

  Future<SyncResult> syncWithCloud({bool auto = false}) async {
    if (_supabaseService.currentUser == null) {
      throw StateError('No authenticated user found. Please sign in again.');
    }

    final DateTime now = DateTime.now().toUtc();
    final DateTime? lastSyncAt = await _readLastSyncAt();
    final List<VaultContact> localContacts = await loadSavedContacts();
    final String? cloudBlob =
        await _supabaseService.fetchEncryptedVaultBlobForCurrentUser();
    final _CloudBlobParseResult cloudParseResult =
        await _parseCloudBlob(cloudBlob);
    final List<VaultContact> cloudContacts = cloudParseResult.contacts;

    final Map<String, VaultContact> localMap = <String, VaultContact>{
      for (final VaultContact contact in localContacts) contact.id: contact,
    };
    final Map<String, VaultContact> cloudMap = <String, VaultContact>{
      for (final VaultContact contact in cloudContacts) contact.id: contact,
    };

    final Set<String> allIds = <String>{...localMap.keys, ...cloudMap.keys};
    final List<ContactMergeConflict> conflicts = <ContactMergeConflict>[];
    final List<VaultContact> merged = <VaultContact>[];

    for (final String id in allIds) {
      final VaultContact? local = localMap[id];
      final VaultContact? remote = cloudMap[id];

      if (local == null && remote != null) {
        merged.add(remote);
        continue;
      }
      if (remote == null && local != null) {
        merged.add(local);
        continue;
      }
      if (local == null || remote == null) {
        continue;
      }
      if (local.fingerprint == remote.fingerprint) {
        merged.add(local.updatedAt.isAfter(remote.updatedAt) ? local : remote);
        continue;
      }

      final VaultContact mergedContact = local.mergeWith(remote);
      merged.add(mergedContact);

      final bool localChangedSinceSync =
          lastSyncAt == null || local.updatedAt.isAfter(lastSyncAt);
      final bool cloudChangedSinceSync =
          lastSyncAt == null || remote.updatedAt.isAfter(lastSyncAt);

      if (localChangedSinceSync && cloudChangedSinceSync) {
        conflicts.add(
          ContactMergeConflict(
            contactId: id,
            local: local,
            remote: remote,
            merged: mergedContact,
          ),
        );
      }
    }

    sortContactsInPlace(merged, ContactSortMode.recent);

    final bool localNeedsUpdate = !_sameContactSets(localContacts, merged);
    final bool cloudNeedsUpdate = !_sameContactSets(cloudContacts, merged) ||
        !cloudParseResult.wasEncrypted;

    if (localNeedsUpdate) {
      await _replaceSavedContacts(
        merged,
        shouldCreateSnapshot: true,
        snapshotReason: 'Before sync merge',
      );
    }

    if (cloudNeedsUpdate) {
      final String payload = await _buildCloudBlob(merged);
      await _supabaseService.upsertEncryptedVaultBlobForCurrentUser(payload);
      await _securityRepository.saveCachedCloudBlob(payload);
      if (!cloudParseResult.wasEncrypted) {
        await logActivity(
          'cloud_blob_migrated_to_encrypted',
          details: 'Migrated legacy plaintext cloud blob to encrypted format',
        );
      }
    }

    await _syncPhotos(merged);
    await _writePendingConflicts(conflicts);
    await _writeLastSyncAt(now);
    await maybeCreateCadenceSnapshots();
    await logActivity(
      auto ? 'auto_sync' : 'manual_sync',
      details:
          'Local ${localContacts.length}, cloud ${cloudContacts.length}, merged ${merged.length}, conflicts ${conflicts.length}',
    );

    return SyncResult(
      localCount: localContacts.length,
      cloudCount: cloudContacts.length,
      mergedCount: merged.length,
      conflicts: conflicts,
      pushedToCloud: cloudNeedsUpdate,
      pulledFromCloud: localNeedsUpdate,
      skipped: false,
    );
  }

  Future<int> pullCloudToLocal() async {
    if (_supabaseService.currentUser == null) {
      throw StateError('No authenticated user found. Please sign in again.');
    }
    final String? cloudBlob =
        await _supabaseService.fetchEncryptedVaultBlobForCurrentUser();
    final _CloudBlobParseResult cloudParseResult =
        await _parseCloudBlob(cloudBlob);
    final List<VaultContact> cloudContacts = cloudParseResult.contacts;
    await _replaceSavedContacts(
      cloudContacts,
      shouldCreateSnapshot: true,
      snapshotReason: 'Before pull from cloud',
    );
    if (!cloudParseResult.wasEncrypted) {
      final String encryptedPayload = await _buildCloudBlob(cloudContacts);
      await _supabaseService.upsertEncryptedVaultBlobForCurrentUser(
        encryptedPayload,
      );
      await _securityRepository.saveCachedCloudBlob(encryptedPayload);
      await logActivity(
        'cloud_blob_migrated_to_encrypted',
        details: 'Migrated legacy plaintext cloud blob during pull',
      );
    }
    await _syncPhotos(cloudContacts);
    await _writeLastSyncAt(DateTime.now().toUtc());
    await logActivity('cloud_pull',
        details: 'Pulled ${cloudContacts.length} contacts from cloud');
    return cloudContacts.length;
  }

  Future<int> pushLocalToCloud() async {
    if (_supabaseService.currentUser == null) {
      throw StateError('No authenticated user found. Please sign in again.');
    }
    final List<VaultContact> contacts = await loadSavedContacts();
    final String blob = await _buildCloudBlob(contacts);
    await _supabaseService.upsertEncryptedVaultBlobForCurrentUser(blob);
    await _securityRepository.saveCachedCloudBlob(blob);
    await _syncPhotos(contacts);
    await _writeLastSyncAt(DateTime.now().toUtc());
    await logActivity('cloud_push',
        details: 'Pushed ${contacts.length} contacts to cloud');
    return contacts.length;
  }

  /// Syncs photos between local storage and Supabase Storage.
  /// - Contacts with a local photo are uploaded to the cloud.
  /// - Contacts whose photo exists only in the cloud are downloaded locally.
  Future<void> _syncPhotos(List<VaultContact> contacts) async {
    final String? userId = _supabaseService.currentUser?.id;
    if (userId == null) return;

    for (final VaultContact contact in contacts) {
      if (contact.photoPath == null) continue;
      final bool hasLocal = await _photoService.getLocalFile(contact.id) != null;
      if (hasLocal) {
        await _photoService.uploadToCloud(userId, contact.id);
      } else {
        await _photoService.downloadFromCloud(userId, contact.id);
      }
    }
  }

  Future<List<ContactMergeConflict>> readPendingConflicts() async {
    final String? raw = await _securityRepository.readString(
      LocalSecurityRepository.pendingConflictsStorageKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return <ContactMergeConflict>[];
    }
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <ContactMergeConflict>[];
    }
    final List<ContactMergeConflict> conflicts = <ContactMergeConflict>[];
    for (final dynamic item in decoded) {
      final Map<String, dynamic>? map = _readJsonMap(item);
      if (map == null) {
        continue;
      }
      conflicts.add(ContactMergeConflict.fromJson(map));
    }
    return conflicts;
  }

  Future<void> clearPendingConflicts() async {
    await _securityRepository
        .deleteKey(LocalSecurityRepository.pendingConflictsStorageKey);
  }

  Future<void> resolveConflict({
    required String contactId,
    required VaultContact resolvedContact,
  }) async {
    final List<VaultContact> local = await loadSavedContacts();
    bool updated = false;
    final List<VaultContact> next = local.map((VaultContact contact) {
      if (contact.id == contactId) {
        updated = true;
        return resolvedContact;
      }
      return contact;
    }).toList();
    if (!updated) {
      next.add(resolvedContact);
    }
    await _replaceSavedContacts(next, shouldCreateSnapshot: true);

    final List<ContactMergeConflict> conflicts = await readPendingConflicts();
    conflicts.removeWhere(
        (ContactMergeConflict item) => item.contactId == contactId);
    await _writePendingConflicts(conflicts);
    await pushLocalToCloud();
    await logActivity('sync_conflict_resolved',
        details: 'Resolved conflict for $contactId');
  }

  Future<void> _replaceSavedContacts(
    List<VaultContact> contacts, {
    required bool shouldCreateSnapshot,
    String snapshotReason = 'Before replacing local contacts',
  }) async {
    if (!_database.isOpen) {
      throw StateError(
        'Local vault is not open on this device. Please sign out and sign in again.',
      );
    }
    if (shouldCreateSnapshot) {
      await createSnapshot(reason: snapshotReason);
    }
    final List<VaultContact> deduped = <VaultContact>[];
    final Set<String> ids = <String>{};
    for (final VaultContact item in contacts) {
      if (ids.add(item.id)) {
        deduped.add(item);
      }
    }
    final List<String> payloads =
        deduped.map((VaultContact item) => item.toStoragePayload()).toList();
    await _database.replaceAllContactPayloads(payloads);
  }

  Future<void> _writeSnapshots(List<VaultSnapshot> snapshots) async {
    final String encoded = jsonEncode(
      snapshots.map((VaultSnapshot item) => item.toJson()).toList(),
    );
    await _securityRepository.writeString(
      key: LocalSecurityRepository.snapshotStorageKey,
      value: encoded,
    );
  }

  Future<void> _writePendingConflicts(
      List<ContactMergeConflict> conflicts) async {
    final String encoded = jsonEncode(
      conflicts.map((ContactMergeConflict item) => item.toJson()).toList(),
    );
    await _securityRepository.writeString(
      key: LocalSecurityRepository.pendingConflictsStorageKey,
      value: encoded,
    );
  }

  Future<DateTime?> _readLastSyncAt() async {
    final String? raw = await _securityRepository.readString(
      LocalSecurityRepository.lastSyncAtStorageKey,
    );
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> _writeLastSyncAt(DateTime value) async {
    await _securityRepository.writeString(
      key: LocalSecurityRepository.lastSyncAtStorageKey,
      value: value.toUtc().toIso8601String(),
    );
  }

  VaultContact _decodeContact(Map<String, dynamic> payload) {
    if (payload.containsKey('fieldUpdatedAt')) {
      return VaultContact.fromJson(payload);
    }
    return VaultContact.fromLegacyPayload(payload);
  }

  Future<_CloudBlobParseResult> _parseCloudBlob(String? cloudBlob) async {
    if (cloudBlob == null || cloudBlob.trim().isEmpty) {
      return _CloudBlobParseResult(
        contacts: <VaultContact>[],
        wasEncrypted: true,
      );
    }
    final Map<String, dynamic>? root = _readJsonMap(cloudBlob);
    if (root == null) {
      return _CloudBlobParseResult(
        contacts: <VaultContact>[],
        wasEncrypted: true,
      );
    }

    final bool appearsEncrypted = root['format'] == 'ztc_cloud_cipher_v1' ||
        (root.containsKey('nonce') &&
            root.containsKey('cipherText') &&
            root.containsKey('mac'));
    if (appearsEncrypted) {
      final String decrypted = await _decryptCloudBlob(root);
      final Map<String, dynamic>? plainRoot = _readJsonMap(decrypted);
      if (plainRoot == null) {
        throw StateError('Decrypted cloud payload is invalid.');
      }
      return _CloudBlobParseResult(
        contacts: _contactsFromDynamic(plainRoot['contacts']),
        wasEncrypted: true,
      );
    }

    return _CloudBlobParseResult(
      contacts: _contactsFromDynamic(root['contacts']),
      wasEncrypted: false,
    );
  }

  Future<String> _buildCloudBlob(List<VaultContact> contacts) async {
    final String plainPayload = jsonEncode(<String, dynamic>{
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'contacts':
          contacts.map((VaultContact contact) => contact.toJson()).toList(),
    });
    return _encryptCloudBlob(plainPayload);
  }

  List<VaultContact> _contactsFromDynamic(dynamic rawContacts) {
    if (rawContacts is! List) {
      return <VaultContact>[];
    }
    final List<VaultContact> contacts = <VaultContact>[];
    for (final dynamic item in rawContacts) {
      final Map<String, dynamic>? map = _readJsonMap(item);
      if (map == null) {
        continue;
      }
      contacts.add(_decodeContact(map));
    }
    return contacts;
  }

  Future<String> _encryptCloudBlob(String plainText) async {
    final Uint8List? keyBytes = await _securityRepository.readEncryptedDbKey();
    if (keyBytes == null || keyBytes.isEmpty) {
      throw StateError(
        'Missing local encryption key. Please sign out and sign in again.',
      );
    }

    final Uint8List nonce = _randomBytes(12);
    final AesGcm algorithm = AesGcm.with256bits();
    final SecretBox secretBox = await algorithm.encrypt(
      utf8.encode(plainText),
      nonce: nonce,
      secretKey: SecretKey(keyBytes),
    );

    return jsonEncode(<String, dynamic>{
      'format': 'ztc_cloud_cipher_v1',
      'alg': 'AES-256-GCM',
      'encryptedAt': DateTime.now().toUtc().toIso8601String(),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<String> _decryptCloudBlob(Map<String, dynamic> encrypted) async {
    final Uint8List? keyBytes = await _securityRepository.readEncryptedDbKey();
    if (keyBytes == null || keyBytes.isEmpty) {
      throw StateError(
        'Missing local encryption key. Please sign out and sign in again.',
      );
    }

    final String nonceEncoded = (encrypted['nonce'] ?? '').toString();
    final String cipherEncoded = (encrypted['cipherText'] ?? '').toString();
    final String macEncoded = (encrypted['mac'] ?? '').toString();
    if (nonceEncoded.isEmpty || cipherEncoded.isEmpty || macEncoded.isEmpty) {
      throw StateError('Encrypted cloud payload is incomplete.');
    }

    final Uint8List nonce = Uint8List.fromList(base64Decode(nonceEncoded));
    final Uint8List cipherText =
        Uint8List.fromList(base64Decode(cipherEncoded));
    final Uint8List macBytes = Uint8List.fromList(base64Decode(macEncoded));

    final AesGcm algorithm = AesGcm.with256bits();
    try {
      final List<int> plainBytes = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(keyBytes),
      );
      return utf8.decode(plainBytes);
    } catch (_) {
      throw StateError(
        'Failed to decrypt cloud data. Your local key may not match this vault.',
      );
    }
  }

  Future<Map<String, dynamic>> _encryptTextWithPassphrase({
    required String plainText,
    required String passphrase,
  }) async {
    if (passphrase.trim().length < 8) {
      throw StateError('Passphrase must be at least 8 characters.');
    }

    final Uint8List salt = _randomBytes(16);
    final Uint8List nonce = _randomBytes(12);
    final Pbkdf2 pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 240000,
      bits: 256,
    );
    final SecretKey key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final List<int> secret = await key.extractBytes();
    final AesGcm algorithm = AesGcm.with256bits();
    final SecretBox secretBox = await algorithm.encrypt(
      utf8.encode(plainText),
      nonce: nonce,
      secretKey: SecretKey(secret),
    );

    return <String, dynamic>{
      'alg': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 240000,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  Future<String> _decryptTextWithPassphrase({
    required Map<String, dynamic> encrypted,
    required String passphrase,
  }) async {
    final int iterations =
        int.tryParse((encrypted['iterations'] ?? '').toString()) ?? 240000;
    final String saltEncoded = (encrypted['salt'] ?? '').toString();
    final String nonceEncoded = (encrypted['nonce'] ?? '').toString();
    final String cipherEncoded = (encrypted['cipherText'] ?? '').toString();
    final String macEncoded = (encrypted['mac'] ?? '').toString();

    if (saltEncoded.isEmpty ||
        nonceEncoded.isEmpty ||
        cipherEncoded.isEmpty ||
        macEncoded.isEmpty) {
      throw StateError('Encrypted payload is incomplete.');
    }

    final Uint8List salt = Uint8List.fromList(base64Decode(saltEncoded));
    final Uint8List nonce = Uint8List.fromList(base64Decode(nonceEncoded));
    final Uint8List cipherText =
        Uint8List.fromList(base64Decode(cipherEncoded));
    final Uint8List macBytes = Uint8List.fromList(base64Decode(macEncoded));

    final Pbkdf2 pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final SecretKey key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final List<int> secret = await key.extractBytes();
    final AesGcm algorithm = AesGcm.with256bits();

    try {
      final List<int> plain = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
        secretKey: SecretKey(secret),
      );
      return utf8.decode(plain);
    } catch (_) {
      throw StateError('Invalid passphrase or corrupted encrypted payload.');
    }
  }

  List<VaultContact> _parseVCard(String raw) {
    final List<VaultContact> contacts = <VaultContact>[];
    final List<String> lines = raw.split(RegExp(r'\r?\n'));
    bool inCard = false;
    final Map<String, dynamic> current = <String, dynamic>{
      'phones': <String>[],
      'emails': <String>[],
      'addresses': <String>[],
      'labels': <String>[],
      'birthdays': <String>[],
      'other': <String>[],
    };

    void finalizeCard() {
      final VaultContact contact = VaultContact.fromLegacyPayload(
        <String, dynamic>{
          'id': VaultContact.generateId(),
          'displayName': current['displayName'] ??
              current['firstName'] ??
              current['lastName'] ??
              '',
          'firstName': current['firstName'] ?? '',
          'lastName': current['lastName'] ?? '',
          'company': current['company'] ?? '',
          'notes': current['notes'] ?? '',
          'phones': current['phones'],
          'emails': current['emails'],
          'addresses': current['addresses'],
          'labels': current['labels'],
          'birthdays': current['birthdays'],
          'other': current['other'],
          'source': 'Saved',
        },
      );
      contacts.add(contact);
    }

    for (final String rawLine in lines) {
      final String line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.toUpperCase() == 'BEGIN:VCARD') {
        inCard = true;
        current
          ..clear()
          ..addAll(<String, dynamic>{
            'phones': <String>[],
            'emails': <String>[],
            'addresses': <String>[],
            'labels': <String>[],
            'birthdays': <String>[],
            'other': <String>[],
          });
        continue;
      }
      if (line.toUpperCase() == 'END:VCARD') {
        if (inCard) {
          finalizeCard();
        }
        inCard = false;
        continue;
      }
      if (!inCard) {
        continue;
      }

      if (line.startsWith('FN:')) {
        current['displayName'] = _unescapeVCard(line.substring(3));
      } else if (line.startsWith('N:')) {
        final String value = _unescapeVCard(line.substring(2));
        final List<String> parts = value.split(';');
        if (parts.isNotEmpty) {
          current['lastName'] = parts[0];
        }
        if (parts.length > 1) {
          current['firstName'] = parts[1];
        }
      } else if (line.startsWith('TEL')) {
        final int split = line.indexOf(':');
        if (split != -1) {
          (current['phones'] as List<String>)
              .add(_unescapeVCard(line.substring(split + 1)));
        }
      } else if (line.startsWith('EMAIL')) {
        final int split = line.indexOf(':');
        if (split != -1) {
          (current['emails'] as List<String>)
              .add(_unescapeVCard(line.substring(split + 1)));
        }
      } else if (line.startsWith('ORG:')) {
        current['company'] = _unescapeVCard(line.substring(4));
      } else if (line.startsWith('NOTE:')) {
        current['notes'] = _unescapeVCard(line.substring(5));
      } else if (line.startsWith('BDAY:')) {
        (current['birthdays'] as List<String>)
            .add(_unescapeVCard(line.substring(5)));
      } else if (line.startsWith('ADR')) {
        final int split = line.indexOf(':');
        if (split != -1) {
          (current['addresses'] as List<String>)
              .add(_unescapeVCard(line.substring(split + 1)));
        }
      }
    }
    return contacts;
  }

  String _escapeVCard(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
  }

  String _unescapeVCard(String value) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', '\\');
  }

  String _generatePassphrase() {
    final Random random = Random.secure();
    const String chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String block() {
      return List<String>.generate(
          4, (_) => chars[random.nextInt(chars.length)]).join();
    }

    return '${block()}-${block()}-${block()}';
  }

  Uint8List _randomBytes(int length) {
    final Random random = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)));
  }

  bool _sameContactSets(List<VaultContact> first, List<VaultContact> second) {
    if (first.length != second.length) {
      return false;
    }
    final Map<String, String> a = <String, String>{
      for (final VaultContact contact in first) contact.id: contact.fingerprint,
    };
    final Map<String, String> b = <String, String>{
      for (final VaultContact contact in second)
        contact.id: contact.fingerprint,
    };
    if (a.length != b.length) {
      return false;
    }
    for (final MapEntry<String, String> entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static Map<String, dynamic>? _readJsonMap(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      try {
        final dynamic decoded = jsonDecode(value);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final Iterator<T> iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
