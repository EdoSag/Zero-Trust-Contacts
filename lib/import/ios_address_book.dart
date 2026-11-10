import 'dart:typed_data';

import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// What was read from the iPhone address book: the contacts, and which
/// address book entry to read each one's photo from (by vault contact id).
class AddressBookImport {
  AddressBookImport({required this.contacts, required this.photoIds});

  final List<VaultContact> contacts;
  final Map<String, String> photoIds;
}

/// Reads the iPhone's own address book (iCloud and any other account the
/// Contacts app shows) so it can be imported into the vault.
///
/// iOS has no "account" an app can add contacts to the way Android does, so
/// on an iPhone the vault is filled by importing. Everything is read on the
/// phone; nothing leaves it until it is encrypted.
class IosAddressBook {
  const IosAddressBook();

  /// Asks iOS for read access. False when the user says no.
  Future<bool> requestPermission() =>
      fc.FlutterContacts.requestPermission(readonly: true);

  /// Every contact, without photos (those are read one at a time during
  /// the import so a big address book doesn't fill the memory).
  Future<AddressBookImport> read() async {
    final List<fc.Contact> all = await fc.FlutterContacts.getContacts(
      withProperties: true,
      withThumbnail: true,
      withGroups: true,
    );
    return addressBookImportFrom(all);
  }

  /// The full-size photo of one address book entry.
  Future<Uint8List?> photo(String addressBookId) async {
    final fc.Contact? contact = await fc.FlutterContacts.getContact(
      addressBookId,
      withProperties: false,
      withThumbnail: true,
      withPhoto: true,
    );
    return contact?.photoOrThumbnail;
  }
}

/// Pure mapping, so it can be tested without an iPhone.
AddressBookImport addressBookImportFrom(List<fc.Contact> all) {
  final List<fc.Contact> usable = all
      .where(
        (fc.Contact c) =>
            c.displayName.trim().isNotEmpty ||
            c.phones.isNotEmpty ||
            c.emails.isNotEmpty,
      )
      .toList();
  final List<VaultContact> contacts = vaultContactsFromAccountFields(
    usable.map(addressBookRow).toList(),
  );
  return AddressBookImport(
    contacts: contacts,
    photoIds: <String, String>{
      for (int i = 0; i < usable.length; i++)
        if (usable[i].thumbnail != null || usable[i].photo != null)
          contacts[i].id: usable[i].id,
    },
  );
}

/// One address book entry in the field-map shape the importer already
/// understands (the same one the Android account import uses).
Map<String, dynamic> addressBookRow(fc.Contact c) {
  final Map<String, String> types = <String, String>{};
  final List<String> other = <String>[];

  for (final fc.Phone p in c.phones) {
    final String? kind = switch (p.label) {
      fc.PhoneLabel.mobile ||
      fc.PhoneLabel.iPhone ||
      fc.PhoneLabel.workMobile => 'mobile',
      fc.PhoneLabel.home => 'home',
      fc.PhoneLabel.work => 'work',
      fc.PhoneLabel.main || fc.PhoneLabel.companyMain => 'main',
      fc.PhoneLabel.other => 'other',
      _ => null,
    };
    if (kind != null) types['phone\n${p.number}'] = kind;
  }
  for (final fc.Email e in c.emails) {
    final String? kind = switch (e.label) {
      fc.EmailLabel.home || fc.EmailLabel.iCloud => 'home',
      fc.EmailLabel.work => 'work',
      fc.EmailLabel.other => 'other',
      _ => null,
    };
    if (kind != null) types['email\n${e.address}'] = kind;
  }
  final List<String> addresses = <String>[];
  for (final fc.Address a in c.addresses) {
    final String text = _addressText(a);
    if (text.isEmpty) continue;
    addresses.add(text);
    final String? kind = switch (a.label) {
      fc.AddressLabel.home => 'home',
      fc.AddressLabel.work => 'work',
      fc.AddressLabel.other => 'other',
      _ => null,
    };
    if (kind != null) types['address\n$text'] = kind;
  }

  final List<String> birthdays = <String>[];
  for (final fc.Event e in c.events) {
    if (e.month < 1 || e.month > 12 || e.day < 1 || e.day > 31) continue;
    final String md =
        '${e.month.toString().padLeft(2, '0')}-'
        '${e.day.toString().padLeft(2, '0')}';
    final int? year = e.year;
    // The iPhone stores "no year" as year 1604 or as nothing at all.
    final String date = year == null || year < 1800
        ? '--$md'
        : '${year.toString().padLeft(4, '0')}-$md';
    if (e.label == fc.EventLabel.birthday) {
      birthdays.add(date);
    } else if (e.label == fc.EventLabel.anniversary) {
      other.add('Anniversary: $date');
    }
  }

  final fc.Organization? org = c.organizations.isEmpty
      ? null
      : c.organizations.first;
  if (org != null && org.title.trim().isNotEmpty) {
    other.add('Title: ${org.title.trim()}');
  }
  if (c.name.nickname.trim().isNotEmpty) {
    other.add('Nickname: ${c.name.nickname.trim()}');
  }
  for (final fc.Website w in c.websites) {
    if (w.url.trim().isNotEmpty) other.add(w.url.trim());
  }

  return <String, dynamic>{
    'displayName': c.displayName.trim(),
    'firstName': c.name.first.trim(),
    'lastName': c.name.last.trim(),
    'company': org?.company.trim() ?? '',
    'notes': c.notes
        .map((fc.Note n) => n.note.trim())
        .where((String n) => n.isNotEmpty)
        .join('\n'),
    'phones': <String>[for (final fc.Phone p in c.phones) p.number],
    'emails': <String>[for (final fc.Email e in c.emails) e.address],
    'addresses': addresses,
    'labels': <String>[for (final fc.Group g in c.groups) g.name],
    'birthdays': birthdays,
    'other': other,
    'isFavorite': c.isStarred,
    'types': types,
  };
}

String _addressText(fc.Address a) {
  final String whole = a.address
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty)
      .join(', ');
  if (whole.isNotEmpty) return whole;
  return <String>[
    a.street,
    a.city,
    a.state,
    a.postalCode,
    a.country,
  ].map((String p) => p.trim()).where((String p) => p.isNotEmpty).join(', ');
}
