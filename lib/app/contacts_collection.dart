import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Contacts as items of the account's synced store. One item per contact,
/// its id the contact's id.
final ZtCollection<VaultContact> contactsCollection =
    ZtCollection<VaultContact>(
  kind: 'contact',
  version: 1,
  fromJson: (String id, Map<String, Object?> json, DateTime _) =>
      VaultContact.fromJson(<String, dynamic>{...json, 'id': id}),
  toJson: (VaultContact contact) => contact.toJson(),
  idOf: (VaultContact contact) => contact.id,
);
