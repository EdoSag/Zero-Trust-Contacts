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
}
