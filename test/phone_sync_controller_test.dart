import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/phone_sync/phone_contacts_bridge.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_controller.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

import 'support/contacts_overrides.dart';
import 'support/fake_sync_backend.dart';

/// The phone's contacts, in memory.
class FakeBridge implements PhoneContactsBridge {
  final Map<String, Map<String, Object?>> written =
      <String, Map<String, Object?>>{};
  bool account = false;
  Completer<void>? holdApply;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<PhoneContactsState> state() async => PhoneContactsState(
      accountExists: account,
      hashes: <String, String>{
        for (final MapEntry<String, Map<String, Object?>> e in written.entries)
          e.key: '${e.value['hash']}',
      });

  @override
  Future<void> apply(
      List<Map<String, Object?>> upserts, List<String> deletes) async {
    await holdApply?.future;
    account = true;
    for (final Map<String, Object?> u in upserts) {
      written['${u['id']}'] = u;
    }
    deletes.forEach(written.remove);
  }

  @override
  Future<void> disable() async {
    account = false;
    written.clear();
  }

  /// What a contacts app changed on the phone.
  final List<PhoneChange> pending = <PhoneChange>[];
  final List<(PhoneChange, String?)> acknowledged = <(PhoneChange, String?)>[];

  @override
  Future<List<PhoneChange>> changes() async => List<PhoneChange>.of(pending);

  @override
  Future<void> acknowledge(PhoneChange change, {String? vaultId}) async {
    pending.remove(change);
    acknowledged.add((change, vaultId));
    if (change.deleted || vaultId == null) {
      written.remove(change.sourceId);
    } else {
      // Rewritten from the vault on the next apply.
      written[vaultId]?['hash'] = '';
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late FakeBridge bridge;
  late VaultRepository repo;

  setUp(() async {
    bridge = FakeBridge();
    container = ProviderContainer(
      retry: (int _, Object __) => null,
      overrides: <Override>[
        ...contactsTestOverrides(server: FakeSyncBackend(), deviceId: 'p'),
        phoneContactsBridgeProvider.overrideWithValue(bridge),
        vaultRepositoryProvider.overrideWith((Ref ref) async => VaultRepository(
              store: await ref.watch(ztLocalStoreProvider.future),
              sync: ref.watch(ztSyncControllerProvider.notifier),
              localFile: InMemoryLocalVaultFile(),
            )),
      ],
    );
    container.listen(vaultControllerProvider, (_, __) {});
    container.listen(ztSyncControllerProvider, (_, __) {});
    container.listen(phoneSyncProvider, (_, __) {});
    await container
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List<int>.filled(32, 5)));
    await container.read(ztSyncEngineProvider.future);
    repo = await container.read(vaultRepositoryProvider.future);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => container.dispose());

  Future<void> addContact(String id, {Map<String, Object?>? photo}) =>
      repo.upsertSavedContact(VaultContact.fromJson(<String, dynamic>{
        'id': id,
        'displayName': 'Person $id',
        'phones': <String>['+4470000000$id'],
        'photo': photo,
      }));

  test('writes contacts, and removal wins over a write in flight', () async {
    await addContact('1');
    final PhoneSyncController sync = container.read(phoneSyncProvider.notifier);
    await sync.enable(const PhoneSyncFields());
    expect(bridge.written.keys, <String>['1']);

    await addContact('2');
    bridge.holdApply = Completer<void>();
    final Future<void> running = sync.run();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final Future<void> removing = sync.disable();
    bridge.holdApply!.complete();
    await Future.wait(<Future<void>>[running, removing]);

    expect(bridge.account, isFalse);
    expect(bridge.written, isEmpty);
  });

  test('a photo that could not be read is retried next time', () async {
    // No attachments here, so the photo can't be read.
    await addContact('1', photo: <String, Object?>{'id': 'p1'});
    final PhoneSyncController sync = container.read(phoneSyncProvider.notifier);
    await sync.enable(const PhoneSyncFields());
    final String first = '${bridge.written['1']!['hash']}';
    expect(first, endsWith(':no-photo'));

    await sync.run();
    expect(bridge.written['1']!['hash'], first,
        reason: 'rewritten (still unreadable), not skipped as up to date');
  });

  test('edits, additions and deletions on the phone reach the vault',
      () async {
    await addContact('1');
    await addContact('2');
    final PhoneSyncController sync = container.read(phoneSyncProvider.notifier);
    await sync.enable(const PhoneSyncFields());
    expect(bridge.written.keys, unorderedEquals(<String>['1', '2']));

    bridge.pending.addAll(<PhoneChange>[
      // Contact 1 got a second number in the phone's contacts app.
      const PhoneChange(
        rawId: 11,
        sourceId: '1',
        deleted: false,
        fields: <String, Object?>{
          'displayName': 'Person 1',
          'phones': <Object?>[
            <Object?, Object?>{'value': '+44700000001', 'type': 'mobile'},
            <Object?, Object?>{'value': '+44999', 'type': 'work'},
          ],
        },
      ),
      // Contact 2 was deleted there.
      const PhoneChange(rawId: 12, sourceId: '2', deleted: true),
      // And a new one was created there.
      const PhoneChange(
        rawId: 13,
        sourceId: null,
        deleted: false,
        fields: <String, Object?>{
          'displayName': 'New Person',
          'phones': <Object?>[
            <Object?, Object?>{'value': '+44123', 'type': 'home'},
          ],
        },
      ),
    ]);
    await sync.run();

    final List<VaultContact> saved = await repo.loadSavedContacts();
    final VaultContact one = saved.singleWhere((VaultContact c) => c.id == '1');
    expect(one.phones, <String>['+44700000001', '+44999']);
    expect(one.typeOf('phone', '+44999'), 'work');
    expect(saved.any((VaultContact c) => c.id == '2'), isFalse);
    expect((await repo.loadTrash()).single.contact.id, '2');
    final VaultContact created =
        saved.singleWhere((VaultContact c) => c.displayName == 'New Person');
    expect(created.typeOf('phone', '+44123'), 'home');

    // Every change was acknowledged, and the phone now holds the vault's
    // version of all three.
    expect(bridge.pending, isEmpty);
    expect(bridge.acknowledged.map(((PhoneChange, String?) a) => a.$2),
        <String?>['1', null, created.id]);
    expect(bridge.written.keys, unorderedEquals(<String>['1', created.id]));
    expect(bridge.written['1']!['phones'], <String>['+44700000001', '+44999']);

    // Nothing left to do: another run pulls nothing and saves nothing.
    final int before = (await repo.loadSavedContacts()).length;
    await sync.run();
    expect((await repo.loadSavedContacts()).length, before);
  });

  test('turning on a hidden detail does not erase it through a pending edit',
      () async {
    await repo.upsertSavedContact(VaultContact.fromJson(<String, dynamic>{
      'id': '1',
      'displayName': 'Person 1',
      'phones': <String>['+44700000001'],
      'emails': <String>['kept@example.com'],
      'notes': 'Kept note',
    }));
    final PhoneSyncController sync = container.read(phoneSyncProvider.notifier);
    await sync.enable(const PhoneSyncFields()); // emails and notes hidden

    // Edited on the phone (which has no email or note), not yet pulled.
    bridge.pending.add(const PhoneChange(
      rawId: 11,
      sourceId: '1',
      deleted: false,
      fields: <String, Object?>{
        'displayName': 'Person 1',
        'phones': <Object?>[
          <Object?, Object?>{'value': '+44700000001', 'type': 'mobile'},
          <Object?, Object?>{'value': '+44555', 'type': 'home'},
        ],
        'emails': <Object?>[],
        'notes': '',
      },
    ));
    await sync.setFields(const PhoneSyncFields(emails: true, notes: true));

    final VaultContact one = (await repo.loadSavedContacts()).single;
    expect(one.phones, <String>['+44700000001', '+44555']);
    expect(one.emails, <String>['kept@example.com']);
    expect(one.notes, 'Kept note');
    expect(bridge.written['1']!['emails'], <String>['kept@example.com']);

    // Once every copy is rewritten, an email removed on the phone counts.
    bridge.pending.add(const PhoneChange(
      rawId: 11,
      sourceId: '1',
      deleted: false,
      fields: <String, Object?>{
        'displayName': 'Person 1',
        'phones': <Object?>[
          <Object?, Object?>{'value': '+44700000001', 'type': 'mobile'},
          <Object?, Object?>{'value': '+44555', 'type': 'home'},
        ],
        'emails': <Object?>[],
        'notes': 'Kept note',
      },
    ));
    await sync.run();
    expect((await repo.loadSavedContacts()).single.emails, isEmpty);
  });
}
