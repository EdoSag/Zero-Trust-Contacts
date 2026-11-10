import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Turns the field maps the Android side returns for one account into vault
/// contacts. Kept free of Flutter so it can be unit tested.
List<VaultContact> vaultContactsFromAccountFields(
  List<Map<String, dynamic>> rows,
) => accountImportFromFields(rows).contacts;

/// Contacts of one phone account, and which of them have a photo there.
class AccountImport {
  AccountImport({required this.contacts, required this.photoRawIds});

  final List<VaultContact> contacts;

  /// The Android raw contact id to read each contact's photo from, by
  /// contact id. Photos are read one at a time during the import.
  final Map<String, int> photoRawIds;
}

AccountImport accountImportFromFields(List<Map<String, dynamic>> rows) {
  final Map<String, int> photoRawIds = <String, int>{};
  final List<VaultContact> contacts = <VaultContact>[];
  for (final Map<String, dynamic> row in rows) {
    final VaultContact contact = _contactFromRow(row);
    contacts.add(contact);
    final Object? rawId = row['rawId'];
    if (row['hasPhoto'] == true && rawId is int) {
      photoRawIds[contact.id] = rawId;
    }
  }
  return AccountImport(contacts: contacts, photoRawIds: photoRawIds);
}

VaultContact _contactFromRow(Map<String, dynamic> row) {
  List<String> strings(dynamic value) {
    if (value is! List) {
      return <String>[];
    }
    return value
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  final List<String> birthdays = strings(
    row['birthdays'],
  ).map(VCardParser.normalizeBirthday).whereType<String>().toSet().toList();
  return VaultContact.fromLegacyPayload(<String, dynamic>{
    'id': VaultContact.generateId(),
    'displayName': row['displayName'],
    'firstName': row['firstName'],
    'lastName': row['lastName'],
    'company': row['company'],
    'notes': row['notes'],
    'phones': strings(row['phones']).toSet().toList(),
    'emails': strings(row['emails']).toSet().toList(),
    'addresses': strings(row['addresses']).toSet().toList(),
    'labels': strings(row['labels']).toSet().toList(),
    'birthdays': birthdays,
    'other': strings(row['other']).toSet().toList(),
    'isFavorite': row['isFavorite'] == true,
    'valueTypes': <String, String>{
      // Kinds (mobile, work…) arrive keyed "phone\n<number>".
      if (row['types'] case final Map<dynamic, dynamic> types)
        for (final MapEntry<dynamic, dynamic> e in types.entries)
          if ('${e.key}'.split('\n') case [final String field, final String value]
              when '${e.value}'.isNotEmpty)
            VaultContact.typeKey(field, value): '${e.value}',
    },
    'source': 'Saved',
  });
}
