import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';

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

/// A local edit that lost to a newer edit from another device. The newer
/// version is what's saved now; [mine] is kept so the user can restore it.
class ContactConflict {
  ContactConflict({required this.contactId, required this.mine, this.current});

  final String contactId;

  /// This device's edit, which lost.
  final VaultContact mine;

  /// The saved version that won, or null if it was deleted.
  final VaultContact? current;
}

/// The address book, on top of the core: contacts are items of the
/// account's encrypted local store, synced per contact by the core's sync
/// controller. Restore points and the activity log stay on this device in a
/// sealed [LocalVaultFile].
class VaultRepository {
  VaultRepository({
    required LocalItemStore store,
    required SyncController sync,
    required LocalVaultFile localFile,
    ContactPhotos? photos,
    Stream<Set<String>>? changes,
  })  : _store = store,
        _sync = sync,
        _localFile = localFile,
        _photos = photos,
        changes = changes ?? const Stream<Set<String>>.empty();

  static const int _maxActivityEntries = 200;
  static const int _maxSnapshots = 20;

  final LocalItemStore _store;
  final SyncController _sync;
  final LocalVaultFile _localFile;
  final ContactPhotos? _photos;

  /// Item ids changed in the store (local edits and other devices' edits).
  final Stream<Set<String>> changes;

  Future<List<VaultContact>> loadSavedContacts() async {
    final List<VaultContact> contacts = await contactsCollection.list(_store)
      ..sort((VaultContact a, VaultContact b) =>
          b.updatedAt.compareTo(a.updatedAt));
    return contacts;
  }

  /// Contacts saved by a newer version of the app, which this one can't show.
  Future<int> newerVersionCount() async =>
      (await contactsCollection.newerItems(_store)).length;

  Future<VaultContact?> findSavedContactById(String id) =>
      contactsCollection.get(_store, id);

  Future<void> upsertSavedContact(
    VaultContact contact, {
    String activity = 'contact_upsert',
  }) async {
    final VaultContact? existing = await findSavedContactById(contact.id);
    await contactsCollection.save(_sync, _store, contact);
    await _deleteReplacedPhoto(existing, contact);
    await maybeCreateCadenceSnapshots();
    await logActivity(
      activity,
      details: '${existing != null ? 'Updated' : 'Created'} '
          '${contact.displayName}',
    );
  }

  Future<bool> deleteSavedContact(String contactId) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return false;
    }
    await createSnapshot(reason: 'Before deleting ${target.displayName}');
    await contactsCollection.delete(_sync, contactId);
    await _photos?.deletePhotoOf(target);
    await logActivity('contact_delete',
        details: 'Deleted ${target.displayName}');
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

  Future<void> blockContact(String contactId, {String? reason}) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return;
    }
    final String? trimmedReason =
        (reason?.trim().isEmpty ?? true) ? null : reason!.trim();
    await upsertSavedContact(
      target.applyEdits(isBlocked: true, blockReason: trimmedReason),
      activity: 'contact_block',
    );
  }

  Future<void> unblockContact(String contactId) async {
    final VaultContact? target = await findSavedContactById(contactId);
    if (target == null) {
      return;
    }
    await upsertSavedContact(
      target.applyEdits(isBlocked: false, clearBlockReason: true),
      activity: 'contact_unblock',
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
    await _replaceSavedContacts(
      saved,
      shouldCreateSnapshot: true,
      snapshotReason: 'Before merging duplicates',
    );
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
    final Map<String, Object?> data = await _localFile.read();
    final List<SecurityActivityEntry> current = _activityFrom(data);
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
    data['activity'] = current
        .take(_maxActivityEntries)
        .map((SecurityActivityEntry item) => item.toJson())
        .toList();
    await _localFile.write(data);
  }

  Future<List<SecurityActivityEntry>> readActivityEntries(
      {int limit = 100}) async {
    return _activityFrom(await _localFile.read()).take(limit).toList();
  }

  List<SecurityActivityEntry> _activityFrom(Map<String, Object?> data) {
    final Object? raw = data['activity'];
    if (raw is! List) {
      return <SecurityActivityEntry>[];
    }
    return <SecurityActivityEntry>[
      for (final Object? item in raw)
        if (_readJsonMap(item) case final Map<String, dynamic> map)
          SecurityActivityEntry.fromJson(map),
    ];
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
    final Map<String, Object?> data = await _localFile.read();
    final List<VaultSnapshot> current = _snapshotsFrom(data);
    current.insert(0, snapshot);
    data['snapshots'] = current
        .take(_maxSnapshots)
        .map((VaultSnapshot item) => item.toJson())
        .toList();
    await _localFile.write(data);
    return snapshot;
  }

  /// Daily and weekly restore points, taken on the first edit after each is
  /// due.
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
    return _snapshotsFrom(await _localFile.read()).take(limit).toList();
  }

  List<VaultSnapshot> _snapshotsFrom(Map<String, Object?> data) {
    final Object? raw = data['snapshots'];
    if (raw is! List) {
      return <VaultSnapshot>[];
    }
    return <VaultSnapshot>[
      for (final Object? item in raw)
        if (_readJsonMap(item) case final Map<String, dynamic> map)
          VaultSnapshot.fromJson(map),
    ]..sort((VaultSnapshot a, VaultSnapshot b) =>
        b.createdAt.compareTo(a.createdAt));
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
      snapshotReason: 'Before restoring a restore point',
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
    final ContactImportPlan plan = await importContacts(
      const VCardParser().parse(rawVCard),
      sourceLabel: 'vCard',
    );
    return plan.changeCount;
  }

  /// Works out what importing [incoming] would add or update, without
  /// writing anything.
  Future<ContactImportPlan> planImport(List<VaultContact> incoming) async {
    final List<VaultContact> local = await loadSavedContacts();
    return const ContactImportPlanner().plan(
      existing: local,
      incoming: incoming,
    );
  }

  /// Adds [incoming] to the vault, merging matches into existing contacts so
  /// nothing is duplicated. A restore point is taken first, so the whole
  /// import can be undone from Account & Vault.
  Future<ContactImportPlan> importContacts(
    List<VaultContact> incoming, {
    required String sourceLabel,
  }) async {
    final List<VaultContact> local = await loadSavedContacts();
    const ContactImportPlanner planner = ContactImportPlanner();
    final ContactImportPlan plan =
        planner.plan(existing: local, incoming: incoming);
    if (plan.isEmpty) {
      return plan;
    }
    await _replaceSavedContacts(
      planner.apply(local, plan),
      shouldCreateSnapshot: true,
      snapshotReason: 'Before import from $sourceLabel',
    );
    await logActivity(
      'contacts_import',
      details: 'Imported from $sourceLabel: ${plan.toAdd.length} new, '
          '${plan.toUpdate.length} updated',
    );
    return plan;
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

  /// Local edits that lost to a newer edit from another device since the
  /// app was opened, from the core's sync status.
  Future<List<ContactConflict>> conflictsFrom(SyncStatus status) async {
    final List<ContactConflict> result = <ContactConflict>[];
    for (final SyncConflict conflict in status.conflicts) {
      final LocalItem lost = conflict.lostLocal;
      final VaultContact? mine =
          lost.json == null ? null : contactsCollection.decode(lost);
      if (mine == null) {
        continue;
      }
      result.add(ContactConflict(
        contactId: conflict.itemId,
        mine: mine,
        current: await findSavedContactById(conflict.itemId),
      ));
    }
    return result;
  }

  /// Keeps [chosen] for a conflicted contact: saved as a new edit, so it
  /// wins on every device.
  Future<void> resolveConflict(VaultContact chosen) async {
    await upsertSavedContact(
      chosen.copyWith(updatedAt: DateTime.now().toUtc()),
      activity: 'sync_conflict_resolved',
    );
  }

  Future<void> syncNow() => _sync.syncNow();

  /// Makes the saved contacts equal to [contacts]: saves the new and changed
  /// ones and deletes the rest, each as its own synced change.
  Future<void> _replaceSavedContacts(
    List<VaultContact> contacts, {
    required bool shouldCreateSnapshot,
    String snapshotReason = 'Before replacing local contacts',
  }) async {
    if (shouldCreateSnapshot) {
      await createSnapshot(reason: snapshotReason);
    }
    final Map<String, VaultContact> current = <String, VaultContact>{
      for (final VaultContact item in await loadSavedContacts()) item.id: item,
    };
    final Set<String> keep = <String>{};
    for (final VaultContact item in contacts) {
      if (!keep.add(item.id)) {
        continue;
      }
      final VaultContact? existing = current[item.id];
      if (existing != null && existing.fingerprint == item.fingerprint) {
        continue;
      }
      await contactsCollection.save(_sync, _store, item);
    }
    for (final VaultContact gone in current.values) {
      if (!keep.contains(gone.id)) {
        await contactsCollection.delete(_sync, gone.id);
      }
    }
  }

  /// A replaced photo's file isn't referenced any more.
  Future<void> _deleteReplacedPhoto(
      VaultContact? before, VaultContact after) async {
    final Object? oldId = before?.photo?['id'];
    if (oldId == null || oldId == after.photo?['id']) {
      return;
    }
    await _photos?.deletePhotoOf(before!);
  }

  VaultContact _decodeContact(Map<String, dynamic> payload) {
    if (payload.containsKey('fieldUpdatedAt')) {
      return VaultContact.fromJson(payload);
    }
    return VaultContact.fromLegacyPayload(payload);
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

  String _escapeVCard(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\n', r'\n');
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
