import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/import/contact_file_text.dart';
import 'package:zerotrust_contacts/import/csv_contacts.dart';
import 'package:zerotrust_contacts/import/sim_contacts.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// C19: import from iCloud, Outlook or CSV files, and SIM contacts.
void main() {
  VaultContact only(CsvContactsImport read) {
    expect(read.contacts, hasLength(1));
    return read.contacts.single;
  }

  group('Google CSV', () {
    test('reads names, typed values, multi-values, labels and addresses', () {
      const String csv =
          'First Name,Middle Name,Last Name,Nickname,Organization Name,'
          'Organization Title,Birthday,Notes,Labels,'
          'E-mail 1 - Label,E-mail 1 - Value,Phone 1 - Label,Phone 1 - Value,'
          'Phone 2 - Label,Phone 2 - Value,Address 1 - Label,'
          'Address 1 - Formatted,Address 1 - Street,Address 1 - City,'
          'Website 1 - Label,Website 1 - Value\n'
          'Ada,Augusta,Lovelace,Ada L,Engines Ltd,Analyst,1815-12-10,'
          '"Line one\nline two","* myContacts ::: * starred ::: Friends",'
          '* Work,ada@work.example,Mobile,+44 7700 900101 ::: +44 7700 900102,'
          'Home,020 7946 0000,Home,"12 St James Sq\nLondon",12 St James Sq,'
          'London,,https://ada.example\n';
      final CsvContactsImport read = const CsvContactsParser().parse(csv);
      expect(read.format, CsvContactFormat.google);
      final VaultContact c = only(read);
      expect(c.firstName, 'Ada Augusta');
      expect(c.lastName, 'Lovelace');
      expect(c.company, 'Analyst, Engines Ltd');
      expect(c.birthdays, <String>['1815-12-10']);
      expect(c.notes, 'Line one\nline two');
      expect(c.labels, <String>['Friends']);
      expect(c.isFavorite, isTrue);
      expect(c.emails, <String>['ada@work.example']);
      expect(c.typeOf('email', 'ada@work.example'), 'work');
      expect(c.phones, <String>[
        '+44 7700 900101',
        '+44 7700 900102',
        '020 7946 0000',
      ]);
      expect(c.typeOf('phone', '+44 7700 900102'), 'mobile');
      expect(c.typeOf('phone', '020 7946 0000'), 'home');
      // The formatted address and its parts are the same address once.
      expect(c.addresses, <String>['12 St James Sq, London']);
      expect(c.typeOf('address', '12 St James Sq, London'), 'home');
      expect(
        c.other,
        containsAll(<String>['Nickname: Ada L', 'https://ada.example']),
      );
    });
  });

  group('Outlook CSV', () {
    const String header =
        'Title,First Name,Middle Name,Last Name,Suffix,Company,Department,'
        'Job Title,Business Street,Business City,Business State,'
        'Business Postal Code,Business Country/Region,Home Street,Home City,'
        'Business Fax,Business Phone,Home Phone,Mobile Phone,Pager,'
        "Assistant's Phone,Birthday,Categories,E-mail Address,E-mail Type,"
        'E-mail Display Name,E-mail 2 Address,Notes,Web Page';

    test('reads Outlook for Windows columns, skipping faxes and pagers', () {
      final String csv =
          '$header\n'
          'Mr.,Grace,,Hopper,,Navy,Research,Rear Admiral,1 Pentagon,'
          'Arlington,VA,22202,USA,,,555-0100,555-0101,555-0102,555-0103,'
          '555-0104,555-0105,12/9/1906,VIP;Work,grace@navy.example,SMTP,'
          'Grace Hopper (grace@navy.example),/o=ExchangeLabs/ou=x/cn=grace,'
          'Compiler pioneer,navy.example\n';
      final CsvContactsImport read = const CsvContactsParser().parse(csv);
      expect(read.format, CsvContactFormat.outlook);
      final VaultContact c = only(read);
      expect(c.displayName, 'Grace Hopper');
      expect(c.company, 'Rear Admiral, Navy - Research');
      expect(c.phones, <String>['555-0101', '555-0102', '555-0103']);
      expect(c.typeOf('phone', '555-0101'), 'work');
      expect(c.typeOf('phone', '555-0102'), 'home');
      expect(c.typeOf('phone', '555-0103'), 'mobile');
      // The Exchange-internal address isn't an email address.
      expect(c.emails, <String>['grace@navy.example']);
      expect(c.addresses, <String>['1 Pentagon, Arlington VA 22202, USA']);
      expect(
        c.typeOf('address', '1 Pentagon, Arlington VA 22202, USA'),
        'work',
      );
      expect(c.birthdays, <String>['1906-12-09']);
      expect(c.labels, <String>['VIP', 'Work']);
      expect(c.notes, 'Compiler pioneer');
      expect(c.other, contains('navy.example'));
    });

    test('"0/0/00" means no birthday; a day above 12 sets the date order', () {
      final String csv =
          '$header\n'
          ',A,,One,,,,,,,,,,,,,,,050-1,,,0/0/00,,,,,,,\n'
          ',B,,Two,,,,,,,,,,,,,,,050-2,,,25/12/1990,,,,,,,\n'
          ',C,,Three,,,,,,,,,,,,,,,050-3,,,3/4/1985,,,,,,,\n';
      final List<VaultContact> contacts = const CsvContactsParser()
          .parse(csv)
          .contacts;
      expect(contacts.map((VaultContact c) => c.birthdays), <List<String>>[
        <String>[],
        <String>['1990-12-25'],
        // Day first, like the rest of this file.
        <String>['1985-04-03'],
      ]);
    });

    test('Hebrew Outlook, saved as Windows-1255, is read', () {
      const String text =
          'שם פרטי,שם משפחה,טלפון נייד,טלפון בעבודה,'
          'כתובת דואר אלקטרוני,רחוב בבית,עיר בבית,חברה\n'
          'דנה,לוי,054-1234567,03-7654321,dana@example.co.il,הרצל 1,'
          'תל אביב,אקמי\n';
      // Encode to Windows-1255 the way Excel/Outlook on Windows would.
      final List<int> bytes = <int>[
        for (final int unit in text.codeUnits)
          unit >= 0x05D0 && unit <= 0x05EA ? 0xE0 + unit - 0x05D0 : unit,
      ];
      expect(() => utf8.decode(bytes), throwsFormatException);
      final String decoded = decodeContactFile(bytes);
      expect(decoded, text);
      final CsvContactsImport read = const CsvContactsParser().parse(decoded);
      expect(read.format, CsvContactFormat.outlook);
      final VaultContact c = only(read);
      expect(c.displayName, 'דנה לוי');
      expect(c.typeOf('phone', '054-1234567'), 'mobile');
      expect(c.typeOf('phone', '03-7654321'), 'work');
      expect(c.emails, <String>['dana@example.co.il']);
      expect(c.addresses, <String>['הרצל 1, תל אביב']);
      expect(c.typeOf('address', 'הרצל 1, תל אביב'), 'home');
      expect(c.company, 'אקמי');
    });
  });

  test('two Hebrew addresses stay two addresses', () {
    const String csv =
        'שם,רחוב בבית,עיר בבית,רחוב בעבודה,עיר בעבודה\n'
        'דנה,הרצל 1,תל אביב,הנביאים 1,חיפה\n';
    final VaultContact c = only(const CsvContactsParser().parse(csv));
    expect(c.addresses, <String>['הרצל 1, תל אביב', 'הנביאים 1, חיפה']);
    expect(c.typeOf('address', 'הנביאים 1, חיפה'), 'work');
  });

  group('plain spreadsheets', () {
    test('semicolons, a full-name column and UTF-8 with a BOM', () {
      final List<int> bytes = <int>[
        0xEF, 0xBB, 0xBF, //
        ...utf8.encode(
          'Name;Phone;Email;Company\n'
          '"Linus Torvalds";+1 503 555 0100;linus@example.org;"Linux; Inc"\n'
          ';;;\n'
          'Solo;;;\n',
        ),
      ];
      final String text = decodeContactFile(bytes);
      expect(detectContactFileKind(text), ContactFileKind.csv);
      final CsvContactsImport read = const CsvContactsParser().parse(text);
      expect(read.format, CsvContactFormat.generic);
      expect(read.contacts, hasLength(2));
      final VaultContact linus = read.contacts.first;
      expect(linus.firstName, 'Linus');
      expect(linus.lastName, 'Torvalds');
      expect(linus.company, 'Linux; Inc');
      expect(linus.phones, <String>['+1 503 555 0100']);
      expect(read.contacts.last.displayName, 'Solo');
    });

    test('Hebrew headers and UTF-16 with a byte order mark', () {
      const String text = 'שם\tטלפון\tדוא"ל\nנועה בר\t052-1112222\tnoa@x.il\n';
      final List<int> bytes = <int>[0xFF, 0xFE];
      for (final int unit in text.codeUnits) {
        bytes
          ..add(unit & 0xFF)
          ..add(unit >> 8);
      }
      final String decoded = decodeContactFile(bytes);
      expect(decoded, text);
      final VaultContact c = only(const CsvContactsParser().parse(decoded));
      expect(c.firstName, 'נועה');
      expect(c.lastName, 'בר');
      expect(c.phones, <String>['052-1112222']);
      expect(c.emails, <String>['noa@x.il']);
    });

    test('quoted cells keep separators, quotes and line breaks', () {
      expect(parseCsvRows('a,b\n"x, ""y""","1\n2"\n'), <List<String>>[
        <String>['a', 'b'],
        <String>['x, "y"', '1\n2'],
      ]);
      expect(parseCsvRows('sep=;\na;b\n1;2'), <List<String>>[
        <String>['a', 'b'],
        <String>['1', '2'],
      ]);
    });

    test('text that is neither vCard nor CSV is recognised as such', () {
      expect(detectContactFileKind('hello'), ContactFileKind.unknown);
      expect(
        detectContactFileKind('BEGIN:VCARD\nFN:A\nEND:VCARD'),
        ContactFileKind.vCard,
      );
    });
  });

  group('iCloud and Outlook vCards', () {
    test('iCloud: grouped values, unknown birth year, embedded photo', () {
      const String vcf =
          'BEGIN:VCARD\r\n'
          'VERSION:3.0\r\n'
          'PRODID:-//Apple Inc.//iCloud Web Address Book//EN\r\n'
          'N:Bar;Noa;;;\r\n'
          'FN:Noa Bar\r\n'
          'item1.TEL;type=pref:+972 52 111 2222\r\n'
          'item1.X-ABLabel:_\$!<Mobile>!\$_\r\n'
          'TEL;type=CELL;type=VOICE:+972 54 333 4444\r\n'
          'item2.EMAIL;type=INTERNET;type=pref:noa@icloud.com\r\n'
          'BDAY;X-APPLE-OMIT-YEAR=1604:1604-05-14\r\n'
          'PHOTO;ENCODING=b;TYPE=JPEG:/9j/4AAQSkZJRg==\r\n'
          'END:VCARD\r\n';
      final VCardImport read = const VCardParser().parseWithPhotos(vcf);
      final VaultContact c = read.contacts.single;
      expect(c.displayName, 'Noa Bar');
      expect(c.phones, <String>['+972 52 111 2222', '+972 54 333 4444']);
      expect(c.typeOf('phone', '+972 54 333 4444'), 'mobile');
      expect(c.emails, <String>['noa@icloud.com']);
      expect(c.birthdays, <String>['--05-14']);
      expect(read.photos[c.id]?.bytes, isNotNull);
    });

    test('Outlook .vcf in UTF-16 is read', () {
      const String vcf =
          'BEGIN:VCARD\r\nVERSION:2.1\r\n'
          'N;LANGUAGE=en-us:Hopper;Grace\r\nFN:Grace Hopper\r\n'
          'TEL;WORK;VOICE:555-0101\r\n'
          'EMAIL;PREF;INTERNET:grace@navy.example\r\nEND:VCARD\r\n';
      final List<int> bytes = <int>[0xFF, 0xFE];
      for (final int unit in vcf.codeUnits) {
        bytes
          ..add(unit & 0xFF)
          ..add(unit >> 8);
      }
      final String text = decodeContactFile(bytes);
      expect(detectContactFileKind(text), ContactFileKind.vCard);
      final VaultContact c = const VCardParser().parse(text).single;
      expect(c.displayName, 'Grace Hopper');
      expect(c.typeOf('phone', '555-0101'), 'work');
    });
  });

  group('SIM card', () {
    test('entries with the same name become one contact', () {
      final List<VaultContact> contacts = vaultContactsFromSim(
        <Map<String, dynamic>>[
          <String, dynamic>{'name': 'Mom', 'number': '050-1111111'},
          <String, dynamic>{
            'name': 'mom',
            'number': '03-2222222',
            'emails': <String>['mom@x.il', 'junk'],
          },
          <String, dynamic>{'name': 'אבא כהן', 'number': '052-3333333'},
          <String, dynamic>{'name': '', 'number': '*100'},
          <String, dynamic>{'name': '', 'number': ''},
        ],
      );
      expect(contacts, hasLength(3));
      expect(contacts[0].displayName, 'Mom');
      expect(contacts[0].phones, <String>['050-1111111', '03-2222222']);
      expect(contacts[0].emails, <String>['mom@x.il']);
      expect(contacts[1].firstName, 'אבא');
      expect(contacts[1].lastName, 'כהן');
      expect(contacts[2].displayName, '*100');
    });
  });
}
