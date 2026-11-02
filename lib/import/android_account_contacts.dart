import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Turns the field maps the Android side returns for one account into vault
/// contacts. Kept free of Flutter so it can be unit tested.
List<VaultContact> vaultContactsFromAccountFields(
  List<Map<String, dynamic>> rows,
) {
  List<String> strings(dynamic value) {
    if (value is! List) {
      return <String>[];
    }
    return value
        .map((dynamic e) => e.toString().trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  return rows.map((Map<String, dynamic> row) {
    final List<String> birthdays = strings(row['birthdays'])
        .map(VCardParser.normalizeBirthday)
        .whereType<String>()
        .toSet()
        .toList();
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
      'source': 'Saved',
    });
  }).toList();
}
