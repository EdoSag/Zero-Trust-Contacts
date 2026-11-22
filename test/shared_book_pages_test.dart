import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/sharing/shared_book_pages.dart';
import 'package:zerotrust_contacts/sharing/shared_books.dart';
import 'package:zt_sharing_ui/zt_sharing_ui.dart';

VaultContact person(String id, String name, {List<String> phones = const <String>[]}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

class FakeBooks extends SharedBooksController {
  FakeBooks(this.books);
  final List<SharedBook> books;

  @override
  SharedBooksState build() =>
      SharedBooksState(books: books, available: true, ready: true);
}

Widget app(List<SharedBook> books, Widget home) => ProviderScope(
      overrides: [
        sharedBooksProvider.overrideWith(() => FakeBooks(books)),
        ztPendingJoinsProvider.overrideWith((Ref ref) async => const <PendingJoin>[]),
      ],
      child: MaterialApp(
        theme: ZtTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          AppL10n.delegate,
          ...ZtLanguages.delegates,
        ],
        supportedLocales: ZtLanguages.supported,
        home: home,
      ),
    );

void main() {
  final List<SharedBook> books = <SharedBook>[
    SharedBook(
      spaceId: 's1',
      name: 'Family',
      isAdmin: true,
      contacts: <VaultContact>[
        person('a', 'Avi the plumber', phones: <String>['050-7654321']),
        person('n', 'Noa the babysitter', phones: <String>['054-1234567']),
      ],
    ),
    const SharedBook(spaceId: 's2', name: '', waiting: true, joinCode: '12 34 56'),
  ];

  testWidgets('books list, then a book, then a contact, all on screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(app(books, const SharedBooksPage(myContacts: <VaultContact>[])));
    await tester.pumpAndSettle();
    final double height = tester.getSize(find.byType(Scaffold).first).height;

    final Finder family = find.text('Family');
    final Finder waiting = find.text('Waiting to join');
    expect(family, findsOneWidget);
    expect(find.text('2 contacts · 0 people'), findsOneWidget);
    expect(waiting, findsOneWidget);
    expect(find.text('Tell the owner this code: 12 34 56'), findsOneWidget);
    // Below the app bar, in name order, above the "New" button.
    expect(tester.getTopLeft(family).dy,
        greaterThan(tester.getBottomLeft(find.byType(AppBar)).dy));
    final double fab = tester.getTopLeft(find.byKey(const Key('new_shared_book'))).dy;
    expect(tester.getBottomLeft(waiting).dy, lessThan(fab));
    expect(fab, lessThan(height));

    await tester.tap(family);
    await tester.pumpAndSettle();
    final Finder avi = find.text('Avi the plumber');
    final Finder noa = find.text('Noa the babysitter');
    expect(tester.getTopLeft(noa).dy, greaterThan(tester.getTopLeft(avi).dy));
    expect(tester.getBottomLeft(noa).dy, lessThan(height));
    expect(find.byKey(const Key('shared_book_add')), findsOneWidget);
    expect(find.byKey(const Key('shared_book_people')), findsOneWidget);

    await tester.tap(noa);
    await tester.pumpAndSettle();
    final Finder phone = find.text('054-1234567');
    expect(phone, findsOneWidget);
    expect(find.text('In "Family"'), findsOneWidget);
    expect(tester.getBottomLeft(phone).dy, lessThan(height));
    expect(find.byKey(const Key('shared_contact_edit')), findsOneWidget);
  });

  testWidgets('no books yet says what they are for', (WidgetTester tester) async {
    await tester.pumpWidget(app(const <SharedBook>[], const SharedBooksPage(myContacts: <VaultContact>[])));
    await tester.pumpAndSettle();
    expect(find.textContaining('No shared address books yet'), findsOneWidget);
    expect(find.byKey(const Key('join_shared_book')), findsOneWidget);
  });
}
