import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';

VaultContact person(String id, String name,
        {List<String> phones = const <String>['+447700900123'],
        bool blocked = false,
        Map<String, Object?>? photo}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones,
      'emails': <String>['$id@example.com'],
      'isBlocked': blocked,
      'photo': photo,
    });

void main() {
  group('vCard photos', () {
    final String b64 = base64Encode(<int>[1, 2, 3, 4, 5]);
    test('embedded, data URI, link, and nonsense', () {
      final VCardImport parsed = const VCardParser().parseWithPhotos('''
BEGIN:VCARD\r
VERSION:3.0\r
FN:Embedded\r
PHOTO;ENCODING=b;TYPE=JPEG:${b64.substring(0, 4)}\r
 ${b64.substring(4)}\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:4.0\r
FN:Data\r
PHOTO:data:image/jpeg;base64,$b64\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:3.0\r
FN:Linked\r
PHOTO:https://lh3.googleusercontent.com/contacts/abc\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:3.0\r
FN:Plain http\r
PHOTO:http://example.com/a.jpg\r
END:VCARD\r
''');
      expect(parsed.contacts, hasLength(4));
      final List<VCardPhoto?> photos = parsed.contacts
          .map((VaultContact c) => parsed.photos[c.id])
          .toList();
      expect(photos[0]!.bytes, <int>[1, 2, 3, 4, 5]);
      expect(photos[1]!.bytes, <int>[1, 2, 3, 4, 5]);
      expect(photos[2]!.url!.host, 'lh3.googleusercontent.com');
      expect(photos[3], isNull, reason: 'only https links are fetched');
      expect(parsed.embeddedPhotoCount, 2);
      expect(parsed.linkedPhotoCount, 1);
    });
  });

  test('account rows keep the raw id of contacts with a photo', () {
    final AccountImport read = accountImportFromFields(<Map<String, dynamic>>[
      <String, dynamic>{'rawId': 7, 'hasPhoto': true, 'displayName': 'Ada'},
      <String, dynamic>{'rawId': 8, 'hasPhoto': false, 'displayName': 'Bo'},
    ]);
    expect(read.contacts, hasLength(2));
    expect(read.photoRawIds, <String, int>{read.contacts.first.id: 7});
  });

  test('planner says which contact each incoming one lands in', () {
    final VaultContact existing = person('e1', 'Ada');
    final VaultContact same = person('i1', 'Ada L');
    final VaultContact fresh =
        person('i2', 'Grace', phones: <String>['+15550100']);
    final ContactImportPlan plan = const ContactImportPlanner()
        .plan(existing: <VaultContact>[existing], incoming: <VaultContact>[
      same,
      fresh,
    ]);
    expect(plan.targetIdOf, <String, String>{'i1': 'e1', 'i2': 'i2'});
  });

  group('phone sync plan', () {
    const PhoneSyncPlanner planner = PhoneSyncPlanner();

    test('only chosen fields leave the vault', () {
      final PhoneSyncEntry e = planner.entryFor(
          person('1', 'Ada', photo: <String, Object?>{'id': 'p1'}),
          const PhoneSyncFields());
      expect(e.fields['phones'], <String>['+447700900123']);
      expect(e.fields['emails'], isEmpty, reason: 'emails are off by default');
      expect(e.fields['notes'], '');
      expect(e.photoId, 'p1');

      final PhoneSyncEntry noPhones = planner.entryFor(
          person('1', 'Ada', blocked: true),
          const PhoneSyncFields(phones: false, photos: false));
      expect(noPhones.fields['phones'], isEmpty);
      expect(noPhones.photoId, isNull);
      expect(noPhones.fields['sendToVoicemail'], isFalse);
    });

    test('blocked contacts go to voicemail', () {
      expect(
          planner
              .entryFor(person('1', 'Spam', blocked: true),
                  const PhoneSyncFields())
              .fields['sendToVoicemail'],
          isTrue);
    });

    test('writes only what changed and removes what is gone', () {
      final VaultContact ada = person('1', 'Ada');
      final VaultContact bo = person('2', 'Bo');
      const PhoneSyncFields f = PhoneSyncFields();
      final Map<String, String> onPhone = <String, String>{
        '1': planner.entryFor(ada, f).hash,
        '2': 'stale',
        '3': planner.entryFor(person('3', 'Gone'), f).hash,
      };
      final PhoneSyncPlan plan = planner.plan(
          contacts: <VaultContact>[ada, bo], fields: f, onPhone: onPhone);
      expect(plan.upserts.map((PhoneSyncEntry e) => e.id), <String>['2']);
      expect(plan.deletes, <String>['3']);

      // Changing which fields are shared rewrites everyone.
      final PhoneSyncPlan more = planner.plan(
          contacts: <VaultContact>[ada],
          fields: f.copyWith(emails: true),
          onPhone: <String, String>{'1': onPhone['1']!});
      expect(more.upserts.single.fields['emails'], <String>['1@example.com']);
    });

    test('settings survive a round trip, unknown keys default', () {
      final PhoneSyncFields f = PhoneSyncFields.fromJson(
          const PhoneSyncFields(notes: true, photos: false).toJson());
      expect(f.notes, isTrue);
      expect(f.photos, isFalse);
      expect(PhoneSyncFields.fromJson(const <String, Object?>{}).phones, isTrue);
    });

    test('birthdays in the form Android expects', () {
      final VaultContact c = VaultContact.fromJson(<String, dynamic>{
        'id': '1',
        'displayName': 'Ada',
        'birthdays': <String>['1815-12-10', '--12-09', 'nonsense'],
      });
      expect(
          planner
              .entryFor(c, const PhoneSyncFields(birthdays: true))
              .fields['birthdays'],
          <String>['1815-12-10', '--12-09']);
    });
  });

  test('Uint8List import stays referenced', () => expect(Uint8List(0), isEmpty));
}
