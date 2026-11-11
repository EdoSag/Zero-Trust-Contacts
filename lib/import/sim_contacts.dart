import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Turns the SIM card rows the Android side returns (`name`, `number`,
/// `emails`) into vault contacts. SIM entries hold little: a name of up to
/// a few dozen characters, one number and sometimes an email. Several
/// entries with the same name (old phones stored one per number) become one
/// contact.
List<VaultContact> vaultContactsFromSim(List<Map<String, dynamic>> rows) {
  final Map<String, _SimEntry> byName = <String, _SimEntry>{};
  final List<_SimEntry> order = <_SimEntry>[];
  for (final Map<String, dynamic> row in rows) {
    final String name = '${row['name'] ?? ''}'.trim();
    final String number = '${row['number'] ?? ''}'.trim();
    final List<String> emails = <String>[
      if (row['emails'] case final List<dynamic> list)
        for (final dynamic e in list)
          if ('$e'.trim().contains('@')) '$e'.trim(),
    ];
    if (name.isEmpty && number.isEmpty) continue;
    // Unnamed entries stay separate: their number is all they have.
    final String key = name.isEmpty ? '#${order.length}' : name.toLowerCase();
    final _SimEntry entry = byName[key] ??= () {
      final _SimEntry created = _SimEntry(name);
      order.add(created);
      return created;
    }();
    if (number.isNotEmpty && !entry.phones.contains(number)) {
      entry.phones.add(number);
    }
    for (final String email in emails) {
      if (!entry.emails.contains(email)) entry.emails.add(email);
    }
  }
  final DateTime now = DateTime.now().toUtc();
  return <VaultContact>[
    for (final _SimEntry e in order)
      VaultContact.fromLegacyPayload(<String, dynamic>{
        'id': VaultContact.generateId(),
        'displayName': e.name.isEmpty ? e.phones.first : e.name,
        'firstName': _first(e.name),
        'lastName': _last(e.name),
        'phones': e.phones,
        'emails': e.emails,
        'source': 'Saved',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      }),
  ];
}

String _first(String name) {
  final List<String> words = name
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  if (words.length <= 1) return name;
  return words.take(words.length - 1).join(' ');
}

String _last(String name) {
  final List<String> words = name
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();
  return words.length <= 1 ? '' : words.last;
}

class _SimEntry {
  _SimEntry(this.name);

  final String name;
  final List<String> phones = <String>[];
  final List<String> emails = <String>[];
}
