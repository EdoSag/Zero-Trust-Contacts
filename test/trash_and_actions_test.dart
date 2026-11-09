import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/import/vcard_writer.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_actions.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

import 'support/contacts_overrides.dart';
import 'support/fake_sync_backend.dart';

VaultContact person(String id, String name, {List<String>? phones}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones ?? <String>['+44 7700 900$id'],
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('trash', () {
    late ProviderContainer container;
    late VaultRepository repo;
    late LocalItemStore store;

    setUp(() async {
      container = ProviderContainer(
        retry: (int _, Object __) => null,
        overrides: contactsTestOverrides(
            server: FakeSyncBackend(), deviceId: 'phone'),
      );
      // Keep everything alive, as the app's widgets do.
      container.listen(vaultControllerProvider, (_, __) {});
      container.listen(ztSyncControllerProvider, (_, __) {});
      await container
          .read(vaultControllerProvider.notifier)
          .unlock(Uint8List.fromList(List<int>.filled(32, 3)));
      store = await container.read(ztLocalStoreProvider.future);
      await container.read(ztSyncEngineProvider.future);
      await Future<void>.delayed(Duration.zero);
      // No signed-in user here, so no photos: built directly.
      repo = VaultRepository(
        store: store,
        sync: container.read(ztSyncControllerProvider.notifier),
        localFile: InMemoryLocalVaultFile(),
      );
    });

    tearDown(() => container.dispose());

    test('delete moves to the trash; restore brings it back', () async {
      await repo.upsertSavedContact(person('1', 'Ada'));
      await repo.upsertSavedContact(person('2', 'Grace'));

      expect(await repo.deleteSavedContact('1'), isTrue);
      expect((await repo.loadSavedContacts()).map((VaultContact c) => c.id),
          <String>['2']);
      final List<TrashedContact> trash = await repo.loadTrash();
      expect(trash.single.contact.displayName, 'Ada');
      expect(trash.single.daysLeft(DateTime.now().toUtc()), 30);

      // Same item, new kind: old app versions just don't list it.
      final LocalItem item = (await store.get('1'))!;
      expect(item.deleted, isFalse);
      expect(item.json!['kind'], 'contact_trash');

      await repo.restoreFromTrash('1');
      expect(await repo.loadTrash(), isEmpty);
      final VaultContact back = (await repo.findSavedContactById('1'))!;
      expect(back.displayName, 'Ada');
      expect((await store.get('1'))!.json!.containsKey('deletedAt'), isFalse);
    });

    test('expired contacts are purged, recent ones kept', () async {
      await repo.upsertSavedContact(person('1', 'Ada'));
      await repo.upsertSavedContact(person('2', 'Grace'));
      await repo.deleteSavedContact('1');
      await repo.deleteSavedContact('2');

      final DateTime now = DateTime.now().toUtc();
      expect(await repo.purgeExpiredTrash(now: now), 0);
      expect(
          await repo.purgeExpiredTrash(
              now: now.add(const Duration(days: 31))),
          2);
      expect(await repo.loadTrash(), isEmpty);
      expect((await store.get('1'))!.deleted, isTrue);
    });

    test('undo changes goes back to a restore point version', () async {
      await repo.upsertSavedContact(person('1', 'Ada'));
      await repo.createSnapshot(reason: 'test');
      final VaultContact current = (await repo.findSavedContactById('1'))!;
      await repo.upsertSavedContact(
          current.applyEdits(displayName: 'Ada L', notes: 'oops'));

      final List<ContactVersion> history = await repo.contactHistory('1');
      expect(history.map((ContactVersion v) => v.contact.displayName),
          contains('Ada'));
      expect(
          history.where(
              (ContactVersion v) => v.contact.displayName == 'Ada L'),
          isEmpty,
          reason: 'the current version is not offered');

      final VaultContact restored = await repo.restoreVersion(history
          .firstWhere((ContactVersion v) => v.contact.displayName == 'Ada')
          .contact);
      expect(restored.displayName, 'Ada');
      expect((await repo.findSavedContactById('1'))!.notes, '');
      // Wins any merge against the edit it undoes.
      expect(restored.fieldUpdatedAt['notes']!.isAfter(current.updatedAt),
          isTrue);
    });
  });

  group('quick actions', () {
    test('phone links', () {
      expect(ContactActions.call('+44 (0) 7700-900123').toString(),
          'tel:+4407700900123');
      expect(ContactActions.text('020 7946 0000').toString(),
          'sms:02079460000');
      expect(ContactActions.whatsApp('0044 7700 900123').toString(),
          'https://wa.me/447700900123');
      expect(ContactActions.signal('+44 7700 900123').toString(),
          'https://signal.me/#p/+447700900123');
      expect(ContactActions.signal('07700 900123'), isNull,
          reason: 'Signal needs an international number');
      expect(ContactActions.call('ext.'), isNull);
    });

    test('email and directions', () {
      expect(ContactActions.email(' ada@example.com ').toString(),
          'mailto:ada@example.com');
      expect(ContactActions.email('nope'), isNull);
      expect(
          ContactActions.directions('12 St James Sq, London', isIOS: false)
              .toString(),
          'geo:0,0?q=12+St+James+Sq%2C+London');
      expect(
          ContactActions.directions('12 St James Sq', isIOS: true)!.host,
          'maps.apple.com');
    });
  });

  group('vCard writer', () {
    test('round-trips through the parser', () {
      final VaultContact ada = VaultContact.fromJson(<String, dynamic>{
        'id': 'c1',
        'firstName': 'Ada',
        'lastName': 'Lovelace',
        'company': 'Engines, Ltd',
        'phones': <String>['+44 7700 900123'],
        'emails': <String>['ada@example.com'],
        'addresses': <String>['12 St James Square, London'],
        'labels': <String>['Maths'],
        'birthdays': <String>['1815-12-10'],
        'notes': 'Line one\nLine two; with a semicolon',
        'other': <String>['Nickname: Countess', 'https://example.com'],
      });
      final String card = const VCardWriter().write(ada,
          photo: Uint8List.fromList(List<int>.generate(300, (int i) => i % 256)));
      expect(card.split('\r\n').every((String l) => l.length <= 75), isTrue);

      final VaultContact back = const VCardParser().parse(card).single;
      expect(back.displayName, 'Ada Lovelace');
      expect(back.company, 'Engines, Ltd');
      expect(back.phones, ada.phones);
      expect(back.emails, ada.emails);
      expect(back.addresses, ada.addresses);
      expect(back.labels, ada.labels);
      expect(back.birthdays, ada.birthdays);
      expect(back.notes, ada.notes);
      expect(back.other, containsAll(ada.other));
    });

    test('QR version leaves out notes', () {
      final VaultContact c = person('1', 'Ada').applyEdits(notes: 'secret');
      expect(const VCardWriter().write(c, includeNotes: false),
          isNot(contains('secret')));
      expect(VCardWriter.fileNameFor(c), 'Ada.vcf');
    });
  });
}
