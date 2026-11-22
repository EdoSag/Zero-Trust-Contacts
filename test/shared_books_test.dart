import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/sharing/shared_books.dart';

const String alice = '00000000-0000-4000-8000-00000000000a';
const String bob = '00000000-0000-4000-8000-00000000000b';

Uint8List key(int seed) =>
    Uint8List.fromList(List<int>.generate(32, (int i) => (seed * 7 + i) & 0xff));

VaultContact person(String id, String name,
        {List<String> phones = const <String>[], Map<String, Object?>? photo}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones,
      'isPinned': true,
      'isFavorite': true,
      'interactionCount': 7,
      'lastContactedAt': '2026-11-01T10:00:00Z',
      'photo': ?photo,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

/// The account's notes about spaces, kept in its own vault store, where
/// the app finds books it is waiting to join.
class StorePrivate implements SpacePrivateStore {
  StorePrivate(this.store);
  final ZtLocalStore store;

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final LocalItem? item = await store.get(id);
    return item == null || item.deleted ? null : item.json;
  }

  @override
  Future<void> write(String id, Map<String, Object?> json) => store
      .put(LocalItem(itemId: id, updatedAt: DateTime.now().toUtc(), json: json));

  @override
  Future<void> remove(String id) => store.put(
      LocalItem(itemId: id, updatedAt: DateTime.now().toUtc(), deleted: true));
}

/// One person's phone: their shared spaces and the app's providers.
class Phone {
  Phone(this.server, this.userId, this.seed);
  final InMemorySpaceServer server;
  final String userId;
  final int seed;
  late final ZtLocalStore vault;
  late final SharedSpaces spaces;
  late final ProviderContainer container;
  final Map<String, ZtLocalStore> stores = <String, ZtLocalStore>{};

  Future<Phone> start() async {
    vault = await ZtLocalStore.open(appKey: key(seed));
    spaces = SharedSpaces(
      app: 'contacts',
      myUserId: userId,
      identity: await ZtIdentity.fromDek(key(seed + 100)),
      backend: server.backendFor(userId),
      privateStore: StorePrivate(vault),
      openStore: (String id) async =>
          stores[id] ??= await ZtLocalStore.open(appKey: key(seed + 200)),
      deleteStore: (String id) async => stores.remove(id)?.close(),
      deviceId: 'phone-$userId',
      policy: contactsSpacePolicy,
    );
    container = ProviderContainer(overrides: [
      ztSharedSpacesProvider.overrideWith((Ref ref) async => spaces),
      ztLocalStoreProvider.overrideWith((Ref ref) async => vault),
    ]);
    container.listen(sharedBooksProvider, (_, _) {});
    await settle();
    return this;
  }

  SharedBooksController get books => container.read(sharedBooksProvider.notifier);
  SharedBooksState get state => container.read(sharedBooksProvider);

  /// Pulls what the others wrote, as the app does every few minutes.
  Future<void> sync() async {
    await container.read(ztSpacesProvider.notifier).refresh();
    await settle();
    await container.read(ztSpacesProvider.notifier).syncAll();
    await settle();
  }

  Future<void> dispose() async {
    container.dispose();
    await spaces.close();
  }
}

Future<void> settle() async {
  for (int i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a shared contact keeps no photo or personal marks', () {
    final VaultContact shared = forSharing(person('1', 'Dana',
        photo: <String, Object?>{'id': 'p1', 'key': 'secret'}));
    expect(shared.hasPhoto, isFalse);
    expect(shared.isPinned, isFalse);
    expect(shared.isFavorite, isFalse);
    expect(shared.interactionCount, 0);
    expect(shared.lastContactedAt, isNull);
    expect(shared.displayName, 'Dana');
  });

  group('Two people share an address book', () {
    late InMemorySpaceServer server;
    late Phone a, b;

    setUp(() async {
      server = InMemorySpaceServer();
      a = await Phone(server, alice, 1).start();
      b = await Phone(server, bob, 2).start();
    });

    tearDown(() async {
      await a.dispose();
      await b.dispose();
    });

    Future<String> shareWithBob() async {
      final String spaceId = await a.books.create(
        'Family',
        myName: 'Alice',
        contacts: <VaultContact>[
          person('sitter', 'Noa the babysitter', phones: <String>['054-1234567']),
        ],
      );
      await settle();
      final SpaceInviteLink link = await a.spaces.invite(spaceId);
      final JoinStarted started = await b.spaces
          .answer(SpaceInviteLink.parse(link.toString()), myName: 'Bob');
      await b.sync();
      final SharedBook waiting = b.state.books.single;
      expect(waiting.waiting, isTrue, reason: 'Bob waits for Alice');
      expect(waiting.joinCode, started.verificationCode);
      final List<PendingJoin> pending = await a.spaces.pendingJoins(spaceId);
      expect(pending.single.verificationCode, started.verificationCode);
      await a.container.read(ztSpacesProvider.notifier).confirm(pending.single);
      await a.sync();
      await b.sync();
      return spaceId;
    }

    test('the owner makes a book; the other person sees its name, contacts and people',
        () async {
      final String spaceId = await shareWithBob();
      final SharedBook mine = a.state[spaceId]!;
      expect(mine.name, 'Family');
      expect(mine.isAdmin, isTrue);
      expect(mine.contacts.single.displayName, 'Noa the babysitter');

      final SharedBook theirs = b.state[spaceId]!;
      expect(theirs.waiting, isFalse);
      expect(theirs.name, 'Family');
      expect(theirs.isAdmin, isFalse);
      expect(theirs.members.map((SpaceMember m) => m.name),
          unorderedEquals(<String>['Alice', 'Bob']));
      expect(theirs.contacts.single.phones, <String>['054-1234567']);
      expect(theirs.contacts.single.isPinned, isFalse);
    });

    test('a member adds and edits contacts; the owner sees the changes', () async {
      final String spaceId = await shareWithBob();
      final VaultContact sitter = b.state[spaceId]!.contacts.single;
      await b.books.saveContact(spaceId,
          sitter.applyEdits(phones: <String>['054-1234567', '03-5551234']));
      await b.books.saveContact(
          spaceId, person('plumber', 'Avi the plumber', phones: <String>['050-7654321']));
      await b.sync();
      await a.sync();
      final SharedBook book = a.state[spaceId]!;
      expect(book.contacts.map((VaultContact c) => c.displayName),
          <String>['Avi the plumber', 'Noa the babysitter']);
      expect(book.contacts.last.phones, <String>['054-1234567', '03-5551234']);

      await a.books.deleteContact(spaceId, 'plumber');
      await a.sync();
      await b.sync();
      expect(b.state[spaceId]!.contacts.map((VaultContact c) => c.id),
          <String>['sitter']);
    });

    test('only the owner renames the book', () async {
      final String spaceId = await shareWithBob();
      await expectLater(b.books.rename(spaceId, 'Bob\'s now'), throwsA(anything));
      await a.books.rename(spaceId, 'Family & friends');
      await a.sync();
      await b.sync();
      expect(b.state[spaceId]!.name, 'Family & friends');
    });

    test('leaving removes the book from that phone only', () async {
      final String spaceId = await shareWithBob();
      await b.books.leave(spaceId);
      await b.sync();
      expect(b.state.books, isEmpty);
      await a.sync();
      expect(a.state[spaceId]!.members.map((SpaceMember m) => m.name),
          <String>['Alice']);
    });
  });
}
