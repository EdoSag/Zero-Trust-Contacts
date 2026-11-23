import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// The sibling apps of the same account whose items Contacts reads for a
/// person's timeline (C-1) and "keep in touch" (C-3). Read only: Contacts
/// never writes another app's data.
enum LinkedApp {
  /// Backed-up calls (`call_history`) and private calls (`private_call`).
  phone('phone'),

  /// Events with the contact as a guest (`contactIds`, `guestEmails`).
  calendar('calendar'),

  /// Tasks linked to the contact (`contactIds`).
  tasks('tasks');

  const LinkedApp(this.appId);

  /// The app's HKDF label and `vault_items.app` value.
  final String appId;
}

/// The other apps' keys for the unlocked account, derived from the account
/// key at unlock (see AppGate) and zeroed when the vault locks.
final linkedKeysProvider =
    NotifierProvider<LinkedKeys, Map<LinkedApp, Uint8List>>(LinkedKeys.new);

class LinkedKeys extends Notifier<Map<LinkedApp, Uint8List>> {
  @override
  Map<LinkedApp, Uint8List> build() {
    ref.listen(vaultControllerProvider, (_, VaultState next) {
      if (next is VaultLocked) clear();
    });
    ref.onDispose(_zero);
    return const <LinkedApp, Uint8List>{};
  }

  /// The keys handed out, kept apart from [state] so they can be zeroed
  /// while the provider is disposed (when [state] can't be read).
  Map<LinkedApp, Uint8List> _held = const <LinkedApp, Uint8List>{};

  /// Derives each linked app's key from [dek]. Doesn't take ownership of
  /// [dek].
  Future<void> deriveFrom(Uint8List dek) async {
    final Map<LinkedApp, Uint8List> keys = <LinkedApp, Uint8List>{
      for (final LinkedApp app in LinkedApp.values)
        app: await KeyHierarchy.appKey(dek, app.appId),
    };
    _zero();
    _held = keys;
    state = keys;
  }

  void clear() {
    _zero();
    state = const <LinkedApp, Uint8List>{};
  }

  void _zero() {
    for (final Uint8List key in _held.values) {
      key.fillRange(0, key.length, 0);
    }
    _held = const <LinkedApp, Uint8List>{};
  }
}

/// Lets the engine pull another app's items but never upload.
class ReadOnlySyncBackend implements SyncBackend {
  ReadOnlySyncBackend(this.inner);
  final SyncBackend inner;

  @override
  Future<List<RemoteItem>> pull(String app, {DateTime? since}) =>
      inner.pull(app, since: since);

  @override
  Future<List<RemoteItem>> fetch(String app, Set<String> itemIds) =>
      inner.fetch(app, itemIds);

  @override
  Future<Set<String>> pushAll(String app, List<RemoteItem> items) async {
    if (items.isNotEmpty) {
      throw StateError('Contacts never writes $app items');
    }
    return <String>{};
  }

  @override
  Future<void> Function() subscribe(
    String app,
    void Function(RemoteItem) onChange,
  ) =>
      inner.subscribe(app, onChange);
}

/// Contacts' own encrypted copy of a sibling app's items, opened with that
/// app's key and kept up to date from the account. Separate from the other
/// app's own file; deleting it loses nothing.
final linkedMirrorProvider =
    FutureProvider.family<LinkedMirror, LinkedApp>((Ref ref, LinkedApp app) async {
  final Uint8List? unlocked =
      ref.watch(linkedKeysProvider.select((Map<LinkedApp, Uint8List> m) => m[app]));
  if (unlocked == null) throw const VaultIsLocked();
  final Uint8List key = Uint8List.fromList(unlocked);
  bool disposed = false;
  ref.onDispose(() {
    disposed = true;
    key.fillRange(0, key.length, 0);
  });
  final String? userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  final String path = await ZtLocalStore.pathFor(
    appId: 'contacts_${app.appId}',
    userId: userId,
  );
  ZtLocalStore store;
  try {
    store = await ZtLocalStore.open(appKey: key, path: path);
  } on LocalStoreUnreadable {
    await ZtLocalStore.moveAside(path);
    store = await ZtLocalStore.open(appKey: key, path: path);
  }
  final String deviceId = await ref.watch(ztDeviceIdProvider.future);
  final ItemSyncEngine engine = await ItemSyncEngine.fromVault(
    appId: app.appId,
    appKey: key,
    deviceId: deviceId,
    store: store,
    backend: ReadOnlySyncBackend(ref.watch(ztSyncBackendProvider)),
  );
  final LinkedMirror mirror = LinkedMirror(store: store, engine: engine);
  if (disposed) {
    await mirror.close();
    throw const VaultIsLocked();
  }
  ref.onDispose(mirror.close);
  mirror.start();
  return mirror;
});

class LinkedMirror {
  LinkedMirror({required this.store, required this.engine});

  final ZtLocalStore store;
  final ItemSyncEngine engine;
  AppLifecycleListener? _lifecycle;
  final StreamController<void> _refreshed = StreamController<void>.broadcast();

  /// Pulls now, then follows live changes, and pulls again on resume.
  void start() {
    unawaited(refresh());
    engine.startLive();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    try {
      await engine.sync();
    } on Object {
      // Offline: what's already on this device still shows.
    }
    if (!_refreshed.isClosed) _refreshed.add(null);
  }

  Stream<List<LocalItem>> watch() async* {
    yield await store.liveItems();
    final StreamController<void> merged = StreamController<void>();
    final StreamSubscription<Object?> a =
        store.changes.listen((_) => merged.add(null));
    final StreamSubscription<void> b =
        _refreshed.stream.listen((_) => merged.add(null));
    try {
      await for (final void _ in merged.stream) {
        yield await store.liveItems();
      }
    } finally {
      await a.cancel();
      await b.cancel();
      await merged.close();
    }
  }

  Future<void> close() async {
    _lifecycle?.dispose();
    await _refreshed.close();
    await engine.close();
    await store.close();
  }
}

/// The live items of a sibling app, as JSON (tombstones left out). Empty
/// while that app has nothing for this account.
final linkedItemsProvider = StreamProvider.family<List<Map<String, Object?>>, LinkedApp>(
    (Ref ref, LinkedApp app) async* {
  final LinkedMirror mirror = await ref.watch(linkedMirrorProvider(app).future);
  await for (final List<LocalItem> items in mirror.watch()) {
    yield <Map<String, Object?>>[
      for (final LocalItem i in items)
        if (i.json case final Map<String, Object?> json)
          <String, Object?>{...json, '_id': i.itemId},
    ];
  }
});
