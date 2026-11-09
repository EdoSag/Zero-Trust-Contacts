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

/// A contact in the trash: the same item as the contact (same id), with its
/// kind switched to `contact_trash`. Moving to the trash and back is one
/// synced edit each way, and app versions from before the trash existed
/// simply don't list it (they only read `contact` items).
class TrashedContact {
  TrashedContact({required this.contact, required this.deletedAt});

  final VaultContact contact;
  final DateTime deletedAt;

  /// How long a contact stays in the trash before it is deleted for good.
  static const Duration keepFor = Duration(days: 30);

  DateTime get purgeAt => deletedAt.add(keepFor);

  bool isExpired(DateTime now) => !now.isBefore(purgeAt);

  int daysLeft(DateTime now) {
    final Duration left = purgeAt.difference(now);
    return left.isNegative ? 0 : (left.inHours / 24).ceil();
  }
}

final ZtCollection<TrashedContact> trashCollection =
    ZtCollection<TrashedContact>(
  kind: 'contact_trash',
  version: 1,
  fromJson: (String id, Map<String, Object?> json, DateTime updatedAt) =>
      TrashedContact(
    contact: VaultContact.fromJson(<String, dynamic>{...json, 'id': id}),
    deletedAt:
        DateTime.tryParse('${json['deletedAt']}')?.toUtc() ?? updatedAt.toUtc(),
  ),
  toJson: (TrashedContact item) => <String, Object?>{
    ...item.contact.toJson(),
    'deletedAt': item.deletedAt.toUtc().toIso8601String(),
  },
  idOf: (TrashedContact item) => item.contact.id,
);
