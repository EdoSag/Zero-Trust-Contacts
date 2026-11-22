import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Shared address books (C11): an address book shared with other
/// Zero-Trust users is one shared space of the app `contacts` (core Z24).
/// Inside it, end-to-end encrypted with the space's key that only the
/// members' phones hold:
/// - item [bookItemId] (kind `address_book`, owners only): its name;
/// - one item per contact (kind `contact`, the same JSON as the account's
///   own contacts), which every member adds, edits and deletes.
///
/// The server sees member ids and encrypted blobs, never names or numbers.
/// Shared contacts stay out of the account's own address book, so nothing
/// changes for the account's own contacts or for older app versions.
const String bookItemId = 'book';

/// Only owners (space admins) rename the address book.
const SpacePolicy contactsSpacePolicy =
    SpacePolicy(adminOnlyKinds: <String>{'address_book'});

/// One shared address book as this account sees it.
@immutable
class SharedBook {
  const SharedBook({
    required this.spaceId,
    required this.name,
    this.isAdmin = false,
    this.members = const <SpaceMember>[],
    this.contacts = const <VaultContact>[],
    this.waiting = false,
    this.joinCode,
  });

  final String spaceId;
  final String name;
  final bool isAdmin;
  final List<SpaceMember> members;

  /// By name.
  final List<VaultContact> contacts;

  /// Joined, but an owner hasn't let this account in yet.
  final bool waiting;

  /// While waiting: the code to compare with the owner.
  final String? joinCode;
}

@immutable
class SharedBooksState {
  const SharedBooksState({
    this.books = const <SharedBook>[],
    this.available = false,
    this.ready = false,
  });

  final List<SharedBook> books;

  /// Sharing can be used now (vault open, sharing reachable).
  final bool available;

  /// Read at least once since the vault opened.
  final bool ready;

  SharedBook? operator [](String spaceId) {
    for (final SharedBook b in books) {
      if (b.spaceId == spaceId) return b;
    }
    return null;
  }
}

/// What a contact looks like inside a shared book: no photo (it lives in
/// this account's own encrypted photo store), not pinned or blocked (those
/// are each person's own choices).
VaultContact forSharing(VaultContact c) {
  final Map<String, dynamic> json = c.toJson()
    ..remove('photo')
    ..remove('photoPath')
    ..['isPinned'] = false
    ..['isFavorite'] = false
    ..['isBlocked'] = false
    ..remove('blockReason')
    ..remove('lastContactedAt')
    ..['interactionCount'] = 0;
  return VaultContact.fromJson(json);
}

/// Reads every book from this phone's copy of its space, so they show
/// offline too. [ownItems] are the account's own items: a book this account
/// answered an invite to, but isn't let in yet, is only there (its anchor).
Future<List<SharedBook>> readSharedBooks(
  List<SpaceEntry> entries, {
  List<LocalItem> ownItems = const <LocalItem>[],
}) async {
  final List<SharedBook> books = <SharedBook>[];
  final Set<String> listed = <String>{
    for (final SpaceEntry e in entries) e.info.id,
  };
  const String anchor = 'zt.space-anchor/';
  for (final LocalItem item in ownItems) {
    if (item.deleted || !item.itemId.startsWith(anchor)) continue;
    final String spaceId = item.itemId.substring(anchor.length);
    if (listed.contains(spaceId)) continue;
    final Object? code = item.json?['verificationCode'];
    // Only anchors of answered invites carry a code; an owner's own anchor
    // without a listed space is a book that was deleted.
    if (code is! String) continue;
    books.add(SharedBook(
      spaceId: spaceId,
      name: '',
      waiting: true,
      joinCode: code,
    ));
  }
  for (final SpaceEntry entry in entries) {
    final SharedSpace? space = entry.space;
    if (space == null) {
      books.add(SharedBook(
        spaceId: entry.info.id,
        name: '',
        waiting: true,
        joinCode: entry.joinCode,
      ));
      continue;
    }
    if (space.gone) continue;
    String name = '';
    bool hasInfo = false;
    final List<VaultContact> contacts = <VaultContact>[];
    for (final LocalItem item in await space.store.all()) {
      if (item.deleted) continue;
      if (item.itemId == bookItemId) {
        name = '${item.json?['name'] ?? ''}';
        hasInfo = true;
        continue;
      }
      final VaultContact? c = contactsCollection.decode(item);
      if (c != null) contacts.add(c);
    }
    contacts.sort((VaultContact a, VaultContact b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    books.add(SharedBook(
      spaceId: space.id,
      name: name,
      isAdmin: space.isAdmin,
      members: space.members,
      contacts: contacts,
      // A space whose name hasn't arrived yet: the owner's first sync.
      waiting: !hasInfo && !space.isAdmin,
      joinCode: entry.joinCode,
    ));
  }
  books.sort((SharedBook a, SharedBook b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return books;
}

class SharedBooksController extends Notifier<SharedBooksState> {
  SharedBooksState _last = const SharedBooksState();
  int _reads = 0;

  @override
  SharedBooksState build() {
    final SpacesState spaces = ref.watch(ztSpacesProvider);
    final LocalItemStore? own = ref.watch(ztLocalStoreProvider).value;
    final List<StreamSubscription<Set<String>>> watching =
        <StreamSubscription<Set<String>>>[];
    bool disposed = false;
    ref.onDispose(() {
      disposed = true;
      for (final StreamSubscription<Set<String>> s in watching) {
        s.cancel();
      }
    });
    if (!spaces.ready) {
      return _last = SharedBooksState(
        books: _last.books,
        ready: spaces.error != null,
      );
    }
    Future<void> read() async {
      final int run = ++_reads;
      final List<SharedBook> books = await readSharedBooks(
        spaces.entries,
        ownItems: own == null ? const <LocalItem>[] : await own.all(),
      );
      if (disposed || run != _reads) return;
      state = _last =
          SharedBooksState(books: books, available: true, ready: true);
    }

    if (own is ZtLocalStore) {
      // Answering an invite writes an anchor here.
      watching.add(own.changes.listen((Set<String> ids) {
        if (ids.any((String id) => id.startsWith('zt.space-anchor/'))) read();
      }));
    }
    for (final SpaceEntry e in spaces.entries) {
      final LocalItemStore? store = e.space?.store;
      if (store is ZtLocalStore) watching.add(store.changes.listen((_) => read()));
    }
    scheduleMicrotask(read);
    return _last = SharedBooksState(
      books: _last.books,
      available: true,
      ready: _last.ready,
    );
  }

  SpacesController get _spaces {
    if (!state.available) {
      throw StateError("Sharing isn't available right now.");
    }
    return ref.read(ztSpacesProvider.notifier);
  }

  /// A new shared address book named [name], this account its owner, with
  /// copies of [contacts] in it. Returns its space id.
  Future<String> create(
    String name, {
    required String myName,
    List<VaultContact> contacts = const <VaultContact>[],
  }) async {
    final SpacesController spaces = _spaces;
    final SharedSpace space = await spaces.create(myName: myName);
    await spaces.save(space.id, bookItemId, <String, Object?>{
      'kind': 'address_book',
      'name': name.trim(),
    });
    for (final VaultContact c in contacts) {
      await spaces.save(
          space.id, c.id, contactsCollection.encode(forSharing(c)));
    }
    return space.id;
  }

  /// Renames the book (owners only; the server and the other phones refuse
  /// anyone else's name too).
  Future<void> rename(String spaceId, String name) async {
    final SpacesController spaces = _spaces;
    if (!(ref.read(ztSpacesProvider)[spaceId]?.space?.isAdmin ?? false)) {
      throw StateError("Only the address book's owners can rename it.");
    }
    await spaces.save(
      spaceId,
      bookItemId,
      <String, Object?>{'kind': 'address_book', 'name': name.trim()},
    );
  }

  /// Adds or changes [contact] in the book, keeping fields a newer app
  /// version added.
  Future<void> saveContact(String spaceId, VaultContact contact) async {
    final SpacesController spaces = _spaces;
    final SharedSpace? space = ref.read(ztSpacesProvider)[spaceId]?.space;
    final Map<String, Object?>? previous =
        (await space?.store.get(contact.id))?.json;
    final VaultContact shared = forSharing(contact);
    await spaces.save(
      spaceId,
      shared.id,
      contactsCollection.encode(
        shared,
        previous: contactsCollection.owns(previous) ? previous : null,
      ),
    );
  }

  Future<void> deleteContact(String spaceId, String contactId) =>
      _spaces.delete(spaceId, contactId);

  Future<void> leave(String spaceId) => _spaces.leave(spaceId);

  Future<void> deleteForEveryone(String spaceId) =>
      _spaces.deleteSpace(spaceId);
}

final NotifierProvider<SharedBooksController, SharedBooksState>
    sharedBooksProvider =
    NotifierProvider<SharedBooksController, SharedBooksState>(
        SharedBooksController.new);
