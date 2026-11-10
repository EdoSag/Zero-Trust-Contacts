import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/scan/business_card_parser.dart';

void main() {
  const BusinessCardParser parser = BusinessCardParser();

  test('an English card: name, title, company, numbers, address', () {
    final ScannedCard card = parser.parse('''
ACME Solutions Ltd.
Dana Levi
Senior Product Manager

M: +972 54-123-4567
T: 03-555 1234 | F: 03-555 1235
dana.levi@acme-solutions.com
www.acme-solutions.com
12 Rothschild Blvd, Floor 4
Tel Aviv 6688102
''');
    expect(card.firstName, 'Dana');
    expect(card.lastName, 'Levi');
    expect(card.company, 'ACME Solutions Ltd.');
    expect(card.title, 'Senior Product Manager');
    expect(card.phones, <String>['+972 54-123-4567', '03-555 1234']);
    expect(card.phoneKinds, <String, String>{
      '+972 54-123-4567': 'mobile',
      '03-555 1234': 'work',
    });
    expect(card.faxes, <String>['03-555 1235']);
    expect(card.emails, <String>['dana.levi@acme-solutions.com']);
    expect(card.websites, <String>['www.acme-solutions.com']);
    expect(card.addresses.single, startsWith('12 Rothschild Blvd, Floor 4'));

    final VaultContact c = card.toContact();
    expect(c.displayName, 'Dana Levi');
    expect(c.company, 'ACME Solutions Ltd.');
    expect(c.typeOf('phone', '+972541234567'), 'mobile');
    expect(c.other, contains('Title: Senior Product Manager'));
    expect(c.other, contains('Fax: 03-555 1235'));
    expect(c.other, contains('www.acme-solutions.com'));
  });

  test('a Hebrew card', () {
    final ScannedCard card = parser.parse('''
יעל כהן
מנהלת שיווק
אורות טכנולוגיות בע"מ
נייד: 052-7654321
טל: 03-6123456
פקס: 03-6123457
yael@orot.co.il
רחוב הרצל 15, תל אביב
''');
    expect(card.firstName, 'יעל');
    expect(card.lastName, 'כהן');
    expect(card.title, 'מנהלת שיווק');
    expect(card.company, 'אורות טכנולוגיות בע"מ');
    expect(card.phones, <String>['052-7654321', '03-6123456']);
    expect(card.phoneKinds['052-7654321'], 'mobile');
    expect(card.phoneKinds['03-6123456'], 'work');
    expect(card.faxes, <String>['03-6123457']);
    expect(card.emails, <String>['yael@orot.co.il']);
    expect(card.websites, isEmpty);
    expect(card.addresses, <String>['רחוב הרצל 15, תל אביב']);
  });

  test('a mixed card with recognition noise', () {
    final ScannedCard card = parser.parse('''
~~ | .
Northwind
John O'Neil-Smith
john.smith @ northwind.io
(415) 555-0199
northwind.io
''');
    expect(card.firstName, 'John');
    expect(card.lastName, "O'Neil-Smith");
    expect(card.company, 'Northwind');
    expect(card.emails, <String>['john.smith@northwind.io']);
    expect(card.phones, <String>['(415) 555-0199']);
    expect(card.websites, isEmpty, reason: 'same as the email domain');
  });

  test('a company picked from the email when no line says Ltd', () {
    final ScannedCard card = parser.parse('''
Maya Stone
Blue Harbor
maya@blueharbor.com
+1 212 555 0100
''');
    expect(card.firstName, 'Maya');
    expect(card.company, 'Blue Harbor');
  });

  test('a personal mail host is not a company', () {
    final ScannedCard card = parser.parse('Sam Reed\nsam.reed@gmail.com\n');
    expect(card.firstName, 'Sam');
    expect(card.company, '');
  });

  group('two readings of one card (real recognition output)', () {
    test('a Hebrew card takes the email from the English reading', () {
      final ScannedCard card = parser.parse(
        BusinessCardParser.mergeReadings(
          hebrew:
              'יעל כהן\nמנהלת שיווק\nאורות טכנולוגיות בע"מ\n'
              'גייד: 052-7654321\nטל: 03-6123456\n906!\n'
              'רחוב הרצל 15, תל אביב\n',
          english:
              '|הכ לעי\nקוויש תלהנמ\nyt: 052-7654321\n'
              'v7: 03-6123456\nyael@orot.co.il\nSy nn 15, 2yaN 7n\n',
        ),
      );
      expect(card.firstName, 'יעל');
      expect(card.lastName, 'כהן');
      expect(card.company, 'אורות טכנולוגיות בע"מ');
      expect(card.title, 'מנהלת שיווק');
      expect(card.phones, <String>['052-7654321', '03-6123456']);
      expect(card.phoneKinds['052-7654321'], 'mobile');
      expect(card.emails, <String>['yael@orot.co.il']);
      expect(card.addresses, <String>['רחוב הרצל 15, תל אביב']);
    });

    test('a fax stays a fax when the other reading has it unlabelled', () {
      final ScannedCard card = parser.parse(
        BusinessCardParser.mergeReadings(
          hebrew: 'יעל כהן\nטל: 03-6123456\nפקס: 03-6123457\n',
          english: 'v7: 03-6123456\nF: 03 6123457\n',
        ),
      );
      expect(card.phones, <String>['03-6123456']);
      expect(card.faxes, <String>['03-6123457']);
      // Also when the unlabelled copy is met first.
      final ScannedCard other = parser.parse('03-6123457\nFax: 03-6123457\n');
      expect(other.phones, isEmpty);
      expect(other.faxes, <String>['03-6123457']);
    });

    test('an English card ignores the Hebrew reading', () {
      const String english =
          'ACME Solutions Ltd.\nDana Levi\nSenior Product Manager\n'
          '12 Rothschild Blvd, Floor 4\nM: +972 54-123-4567\n'
          'Tel Aviv 6688102\nTJ. 03-555 1234 | F: 03-555 1235\n'
          'dana.levi@acme-solutions.com\nwww.acme-solutions.com\n';
      final String merged = BusinessCardParser.mergeReadings(
        hebrew:
            'ACME Solutions Ltd.\nDana Levi\n'
            'F: 03-555 1235 | 1234 03-555 :ד\n',
        english: english,
      );
      expect(merged, english);
      final ScannedCard card = parser.parse(merged);
      expect(card.firstName, 'Dana');
      expect(card.company, 'ACME Solutions Ltd.');
      expect(card.phones, <String>['+972 54-123-4567', '03-555 1234']);
      expect(card.faxes, <String>['03-555 1235']);
      expect(card.addresses.single, contains('Tel Aviv 6688102'));
    });
  });

  test('nothing readable gives an empty card', () {
    expect(parser.parse('~ ..\n|\n').isEmpty, isTrue);
    expect(parser.parse('').isEmpty, isTrue);
  });
}
