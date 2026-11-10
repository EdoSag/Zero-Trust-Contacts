import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/app/contact_sorting.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/mecard.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/import/vcard_writer.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/phone_sync/phone_contacts_bridge.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';

VaultContact contact(Map<String, dynamic> json) => VaultContact.fromJson(
  <String, dynamic>{'id': 'c1', 'displayName': 'Ada Lovelace', ...json},
);

void main() {
  group('typed fields (C13)', () {
    test('kinds are kept per value and dropped with the value', () {
      final VaultContact c = contact(<String, dynamic>{
        'phones': <String>['+44 7700 900123', '020 7946 0000'],
        'emails': <String>['Ada@Example.com'],
      }).applyEdits(valueTypes: <String, String>{
        VaultContact.typeKey('phone', '+44 7700 900123'): 'mobile',
        VaultContact.typeKey('phone', '020 7946 0000'): 'work',
        VaultContact.typeKey('email', 'ada@example.com'): 'home',
      });
      expect(c.typeOf('phone', '+447700900123'), 'mobile');
      expect(c.typeLabel('phone', '020 7946 0000', fallback: 'Phone'), 'Work');
      expect(c.typeLabel('email', 'ADA@example.com', fallback: 'Email'), 'Home');

      // Survives a round trip through storage.
      final VaultContact again = VaultContact.fromJson(c.toJson());
      expect(again.valueTypes, c.valueTypes);

      // Removing a number removes its kind; '' clears one.
      final VaultContact fewer = c.applyEdits(
        phones: <String>['+44 7700 900123'],
        valueTypes: <String, String>{
          VaultContact.typeKey('email', 'ada@example.com'): '',
        },
      );
      expect(fewer.valueTypes, <String, String>{
        VaultContact.typeKey('phone', '+44 7700 900123'): 'mobile',
      });
    });

    test('a contact saved before typed fields still reads', () {
      final VaultContact old = contact(<String, dynamic>{
        'phones': <String>['123'],
      });
      expect(old.valueTypes, isEmpty);
      expect(old.typeLabel('phone', '123', fallback: 'Phone'), 'Phone');
    });

    test('two devices setting different kinds both keep theirs', () {
      final VaultContact base = contact(<String, dynamic>{
        'phones': <String>['111', '222'],
      });
      final VaultContact a = base.applyEdits(valueTypes: <String, String>{
        VaultContact.typeKey('phone', '111'): 'home',
      });
      final VaultContact b = base.applyEdits(valueTypes: <String, String>{
        VaultContact.typeKey('phone', '222'): 'work',
      });
      final VaultContact merged = a.mergeWith(b);
      expect(merged.typeOf('phone', '111'), 'home');
      expect(merged.typeOf('phone', '222'), 'work');
    });

    test('vCard export and import carry the kinds', () {
      final VaultContact c = contact(<String, dynamic>{
        'phones': <String>['+15550001', '+15550002'],
        'emails': <String>['w@example.com'],
        'addresses': <String>['1 Main St'],
        'valueTypes': <String, String>{
          'phone:+15550001': 'work',
          'phone:+15550002': 'home',
          'email:w@example.com': 'work',
          'address:1 main st': 'work',
        },
      });
      final String card = const VCardWriter().write(c);
      expect(card, contains('TEL;TYPE=WORK:+15550001'));
      expect(card, contains('EMAIL;TYPE=INTERNET;TYPE=WORK:w@example.com'));
      expect(card, contains('ADR;TYPE=WORK:'));

      final VaultContact back =
          const VCardParser().parseWithPhotos(card).contacts.single;
      expect(back.typeOf('phone', '+15550001'), 'work');
      expect(back.typeOf('phone', '+15550002'), 'home');
      expect(back.typeOf('email', 'w@example.com'), 'work');
      expect(back.typeOf('address', '1 Main St'), 'work');
    });

    test('Google and old-style vCard kinds are read', () {
      const String card = 'BEGIN:VCARD\r\nVERSION:2.1\r\nFN:Bo\r\n'
          'TEL;CELL;VOICE:111\r\n'
          'TEL;TYPE=WORK,VOICE:222\r\n'
          'item1.EMAIL;TYPE=INTERNET;TYPE=HOME:bo@example.com\r\n'
          'END:VCARD\r\n';
      final VaultContact c =
          const VCardParser().parseWithPhotos(card).contacts.single;
      expect(c.typeOf('phone', '111'), 'mobile');
      expect(c.typeOf('phone', '222'), 'work');
      expect(c.typeOf('email', 'bo@example.com'), 'home');
    });

    test('kinds come along from a Google account on the phone', () {
      final VaultContact c = accountImportFromFields(<Map<String, dynamic>>[
        <String, dynamic>{
          'displayName': 'Bo',
          'phones': <String>['111', '222'],
          'emails': <String>['bo@example.com'],
          'types': <String, String>{
            'phone\n111': 'work',
            'email\nbo@example.com': 'home',
          },
        },
      ]).contacts.single;
      expect(c.typeOf('phone', '111'), 'work');
      expect(c.typeOf('phone', '222'), isNull);
      expect(c.typeOf('email', 'bo@example.com'), 'home');
    });

    test('an import adds kinds only for values without one', () {
      final VaultContact mine = contact(<String, dynamic>{
        'phones': <String>['111', '222'],
        'valueTypes': <String, String>{'phone:111': 'home'},
      });
      final VaultContact incoming = contact(<String, dynamic>{
        'id': 'other',
        'phones': <String>['111', '222'],
        'valueTypes': <String, String>{
          'phone:111': 'work',
          'phone:222': 'mobile',
          'phone:999': 'main',
        },
      });
      final VaultContact merged =
          const ContactImportPlanner().merge(mine, incoming);
      expect(merged.valueTypes, <String, String>{
        'phone:111': 'home',
        'phone:222': 'mobile',
      });
    });
  });

  group('duplicate warning (C21)', () {
    final List<VaultContact> vault = <VaultContact>[
      contact(<String, dynamic>{
        'id': 'a',
        'firstName': 'Ada',
        'lastName': 'Lovelace',
        'phones': <String>['+44 7700 900123'],
      }),
      contact(<String, dynamic>{
        'id': 'b',
        'displayName': 'Grace Hopper',
        'firstName': 'Grace',
        'lastName': 'Hopper',
        'emails': <String>['grace@example.com'],
      }),
    ];
    const ContactImportPlanner planner = ContactImportPlanner();

    test('same number in another format, same email, same name', () {
      expect(
        planner.matchesFor(
          contact(<String, dynamic>{
            'id': 'n',
            'displayName': 'A. L.',
            'phones': <String>['07700 900123'],
          }),
          vault,
        ).map((VaultContact c) => c.id),
        <String>['a'],
      );
      expect(
        planner.matchesFor(
          contact(<String, dynamic>{
            'id': 'n',
            'displayName': 'G',
            'emails': <String>['GRACE@example.com'],
          }),
          vault,
        ).map((VaultContact c) => c.id),
        <String>['b'],
      );
      expect(
        planner.matchesFor(
          contact(<String, dynamic>{
            'id': 'n',
            'displayName': 'ada  lovelace',
            'firstName': 'ada',
            'lastName': 'Lovelace',
            'phones': <String>['999999'],
          }),
          vault,
        ).map((VaultContact c) => c.id),
        <String>['a'],
      );
    });

    test('a different person is not flagged', () {
      expect(
        planner.matchesFor(
          contact(<String, dynamic>{
            'id': 'n',
            'displayName': 'Alan Turing',
            'firstName': 'Alan',
            'lastName': 'Turing',
            'phones': <String>['555123'],
          }),
          vault,
        ),
        isEmpty,
      );
    });
  });

  group('list order and sections (C17, C18)', () {
    test('Latin, then Hebrew, then everything else', () {
      final List<String> names = <String>[
        '+972 50 123',
        'דנה',
        'bob',
        'Émile',
        'אבי',
        'Alice',
        '',
        'ךלב',
      ]..sort(ContactSorting.compareNames);
      expect(names, <String>[
        'Alice',
        'bob',
        'Émile',
        'אבי',
        'דנה',
        'ךלב',
        '',
        '+972 50 123',
      ]);
      expect(ContactSorting.sectionOf('Émile'), 'E');
      expect(ContactSorting.sectionOf('bob'), 'B');
      expect(ContactSorting.sectionOf('דנה'), 'ד');
      // A final letter is listed under its regular form.
      expect(ContactSorting.sectionOf('ךלב'), 'כ');
      expect(ContactSorting.sectionOf('"The" Bar'), 'T');
      expect(ContactSorting.sectionOf('123'), '#');
      expect(ContactSorting.sectionOf(''), '#');
    });

    test('sorting by last name', () {
      final VaultContact a = contact(<String, dynamic>{
        'id': 'a',
        'displayName': 'Zed Abel',
        'firstName': 'Zed',
        'lastName': 'Abel',
      });
      final VaultContact b = contact(<String, dynamic>{
        'id': 'b',
        'displayName': 'Amy Young',
        'firstName': 'Amy',
        'lastName': 'Young',
      });
      expect(ContactSorting.compare(a, b), greaterThan(0));
      expect(ContactSorting.compare(a, b, byLastName: true), lessThan(0));
      expect(ContactSorting.sortName(a, byLastName: true), 'Abel Zed');
    });

    test('text direction follows the first letter', () {
      expect(directionOf('דנה Cohen'), TextDirection.rtl);
      expect(directionOf('Dana כהן'), TextDirection.ltr);
      expect(directionOf('(050) 123'), isNull);
      expect(directionOf('مرحبا'), TextDirection.rtl);
    });
  });

  group('QR codes and other apps (C14, C12)', () {
    test('a MECARD becomes a contact', () {
      final String? card = vCardFromQr(
        r'MECARD:N:Lovelace,Ada;TEL:+447700900123;EMAIL:ada@example.com;'
        r'NOTE:Likes\; maths;;',
      );
      final VaultContact c =
          const VCardParser().parseWithPhotos(card!).contacts.single;
      expect(c.firstName, 'Ada');
      expect(c.lastName, 'Lovelace');
      expect(c.phones, <String>['+447700900123']);
      expect(c.emails, <String>['ada@example.com']);
      expect(c.notes, 'Likes; maths');
    });

    test('a vCard passes through and anything else is refused', () {
      expect(vCardFromQr('BEGIN:VCARD\nFN:A\nEND:VCARD'), contains('FN:A'));
      expect(vCardFromQr('https://example.com'), isNull);
      expect(vCardFromQr('MECARD:;;'), isNull);
    });

    test('"add to contacts" from another app fills in the editor', () {
      final IncomingRequest? request = IncomingRequest.fromMap(
        <Object?, Object?>{
          'kind': 'insert',
          'allowExisting': true,
          'displayName': 'Ada King Lovelace',
          'firstName': '',
          'lastName': '',
          'company': 'Analytical Engines',
          'phones': <Object?>[
            <Object?, Object?>{'value': '+447700900123', 'type': 'mobile'},
            <Object?, Object?>{'value': '02079460000', 'type': 'work'},
          ],
          'emails': <Object?>[
            <Object?, Object?>{'value': 'ada@example.com', 'type': ''},
          ],
          'addresses': <Object?>[],
          'other': <Object?>['https://example.com'],
          'birthdays': <Object?>['1815-12-10'],
        },
      );
      final IncomingNewContact incoming = request! as IncomingNewContact;
      final VaultContact c = incoming.contact;
      expect(incoming.allowExisting, isTrue);
      expect(c.firstName, 'Ada King');
      expect(c.lastName, 'Lovelace');
      expect(c.company, 'Analytical Engines');
      expect(c.phones, <String>['+447700900123', '02079460000']);
      expect(c.typeOf('phone', '02079460000'), 'work');
      expect(c.typeOf('email', 'ada@example.com'), isNull);
      expect(c.other, <String>['https://example.com']);
      expect(c.birthdays, <String>['1815-12-10']);
    });

    test('a shared .vcf file is read as text', () {
      final IncomingRequest? request = IncomingRequest.fromMap(
        <Object?, Object?>{
          'kind': 'vcard',
          'name': 'ada.vcf',
          'bytes': Uint8List.fromList('BEGIN:VCARD\nFN:Ada\nEND:VCARD'.codeUnits),
        },
      );
      final IncomingVCard file = request! as IncomingVCard;
      expect(file.name, 'ada.vcf');
      expect(file.text, contains('FN:Ada'));
      expect(IncomingRequest.fromMap(<Object?, Object?>{'kind': 'x'}), isNull);
    });
  });

  group('changes made in the phone\'s contacts app (C12)', () {
    const PhoneSyncPlanner planner = PhoneSyncPlanner();
    const PhoneSyncFields shown = PhoneSyncFields(); // phones, no emails
    final VaultContact ada = contact(<String, dynamic>{
      'firstName': 'Ada',
      'lastName': 'Lovelace',
      'phones': <String>['111', '222'],
      'emails': <String>['ada@example.com'],
      'notes': 'Private note',
      'valueTypes': <String, String>{'phone:111': 'mobile'},
    });

    Map<String, Object?> asOnPhone(VaultContact c) => <String, Object?>{
      'displayName': c.displayName,
      'firstName': c.firstName,
      'lastName': c.lastName,
      'starred': c.isFavorite,
      'phones': <Object?>[
        for (final String p in c.phones)
          <Object?, Object?>{'value': p, 'type': c.typeOf('phone', p) ?? 'mobile'},
      ],
      'emails': <Object?>[],
      'addresses': <Object?>[],
      'birthdays': <Object?>[],
    };

    test('a new number and a removed one come back; hidden details stay', () {
      final Map<String, Object?> phone = asOnPhone(ada)
        ..['phones'] = <Object?>[
          <Object?, Object?>{'value': '111', 'type': 'work'},
          <Object?, Object?>{'value': '333', 'type': 'home'},
        ];
      final VaultContact merged = planner.mergePhoneEdit(
        ada,
        PhoneChange(rawId: 7, sourceId: ada.id, deleted: false, fields: phone),
        shown,
      );
      expect(merged.phones, <String>['111', '333']);
      expect(merged.typeOf('phone', '111'), 'work');
      expect(merged.typeOf('phone', '333'), 'home');
      // Not shown on the phone, so the phone can't remove them.
      expect(merged.emails, <String>['ada@example.com']);
      expect(merged.notes, 'Private note');
      expect(merged.displayName, 'Ada Lovelace');
    });

    test('an email added on the phone is kept even when emails are hidden', () {
      final Map<String, Object?> phone = asOnPhone(ada)
        ..['emails'] = <Object?>[
          <Object?, Object?>{'value': 'new@example.com', 'type': 'work'},
        ];
      final VaultContact merged = planner.mergePhoneEdit(
        ada,
        PhoneChange(rawId: 7, sourceId: ada.id, deleted: false, fields: phone),
        shown,
      );
      expect(merged.emails, <String>['ada@example.com', 'new@example.com']);
      expect(merged.typeOf('email', 'new@example.com'), 'work');
    });

    test('a rename on the phone renames the vault contact', () {
      final Map<String, Object?> phone = asOnPhone(ada)
        ..['displayName'] = 'Ada King'
        ..['lastName'] = 'King';
      final VaultContact merged = planner.mergePhoneEdit(
        ada,
        PhoneChange(rawId: 7, sourceId: ada.id, deleted: false, fields: phone),
        shown,
      );
      expect(merged.displayName, 'Ada King');
      expect(merged.lastName, 'King');
    });

    test('an untouched copy changes nothing', () {
      final VaultContact merged = planner.mergePhoneEdit(
        ada,
        PhoneChange(
          rawId: 7,
          sourceId: ada.id,
          deleted: false,
          fields: asOnPhone(ada)
            ..['phones'] = <Object?>[
              <Object?, Object?>{'value': '111', 'type': 'mobile'},
              <Object?, Object?>{'value': '222', 'type': ''},
            ],
        ),
        shown,
      );
      expect(identical(merged, ada), isTrue);
    });

    test('a contact created on the phone becomes a vault contact', () {
      final VaultContact created = planner.mergePhoneEdit(
        null,
        const PhoneChange(
          rawId: 9,
          sourceId: null,
          deleted: false,
          fields: <String, Object?>{
            'displayName': 'Grace Hopper',
            'firstName': 'Grace',
            'lastName': 'Hopper',
            'company': 'Navy',
            'starred': true,
            'phones': <Object?>[
              <Object?, Object?>{'value': '555', 'type': 'work'},
            ],
            'birthdays': <Object?>['1906-12-09'],
          },
        ),
        shown,
      );
      expect(created.displayName, 'Grace Hopper');
      expect(created.company, 'Navy');
      expect(created.isFavorite, isTrue);
      expect(created.typeOf('phone', '555'), 'work');
      expect(created.birthdays, <String>['1906-12-09']);
      expect(created.isSavedContact, isTrue);
    });

    test('kinds go to the phone only for contacts that have them', () {
      expect(
        planner.entryFor(ada, shown).fields['phoneTypes'],
        <String>['mobile', ''],
      );
      final VaultContact plain = contact(<String, dynamic>{
        'phones': <String>['111'],
      });
      expect(
        planner.entryFor(plain, shown).fields.containsKey('phoneTypes'),
        isFalse,
      );
    });
  });
}
