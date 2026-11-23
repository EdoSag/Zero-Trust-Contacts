import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/pick_for_keyboard_page.dart';

VaultContact person(
  String id,
  String name, {
  List<String> phones = const <String>[],
  List<String> emails = const <String>[],
  List<String> addresses = const <String>[],
}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones,
      'emails': emails,
      'addresses': addresses,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

void main() {
  final List<VaultContact> contacts = <VaultContact>[
    person('1', 'Noa Levi',
        phones: <String>['054-123 4567', '03-5551234'],
        emails: <String>['noa@example.com'],
        addresses: <String>['1 Herzl St, Tel Aviv']),
    person('2', 'Adam Cohen', phones: <String>['+44 7700 900123']),
  ];

  test('a pick request from the keyboard is understood', () {
    expect(
      IncomingRequest.fromMap(<Object?, Object?>{'kind': 'pick'}),
      isA<IncomingTextPick>(),
    );
  });

  test('values: name, phones, emails, addresses, no blanks or repeats', () {
    final List<PickValue> values = pickValuesOf(person('9', ' Dana ',
        phones: <String>['050-1', '050-1', ' '], emails: <String>['d@x.io']));
    expect(values.map((PickValue v) => '${v.field}:${v.text}'),
        <String>['name:Dana', 'phone:050-1', 'email:d@x.io']);
  });

  test('search by name, number in any spacing, or email; A to Z', () {
    expect(pickMatches(contacts, '').map((VaultContact c) => c.id),
        <String>['2', '1']);
    expect(pickMatches(contacts, 'levi').single.id, '1');
    expect(pickMatches(contacts, '0541234').single.id, '1');
    expect(pickMatches(contacts, 'EXAMPLE.com').single.id, '1');
    expect(pickMatches(contacts, 'zzz'), isEmpty);
  });

  testWidgets('tapping a contact and then a value hands that text back',
      (WidgetTester tester) async {
    String? picked = 'unset';
    await tester.pumpWidget(MaterialApp(
      theme: ZtTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppL10n.delegate,
        ...ZtLanguages.delegates,
      ],
      supportedLocales: ZtLanguages.supported,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => PickForKeyboardPage(contacts: contacts),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Insert into ZT Keyboard'), findsOneWidget);
    // Adam is listed above Noa, both on screen below the search field.
    final double search = tester.getBottomLeft(find.byType(TextField)).dy;
    final double adam = tester.getTopLeft(find.text('Adam Cohen')).dy;
    final double noa = tester.getTopLeft(find.text('Noa Levi')).dy;
    expect(adam, greaterThan(search));
    expect(noa, greaterThan(adam));
    expect(noa, lessThan(tester.getSize(find.byType(Scaffold).last).height));

    await tester.tap(find.text('Noa Levi'));
    await tester.pumpAndSettle();
    // The sheet lists everything of Noa, inside the screen.
    final double height = tester.getSize(find.byType(MaterialApp)).height;
    for (final String text in <String>[
      '03-5551234',
      'noa@example.com',
      '1 Herzl St, Tel Aviv',
    ]) {
      final Finder value = find.textContaining(text);
      expect(value, findsOneWidget);
      expect(tester.getBottomLeft(value).dy, lessThan(height));
    }

    await tester.tap(find.textContaining('03-5551234'));
    await tester.pumpAndSettle();
    expect(picked, '03-5551234');
    expect(find.text('Insert into ZT Keyboard'), findsNothing);
  });

  testWidgets('a search with no match says so', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ZtTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppL10n.delegate,
        ...ZtLanguages.delegates,
      ],
      supportedLocales: ZtLanguages.supported,
      home: PickForKeyboardPage(contacts: contacts),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No contacts match.'), findsOneWidget);
    expect(find.text('Adam Cohen'), findsNothing);
  });

  test('a phone-only contact gets every number, email and address', () {
    final VaultContact listed = person('device_42', 'Dana', phones: <String>['050-1111111']);
    final VaultContact full = withPhoneDetails(listed, <String, dynamic>{
      'displayName': 'Dana Mizrahi',
      'phones': <String>['050-1111111', '03-7654321'],
      'emails': <String>['dana@example.com'],
      'addresses': <String>['5 Dizengoff, Tel Aviv'],
      'company': 'Acme',
      'types': <String, String>{'phone\n03-7654321': 'work'},
    });
    expect(full.id, 'device_42');
    expect(full.displayName, 'Dana');
    expect(pickValuesOf(full).map((PickValue v) => v.text), <String>[
      'Dana', '050-1111111', '03-7654321', 'dana@example.com',
      '5 Dizengoff, Tel Aviv',
    ]);
    expect(full.typeOf('phone', '03-7654321'), 'work');
    expect(withPhoneDetails(listed, null), same(listed));
    expect(isPhoneOnly(listed), isTrue);
    expect(isPhoneOnly(contacts.first), isFalse);
  });

  testWidgets('tapping a phone-only contact reads its details from the phone',
      (WidgetTester tester) async {
    final List<String> asked = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: ZtTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object?>>[
        AppL10n.delegate,
        ...ZtLanguages.delegates,
      ],
      supportedLocales: ZtLanguages.supported,
      home: PickForKeyboardPage(
        contacts: <VaultContact>[
          ...contacts,
          person('device_42', 'Dana', phones: <String>['050-1111111']),
        ],
        loadPhoneDetails: (String id) async {
          asked.add(id);
          return <String, dynamic>{
            'phones': <String>['050-1111111'],
            'emails': <String>['dana@example.com'],
            'addresses': <String>['5 Dizengoff, Tel Aviv'],
          };
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Noa Levi'));
    await tester.pumpAndSettle();
    expect(asked, isEmpty); // Vault contacts already have everything.
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dana'));
    await tester.pumpAndSettle();
    expect(asked, <String>['42']);
    expect(find.textContaining('dana@example.com'), findsOneWidget);
    expect(find.textContaining('5 Dizengoff, Tel Aviv'), findsOneWidget);
  });
}
