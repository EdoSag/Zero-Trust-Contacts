import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/import/ios_address_book.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/pages/google_import_page.dart';
import 'package:zerotrust_contacts/pages/labels_page.dart';
import 'package:zerotrust_contacts/scan/card_scanner.dart';
import 'package:zerotrust_contacts/services/contact_actions.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

import 'support/contacts_overrides.dart';
import 'support/fake_sync_backend.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

VaultContact person(
  String id,
  String name, {
  List<String> labels = const <String>[],
  List<String>? phones,
  List<String> emails = const <String>[],
}) => VaultContact.fromJson(<String, dynamic>{
  'id': id,
  'displayName': name,
  'phones': phones ?? <String>['+44 7700 90010$id'],
  'emails': emails,
  'labels': labels,
  'createdAt': '2026-01-01T00:00:00Z',
  'updatedAt': '2026-01-01T00:00:00Z',
});

class FakeAddressBook extends IosAddressBook {
  FakeAddressBook(this.entries, {this.allowed = true});

  final List<fc.Contact> entries;
  final bool allowed;
  final List<String> photosRead = <String>[];

  @override
  Future<bool> requestPermission() async => allowed;

  @override
  Future<AddressBookImport> read() async => addressBookImportFrom(entries);

  @override
  Future<Uint8List?> photo(String addressBookId) async {
    photosRead.add(addressBookId);
    return null;
  }
}

class FakeCardScanner extends CardScanner {
  FakeCardScanner(this.text);

  final String text;
  final List<String> discarded = <String>[];
  bool? askedForCamera;

  @override
  bool get isSupported => true;

  @override
  Future<String?> takePicture({required bool fromCamera}) async {
    askedForCamera = fromCamera;
    return '/tmp/card.jpg';
  }

  /// Runs while the card is being read, like a lock that happens then.
  void Function()? whileReading;

  @override
  Future<String> readText(String imagePath) async {
    whileReading?.call();
    return text;
  }

  @override
  Future<void> discard(String imagePath) async => discarded.add(imagePath);
}

fc.Contact iphoneContact() => fc.Contact(
  id: 'ab-1',
  displayName: 'Noa Bar',
  isStarred: true,
  name: fc.Name(first: 'Noa', last: 'Bar', nickname: 'Nono'),
  phones: <fc.Phone>[
    fc.Phone('+972 52-111-2222', label: fc.PhoneLabel.iPhone),
    fc.Phone('03-555-0000', label: fc.PhoneLabel.work),
    fc.Phone('09-000-0000', label: fc.PhoneLabel.pager),
  ],
  emails: <fc.Email>[fc.Email('noa@example.com', label: fc.EmailLabel.iCloud)],
  addresses: <fc.Address>[
    fc.Address('1 Herzl St\nTel Aviv', label: fc.AddressLabel.home),
  ],
  organizations: <fc.Organization>[
    fc.Organization(company: 'Orot', title: 'Designer'),
  ],
  websites: <fc.Website>[fc.Website('https://noa.example')],
  events: <fc.Event>[
    fc.Event(year: 1990, month: 3, day: 7, label: fc.EventLabel.birthday),
    fc.Event(year: null, month: 6, day: 12, label: fc.EventLabel.anniversary),
  ],
  notes: <fc.Note>[fc.Note('Met at the conference')],
  groups: <fc.Group>[fc.Group('g1', 'Friends')],
  thumbnail: Uint8List.fromList(<int>[1, 2, 3]),
);

void main() {
  group('email or text a whole label', () {
    test('email goes to everyone once, in Bcc', () {
      expect(
        ContactActions.emailGroup(<String>[
          'a@x.com',
          ' b@y.org ',
          'a@x.com',
          'not an address',
        ]).toString(),
        'mailto:?bcc=a%40x.com,b%40y.org',
      );
      expect(ContactActions.emailGroup(<String>['nope']), isNull);
    });

    test('text uses the form each phone understands', () {
      const List<String> phones = <String>['+44 7700 900123', '054-1234567'];
      expect(
        ContactActions.textGroup(phones, isIOS: false).toString(),
        'sms:%2B447700900123,0541234567',
      );
      expect(
        ContactActions.textGroup(phones, isIOS: true).toString(),
        'sms:/open?addresses=%2B447700900123,0541234567',
      );
      expect(ContactActions.textGroup(<String>[''], isIOS: false), isNull);
    });
  });

  group('iPhone address book (C8)', () {
    test('an entry maps to a vault contact with kinds, groups and dates', () {
      final AddressBookImport read = addressBookImportFrom(<fc.Contact>[
        iphoneContact(),
        fc.Contact(id: 'empty'),
      ]);
      final VaultContact c = read.contacts.single;
      expect(c.displayName, 'Noa Bar');
      expect(c.firstName, 'Noa');
      expect(c.lastName, 'Bar');
      expect(c.company, 'Orot');
      expect(c.isFavorite, isTrue);
      expect(c.phones, hasLength(3));
      expect(c.typeOf('phone', '+972 52-111-2222'), 'mobile');
      expect(c.typeOf('phone', '03-555-0000'), 'work');
      expect(c.typeOf('phone', '09-000-0000'), isNull);
      expect(c.typeOf('email', 'noa@example.com'), 'home');
      expect(c.addresses, <String>['1 Herzl St, Tel Aviv']);
      expect(c.typeOf('address', '1 Herzl St, Tel Aviv'), 'home');
      expect(c.labels, <String>['Friends']);
      expect(c.birthdays, <String>['1990-03-07']);
      expect(c.notes, 'Met at the conference');
      expect(
        c.other,
        containsAll(<String>[
          'Anniversary: --06-12',
          'Title: Designer',
          'Nickname: Nono',
          'https://noa.example',
        ]),
      );
      expect(read.photoIds, <String, String>{c.id: 'ab-1'});
    });
  });

  group('screens', () {
    late ProviderContainer container;
    late VaultRepository repo;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> open(
      WidgetTester tester,
      Widget home, {
      List<VaultContact> contacts = const <VaultContact>[],
      CardScanner? scanner,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      container = ProviderContainer(
        retry: (int _, Object __) => null,
        overrides: [
          ...contactsTestOverrides(
            server: FakeSyncBackend(),
            deviceId: 'phone',
          ),
          if (scanner != null) cardScannerProvider.overrideWithValue(scanner),
        ],
      );
      addTearDown(container.dispose);
      container.listen(vaultControllerProvider, (_, __) {});
      container.listen(ztSyncControllerProvider, (_, __) {});
      container.listen(vaultRepositoryProvider, (_, __) {});
      await tester.runAsync(() async {
        await container
            .read(vaultControllerProvider.notifier)
            .unlock(Uint8List.fromList(List<int>.filled(32, 3)));
        await container.read(ztLocalStoreProvider.future);
        await container.read(ztSyncEngineProvider.future);
        await Future<void>.delayed(Duration.zero);
        repo = await container.read(vaultRepositoryProvider.future);
        for (final VaultContact c in contacts) {
          await repo.upsertSavedContact(c);
        }
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [AppL10n.delegate, ...ZtLanguages.delegates],
            supportedLocales: ZtLanguages.supported,
            home: home,
          ),
        ),
      );
      await settle(tester);
    }

    /// Locking stops the sync and auto-lock timers, as closing the app does.
    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      container.read(vaultControllerProvider.notifier).lock();
      await settle(tester);
    }

    Future<List<VaultContact>> saved(WidgetTester tester) async =>
        (await tester.runAsync(repo.loadSavedContacts))!;

    testWidgets('labels: create, add, rename, take out, delete (C7)', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        const LabelsPage(),
        contacts: <VaultContact>[
          person(
            '1',
            'Ada',
            labels: <String>['Family'],
            emails: <String>['ada@x.com'],
          ),
          person('2', 'Grace', labels: <String>['family']),
          person('3', 'Linus'),
        ],
      );
      // "Family" and "family" are one label.
      expect(find.text('Family'), findsOneWidget);
      expect(find.text('2 contacts'), findsOneWidget);

      // Create a label with one person in it.
      await tester.tap(find.text('New label'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Work');
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await settle(tester);
      await tester.tap(find.text('Linus'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add 1'));
      await settle(tester);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('1 contact'), findsOneWidget);

      // Open Family, add Linus, rename it.
      await tester.tap(find.text('Family'));
      await settle(tester);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
      expect(find.text('Linus'), findsNothing);
      expect(find.text('Email all'), findsOneWidget);
      expect(find.text('Text all'), findsOneWidget);
      // The name sits above its number, not on top of it.
      expect(
        tester.getRect(find.text('Ada')).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('+44 7700 900101')).top),
      );

      await tester.tap(find.byTooltip('Add contacts'));
      await settle(tester);
      await tester.tap(find.text('Linus'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add 1'));
      await settle(tester);
      expect(find.text('Linus'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Rename label'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Relatives');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await settle(tester);
      expect(find.widgetWithText(AppBar, 'Relatives'), findsOneWidget);
      expect(
        (await saved(tester)).map((VaultContact c) => c.labels).toList(),
        containsAll(<Matcher>[
          equals(<String>['Relatives']),
          equals(<String>['Work', 'Relatives']),
        ]),
      );

      // Take Grace out.
      await tester.longPress(find.text('Grace'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from label'));
      await settle(tester);
      expect(find.text('Grace'), findsNothing);
      expect(find.text('Ada'), findsOneWidget);

      // Delete the label: contacts stay.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text('Delete label'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete label'));
      await settle(tester);
      expect(find.text('Relatives'), findsNothing);
      expect(find.text('Work'), findsOneWidget);
      final List<VaultContact> after = await saved(tester);
      expect(after, hasLength(3));
      expect(after.expand((VaultContact c) => c.labels).toSet(), <String>{
        'Work',
      });
      await finish(tester);
    });

    testWidgets('iPhone: preview, then import merges and adds (C8)', (
      WidgetTester tester,
    ) async {
      final FakeAddressBook book = FakeAddressBook(<fc.Contact>[
        iphoneContact(),
        fc.Contact(
          id: 'ab-2',
          displayName: 'Ada',
          phones: <fc.Phone>[fc.Phone('+44 7700 900101')],
          emails: <fc.Email>[fc.Email('ada@new.example')],
        ),
      ]);
      await open(
        tester,
        GoogleImportPage(isIOS: true, addressBook: book),
        contacts: <VaultContact>[person('1', 'Ada')],
      );
      expect(find.text('Import contacts'), findsOneWidget);
      await tester.tap(find.text('Import from this iPhone'));
      await settle(tester);
      expect(find.text('Ready to import'), findsOneWidget);
      await tester.tap(find.text('Import 2 contacts'));
      await settle(tester);

      final List<VaultContact> after = await saved(tester);
      expect(after, hasLength(2));
      final VaultContact ada = after.firstWhere(
        (VaultContact c) => c.displayName == 'Ada',
      );
      expect(ada.id, '1');
      expect(ada.emails, <String>['ada@new.example']);
      expect(after.any((VaultContact c) => c.displayName == 'Noa Bar'), isTrue);
      await finish(tester);
    });

    testWidgets('iPhone: a refused permission says how to allow it', (
      WidgetTester tester,
    ) async {
      await open(
        tester,
        GoogleImportPage(
          isIOS: true,
          addressBook: FakeAddressBook(<fc.Contact>[], allowed: false),
        ),
      );
      await tester.tap(find.text('Import from this iPhone'));
      await settle(tester);
      expect(find.textContaining('is not allowed to read'), findsOneWidget);
      expect(find.text('Ready to import'), findsNothing);
      await finish(tester);
    });

    testWidgets('card scan opens the editor filled in, then saves (C9)', (
      WidgetTester tester,
    ) async {
      final FakeCardScanner scanner = FakeCardScanner(
        'ACME Solutions Ltd.\nDana Levi\nSenior Product Manager\n'
        'M: +972 54-123-4567\ndana.levi@acme-solutions.com\n',
      );
      await open(
        tester,
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => scanBusinessCard(context, ref),
              child: const Text('scan'),
            ),
          ),
        ),
        scanner: scanner,
      );
      await tester.tap(find.text('scan'));
      await settle(tester);
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);

      expect(scanner.askedForCamera, isFalse);
      expect(scanner.discarded, <String>['/tmp/card.jpg']);
      expect(find.byType(CreateContactPage), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Dana'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Levi'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'ACME Solutions Ltd.'),
        findsOneWidget,
      );
      expect(find.text('Reading the card…'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settle(tester);
      final VaultContact dana = (await saved(tester)).single;
      expect(dana.displayName, 'Dana Levi');
      expect(dana.phones, <String>['+972 54-123-4567']);
      expect(dana.typeOf('phone', '+972 54-123-4567'), 'mobile');
      expect(dana.emails, <String>['dana.levi@acme-solutions.com']);
      await finish(tester);
    });

    testWidgets('a vault that locks during the scan opens nothing', (
      WidgetTester tester,
    ) async {
      final FakeCardScanner scanner = FakeCardScanner(
        'Dana Levi\n+972 54-123-4567\n',
      );
      await open(
        tester,
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => scanBusinessCard(context, ref),
              child: const Text('scan'),
            ),
          ),
        ),
        scanner: scanner,
      );
      scanner.whileReading = () =>
          container.read(vaultControllerProvider.notifier).lock();
      await tester.tap(find.text('scan'));
      await settle(tester);
      await tester.tap(find.text('Choose a photo'));
      await settle(tester);

      expect(container.read(vaultControllerProvider), isA<VaultLocked>());
      expect(scanner.discarded, <String>['/tmp/card.jpg']);
      expect(find.byType(CreateContactPage), findsNothing);
      expect(find.text('Reading the card…'), findsNothing);
      expect(find.text('scan'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('card scan with nothing readable says so', (
      WidgetTester tester,
    ) async {
      final FakeCardScanner scanner = FakeCardScanner('~ .\n');
      await open(
        tester,
        Scaffold(
          body: Consumer(
            builder: (BuildContext context, WidgetRef ref, _) => TextButton(
              onPressed: () => scanBusinessCard(context, ref),
              child: const Text('scan'),
            ),
          ),
        ),
        scanner: scanner,
      );
      await tester.tap(find.text('scan'));
      await settle(tester);
      await tester.tap(find.text('Take a photo of the card'));
      await settle(tester);
      expect(scanner.askedForCamera, isTrue);
      expect(find.byType(CreateContactPage), findsNothing);
      expect(find.textContaining('No details could be read'), findsOneWidget);
      await finish(tester);
    });
  });
}
