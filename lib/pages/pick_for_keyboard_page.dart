import 'package:flutter/material.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// One thing of a contact that ZT Keyboard can type.
class PickValue {
  const PickValue(this.field, this.text);

  /// `name`, `phone`, `email` or `address`.
  final String field;
  final String text;
}

/// What can be typed for [contact]: the name, then every phone number, email
/// and address, without blanks or repeats.
List<PickValue> pickValuesOf(VaultContact contact) {
  final List<PickValue> values = <PickValue>[];
  final Set<String> seen = <String>{};
  void add(String field, String raw) {
    final String text = raw.trim();
    if (text.isNotEmpty && seen.add(text)) {
      values.add(PickValue(field, text));
    }
  }

  add('name', contact.displayName);
  for (final String phone in contact.phones) {
    add('phone', phone);
  }
  for (final String email in contact.emails) {
    add('email', email);
  }
  for (final String address in contact.addresses) {
    add('address', address);
  }
  return values;
}

/// The contacts among [contacts] whose name, number, email or company holds
/// [query], A to Z. Numbers match whatever their spacing.
List<VaultContact> pickMatches(List<VaultContact> contacts, String query) {
  final String needle = query.trim().toLowerCase();
  final String digits = needle.replaceAll(RegExp(r'[^0-9]'), '');
  bool matches(VaultContact contact) {
    if (needle.isEmpty) {
      return true;
    }
    if (contact.displayName.toLowerCase().contains(needle) ||
        contact.company.toLowerCase().contains(needle) ||
        contact.emails.any((String e) => e.toLowerCase().contains(needle))) {
      return true;
    }
    return digits.isNotEmpty &&
        contact.phones.any(
          (String p) => p.replaceAll(RegExp(r'[^0-9]'), '').contains(digits),
        );
  }

  return contacts
      .where((VaultContact c) => pickValuesOf(c).isNotEmpty && matches(c))
      .toList()
    ..sort((VaultContact a, VaultContact b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
}

/// A contact of the phone's address book (not in the vault) with every
/// field read from the phone: the list only carries its name and first
/// number (C-8). [fields] is what the Android side returns for it; the
/// list's own name and id are kept.
VaultContact withPhoneDetails(VaultContact listed, Map<String, dynamic>? fields) {
  if (fields == null) return listed;
  final VaultContact full = accountImportFromFields(
      <Map<String, dynamic>>[fields]).contacts.single;
  List<String> union(List<String> a, List<String> b) =>
      <String>{...a, ...b}.toList();
  return listed.copyWith(
    phones: union(listed.phones, full.phones),
    emails: full.emails,
    addresses: full.addresses,
    company: listed.company.isEmpty ? full.company : listed.company,
    valueTypes: full.valueTypes,
  );
}

/// Contacts in the picker that come from the phone, not the vault.
bool isPhoneOnly(VaultContact contact) => contact.id.startsWith('device_');

/// Opened by ZT Keyboard's "Insert from ZT apps" key, after the vault was
/// unlocked: the user taps a contact and then the one thing to type. Pops
/// with that text, or with nothing when the user goes back.
class PickForKeyboardPage extends StatefulWidget {
  const PickForKeyboardPage({
    super.key,
    required this.contacts,
    this.loadPhoneDetails,
  });

  final List<VaultContact> contacts;

  /// Reads every field of a phone-only contact (by its Android id, the
  /// part after `device_`). Null: only what the list holds.
  final Future<Map<String, dynamic>?> Function(String deviceId)?
      loadPhoneDetails;

  @override
  State<PickForKeyboardPage> createState() => _PickForKeyboardPageState();
}

class _PickForKeyboardPageState extends State<PickForKeyboardPage> {
  String _query = '';

  String _fieldLabel(BuildContext context, VaultContact contact, PickValue v) {
    final AppL10n l10n = context.l10n;
    return switch (v.field) {
      'name' => l10n.name,
      'phone' => contact.typeLabel('phone', v.text, fallback: l10n.phoneLabel),
      'email' => contact.typeLabel('email', v.text, fallback: l10n.email),
      _ => contact.typeLabel('address', v.text, fallback: l10n.address),
    };
  }

  IconData _icon(String field) => switch (field) {
        'name' => Icons.person_outline,
        'phone' => Icons.phone_outlined,
        'email' => Icons.email_outlined,
        _ => Icons.place_outlined,
      };

  Future<void> _open(VaultContact listed) async {
    VaultContact contact = listed;
    final Future<Map<String, dynamic>?> Function(String)? load =
        widget.loadPhoneDetails;
    if (load != null && isPhoneOnly(listed)) {
      try {
        contact = withPhoneDetails(
            listed, await load(listed.id.substring('device_'.length)));
      } on Object {
        // Not readable now: offer what the list has.
      }
      if (!mounted) return;
    }
    final List<PickValue> values = pickValuesOf(contact);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final PickValue value in values)
                ListTile(
                  leading: Icon(_icon(value.field)),
                  title: Text(
                    value.field == 'name' ? value.text : ltr(value.text),
                  ),
                  subtitle: Text(_fieldLabel(sheet, contact, value)),
                  onTap: () => Navigator.of(sheet).pop(value.text),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      Navigator.of(context).pop(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l10n = context.l10n;
    final List<VaultContact> matches = pickMatches(widget.contacts, _query);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.insertIntoKeyboard)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.searchContacts,
                helperText: l10n.insertPickHint,
              ),
              onChanged: (String value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(child: Text(l10n.insertNothingToInsert))
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (BuildContext context, int index) {
                      final VaultContact contact = matches[index];
                      final String detail = contact.phones.isNotEmpty
                          ? ltr(contact.phones.first)
                          : contact.emails.isNotEmpty
                              ? ltr(contact.emails.first)
                              : contact.company;
                      return ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          contact.displayName.trim().isEmpty
                              ? detail
                              : contact.displayName,
                        ),
                        subtitle: detail.isEmpty ? null : Text(detail),
                        onTap: () => _open(contact),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
