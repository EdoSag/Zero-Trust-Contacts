import 'package:zerotrust_contacts/models/vault_contact.dart';

/// What an import will do, worked out before anything is written so the user
/// can see it first.
class ContactImportPlan {
  ContactImportPlan({
    required this.toAdd,
    required this.toUpdate,
    required this.unchangedCount,
  });

  /// Contacts that are not in the vault yet.
  final List<VaultContact> toAdd;

  /// Vault contacts that gain new details (extra phone, email, birthday...).
  final List<VaultContact> toUpdate;

  /// Incoming contacts that are already in the vault with nothing new.
  final int unchangedCount;

  int get changeCount => toAdd.length + toUpdate.length;
  bool get isEmpty => changeCount == 0;
}

/// Matches incoming contacts against the vault so re-importing the same
/// Google account or file never creates duplicates.
///
/// A contact matches when it shares a phone number or email address with a
/// vault contact; when neither side has any, an identical full name counts.
/// Matches are merged additively: new phones, emails, addresses, labels,
/// birthdays and notes are added, and nothing the user already has is
/// overwritten or removed.
class ContactImportPlanner {
  const ContactImportPlanner();

  ContactImportPlan plan({
    required List<VaultContact> existing,
    required List<VaultContact> incoming,
  }) {
    final Map<String, VaultContact> working = <String, VaultContact>{
      for (final VaultContact contact in existing) contact.id: contact,
    };
    final Map<String, String> index = <String, String>{};
    final Set<String> updatedIds = <String>{};
    final List<VaultContact> added = <VaultContact>[];
    int unchanged = 0;

    void indexContact(VaultContact contact) {
      for (final String key in _keys(contact)) {
        index.putIfAbsent(key, () => contact.id);
      }
    }

    existing.forEach(indexContact);

    for (final VaultContact candidate in incoming) {
      String? matchId;
      for (final String key in _keys(candidate)) {
        matchId = index[key];
        if (matchId != null) {
          break;
        }
      }

      if (matchId == null) {
        working[candidate.id] = candidate;
        added.add(candidate);
        indexContact(candidate);
        continue;
      }

      final VaultContact current = working[matchId]!;
      final VaultContact merged = _mergeInto(current, candidate);
      if (identical(merged, current)) {
        unchanged += 1;
        continue;
      }
      working[matchId] = merged;
      indexContact(merged);
      final int addedIndex =
          added.indexWhere((VaultContact c) => c.id == matchId);
      if (addedIndex != -1) {
        // Two incoming cards for the same person: keep one combined new contact.
        added[addedIndex] = merged;
      } else {
        updatedIds.add(matchId);
      }
    }

    return ContactImportPlan(
      toAdd: added,
      toUpdate: updatedIds.map((String id) => working[id]!).toList(),
      unchangedCount: unchanged,
    );
  }

  /// Applies [plan] to [existing] and returns the full new contact list.
  List<VaultContact> apply(
      List<VaultContact> existing, ContactImportPlan plan) {
    final Map<String, VaultContact> updates = <String, VaultContact>{
      for (final VaultContact contact in plan.toUpdate) contact.id: contact,
    };
    return <VaultContact>[
      ...existing.map((VaultContact c) => updates[c.id] ?? c),
      ...plan.toAdd,
    ];
  }

  Iterable<String> _keys(VaultContact contact) sync* {
    bool hasStrongKey = false;
    for (final String phone in contact.phones) {
      final String normalized = _phoneKey(phone);
      if (normalized.length >= 5) {
        hasStrongKey = true;
        yield 'phone:$normalized';
      }
    }
    for (final String email in contact.emails) {
      final String normalized = VaultContact.normalizedEmail(email);
      if (normalized.isNotEmpty) {
        hasStrongKey = true;
        yield 'email:$normalized';
      }
    }
    if (!hasStrongKey) {
      final String name = VaultContact.normalizedName(contact.displayName);
      if (name.isNotEmpty && name != 'unnamed contact') {
        yield 'name:$name';
      }
    }
  }

  /// Compares numbers on their last 9 digits so "+44 7700 900123" and
  /// "07700 900123" are treated as the same phone.
  static String _phoneKey(String phone) {
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  /// Returns [current] itself when [incoming] adds nothing.
  VaultContact _mergeInto(VaultContact current, VaultContact incoming) {
    List<String>? union(
        List<String> a, List<String> b, String Function(String) normalize) {
      final Set<String> seen = a.map(normalize).toSet();
      final List<String> extra =
          b.where((String value) => seen.add(normalize(value))).toList();
      return extra.isEmpty ? null : <String>[...a, ...extra];
    }

    String? fill(String currentValue, String incomingValue) {
      return currentValue.trim().isEmpty && incomingValue.trim().isNotEmpty
          ? incomingValue
          : null;
    }

    String lower(String value) => value.trim().toLowerCase();

    final List<String>? phones =
        union(current.phones, incoming.phones, _phoneKey);
    final List<String>? emails =
        union(current.emails, incoming.emails, VaultContact.normalizedEmail);
    final List<String>? addresses =
        union(current.addresses, incoming.addresses, lower);
    final List<String>? labels = union(current.labels, incoming.labels, lower);
    final List<String>? birthdays =
        union(current.birthdays, incoming.birthdays, (String e) => e);
    final List<String>? other = union(current.other, incoming.other, lower);
    final String? firstName = fill(current.firstName, incoming.firstName);
    final String? lastName = fill(current.lastName, incoming.lastName);
    final String? company = fill(current.company, incoming.company);
    String? notes = fill(current.notes, incoming.notes);
    if (notes == null &&
        incoming.notes.trim().isNotEmpty &&
        !current.notes.contains(incoming.notes.trim())) {
      notes = '${current.notes}\n\n${incoming.notes.trim()}';
    }
    final bool? favorite =
        incoming.isFavorite && !current.isFavorite ? true : null;

    final bool changed = <Object?>[
      phones,
      emails,
      addresses,
      labels,
      birthdays,
      other,
      firstName,
      lastName,
      company,
      notes,
      favorite,
    ].any((Object? value) => value != null);
    if (!changed) {
      return current;
    }
    return current.applyEdits(
      phones: phones,
      emails: emails,
      addresses: addresses,
      labels: labels,
      birthdays: birthdays,
      other: other,
      firstName: firstName,
      lastName: lastName,
      company: company,
      notes: notes,
      isFavorite: favorite,
    );
  }
}
