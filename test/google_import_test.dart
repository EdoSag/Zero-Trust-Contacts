import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Shaped like a real contacts.google.com "vCard (for iOS Contacts)" export.
const String googleExport = '''BEGIN:VCARD\r
VERSION:3.0\r
FN:Ada Lovelace\r
N:Lovelace;Ada;King;;\r
NICKNAME:Countess\r
EMAIL;TYPE=INTERNET;TYPE=HOME:ada@example.com\r
TEL;TYPE=CELL:+44 7700 900123\r
TEL;TYPE=HOME:020 7946 0000\r
ADR;TYPE=HOME:;;12 St James\\'s Square;London;;SW1Y 4JH;United Kingdom\r
ORG:Analytical Engines Ltd\\, London;\r
TITLE:Programmer\r
BDAY:1815-12-10\r
item1.URL:https://example.com/ada\r
item1.X-ABLabel:\r
NOTE:First line\\nSecond line that is long enough to be folded by the expo\r
 rter onto a continuation line\r
CATEGORIES:myContacts,starred,Mathematicians\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:3.0\r
FN:Grace Hopper\r
N:Hopper;Grace;;;\r
TEL;TYPE=CELL:(555) 010-9999\r
BDAY:--12-09\r
CATEGORIES:myContacts\r
END:VCARD\r
BEGIN:VCARD\r
VERSION:3.0\r
END:VCARD\r
''';

void main() {
  group('VCardParser', () {
    test('reads a Google Contacts export', () {
      final List<VaultContact> contacts = const VCardParser().parse(googleExport);
      expect(contacts, hasLength(2), reason: 'empty card is skipped');

      final VaultContact ada = contacts.first;
      expect(ada.displayName, 'Ada Lovelace');
      expect(ada.firstName, 'Ada King');
      expect(ada.lastName, 'Lovelace');
      expect(ada.emails, <String>['ada@example.com']);
      expect(ada.phones, <String>['+44 7700 900123', '020 7946 0000']);
      expect(ada.addresses,
          <String>["12 St James's Square, London, SW1Y 4JH, United Kingdom"]);
      expect(ada.company, 'Programmer, Analytical Engines Ltd, London');
      expect(ada.birthdays, <String>['1815-12-10']);
      expect(ada.labels, <String>['Mathematicians']);
      expect(ada.isFavorite, isTrue);
      expect(ada.other, contains('https://example.com/ada'));
      expect(ada.other, contains('Nickname: Countess'));
      expect(
        ada.notes,
        'First line\nSecond line that is long enough to be folded by the '
        'exporter onto a continuation line',
      );

      final VaultContact grace = contacts[1];
      expect(grace.birthdays, <String>['--12-09']);
      expect(grace.labels, isEmpty);
      expect(grace.isFavorite, isFalse);
      expect(grace.nextBirthday, isNotNull,
          reason: 'year-less birthdays show in upcoming birthdays');
    });

    test('decodes vCard 2.1 quoted-printable', () {
      const String raw = 'BEGIN:VCARD\n'
          'VERSION:2.1\n'
          'N;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:M=C3=BCller;J=C3=BCrgen;;;\n'
          'TEL;CELL:0151 2345678\n'
          'NOTE;ENCODING=QUOTED-PRINTABLE:Line one=\n'
          ' and more\n'
          'END:VCARD\n';
      final VaultContact c = const VCardParser().parse(raw).single;
      expect(c.lastName, 'Müller');
      expect(c.firstName, 'Jürgen');
      expect(c.displayName, 'Jürgen Müller');
      expect(c.phones, <String>['0151 2345678']);
    });

    test('normalizes birthdays', () {
      expect(VCardParser.normalizeBirthday('19850412'), '1985-04-12');
      expect(VCardParser.normalizeBirthday('1985-04-12T00:00:00Z'), '1985-04-12');
      expect(VCardParser.normalizeBirthday('--0412'), '--04-12');
      expect(VCardParser.normalizeBirthday('soon'), isNull);
    });
  });

  group('ContactImportPlanner', () {
    VaultContact contact(
      String name, {
      List<String> phones = const <String>[],
      List<String> emails = const <String>[],
      String notes = '',
      String company = '',
    }) {
      return VaultContact.fromLegacyPayload(<String, dynamic>{
        'displayName': name,
        'phones': phones,
        'emails': emails,
        'notes': notes,
        'company': company,
      });
    }

    test('adds new contacts and merges matches without duplicating', () {
      final VaultContact existing = contact(
        'Ada',
        phones: <String>['07700 900123'],
        notes: 'Met at the Royal Society',
      );
      final List<VaultContact> incoming = <VaultContact>[
        contact('Ada Lovelace',
            phones: <String>['+44 7700 900123'],
            emails: <String>['ada@example.com'],
            company: 'Analytical Engines'),
        contact('Grace Hopper', emails: <String>['grace@example.com']),
      ];

      const ContactImportPlanner planner = ContactImportPlanner();
      final ContactImportPlan plan =
          planner.plan(existing: <VaultContact>[existing], incoming: incoming);

      expect(plan.toAdd.map((VaultContact c) => c.displayName),
          <String>['Grace Hopper']);
      expect(plan.toUpdate, hasLength(1));
      final VaultContact merged = plan.toUpdate.single;
      expect(merged.id, existing.id);
      expect(merged.displayName, 'Ada', reason: 'existing name is kept');
      expect(merged.phones, <String>['07700 900123'],
          reason: 'same number in another format is not added twice');
      expect(merged.emails, <String>['ada@example.com']);
      expect(merged.company, 'Analytical Engines');
      expect(merged.notes, 'Met at the Royal Society');

      final List<VaultContact> result =
          planner.apply(<VaultContact>[existing], plan);
      expect(result, hasLength(2));
    });

    test('re-importing the same source changes nothing', () {
      const ContactImportPlanner planner = ContactImportPlanner();
      final List<VaultContact> first = const VCardParser().parse(googleExport);
      final ContactImportPlan initial =
          planner.plan(existing: <VaultContact>[], incoming: first);
      final List<VaultContact> vault =
          planner.apply(<VaultContact>[], initial);
      expect(vault, hasLength(2));

      final ContactImportPlan again = planner.plan(
        existing: vault,
        incoming: const VCardParser().parse(googleExport),
      );
      expect(again.isEmpty, isTrue);
      expect(again.unchangedCount, 2);
    });

    test('collapses duplicate cards inside one import', () {
      const ContactImportPlanner planner = ContactImportPlanner();
      final ContactImportPlan plan = planner.plan(
        existing: <VaultContact>[],
        incoming: <VaultContact>[
          contact('Sam', emails: <String>['sam@example.com']),
          contact('Sam Smith',
              emails: <String>['SAM@example.com'],
              phones: <String>['555 0100 22']),
        ],
      );
      expect(plan.toAdd, hasLength(1));
      expect(plan.toAdd.single.phones, <String>['555 0100 22']);
      expect(plan.toUpdate, isEmpty);
    });

    test('matches by name only when neither side has phone or email', () {
      const ContactImportPlanner planner = ContactImportPlanner();
      final ContactImportPlan plan = planner.plan(
        existing: <VaultContact>[contact('Pat Lee')],
        incoming: <VaultContact>[
          contact('pat  lee', company: 'Acme'),
          contact('Pat Lee', phones: <String>['555 123 4567']),
        ],
      );
      expect(plan.toUpdate.single.company, 'Acme');
      expect(plan.toAdd, hasLength(1),
          reason: 'a contact with a number is not merged on name alone');
    });
  });

  test('Android account rows become vault contacts', () {
    final List<VaultContact> contacts =
        vaultContactsFromAccountFields(<Map<String, dynamic>>[
      <String, dynamic>{
        'displayName': 'Linus Torvalds',
        'firstName': 'Linus',
        'lastName': 'Torvalds',
        'phones': <String>['+1 503 555 0100', '+1 503 555 0100'],
        'emails': <String>['linus@example.org'],
        'birthdays': <String>['1969-12-28', '--12-28'],
        'labels': <String>['Kernel'],
        'isFavorite': true,
      },
    ]);
    final VaultContact linus = contacts.single;
    expect(linus.phones, <String>['+1 503 555 0100']);
    expect(linus.birthdays, <String>['1969-12-28', '--12-28']);
    expect(linus.labels, <String>['Kernel']);
    expect(linus.isFavorite, isTrue);
    expect(linus.source, 'Saved');
  });
}
