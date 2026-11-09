import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_crypto.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_importer.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_source.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';

import 'support/contacts_overrides.dart';
import 'support/fake_legacy_source.dart';
import 'support/fake_sync_backend.dart';

const String password = 'correct horse battery';
const String salt = 'AAECAwQFBgcICQoLDA0ODw'; // 16 bytes, base64url

VaultContact contact(String id, String name,
        {DateTime? updated, List<String> phones = const <String>[]}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'firstName': name,
      'phones': phones,
      'updatedAt': (updated ?? DateTime.utc(2026, 6, 1)).toIso8601String(),
      'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    });

/// The pre-core cloud blob for [contacts], encrypted the way old versions
/// did.
Future<String> oldBlob(List<VaultContact> contacts, List<int> key) =>
    LegacyContactsCrypto.encryptBlob(
      jsonEncode(<String, dynamic>{
        'version': 2,
        'contacts': contacts.map((VaultContact c) => c.toJson()).toList(),
      }),
      key,
    );

void main() {
  late Uint8List oldKey;
  late ZtLocalStore store;
  late ItemSyncEngine engine;
  late FakeSyncBackend server;

  setUpAll(() async {
    oldKey = await LegacyContactsCrypto.deriveKey(
        password: password, legacySalt: salt, kdf: testKdf);
  });

  setUp(() async {
    final Uint8List appKey = Uint8List.fromList(List<int>.filled(32, 7));
    server = FakeSyncBackend();
    store = await ZtLocalStore.open(appKey: appKey);
    engine = await ItemSyncEngine.fromVault(
      appId: 'contacts',
      appKey: appKey,
      deviceId: 'phone',
      store: store,
      backend: server,
    );
  });

  tearDown(() async {
    await engine.close();
    await store.close();
  });

  LegacyContactsImporter importer(FakeLegacySource source) =>
      LegacyContactsImporter(
          source: source, engine: engine, ledger: store, kdf: testKdf);

  Future<List<VaultContact>> saved() async =>
      (await contactsCollection.list(store))
        ..sort((VaultContact a, VaultContact b) => a.id.compareTo(b.id));

  test('old key derivation matches the pre-core app', () async {
    // What lib/security_service.dart did before the core.
    final SecretKey key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: testKdf.iterations,
      bits: 256,
    ).deriveKey(
      secretKey:
          SecretKey(utf8.encode('$password:${LegacyContactsCrypto.pepper}')),
      nonce: base64Url.decode('$salt=='),
    );
    expect(oldKey, await key.extractBytes());
  });

  test('an updated phone imports with the key it already has, no password',
      () async {
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: await oldBlob(
          <VaultContact>[contact('c1', 'Ada'), contact('c2', 'Grace')],
          oldKey),
      legacySalt: salt,
      deviceKey: oldKey,
      // An edit never uploaded, and a contact only on this phone.
      localContacts: <VaultContact>[
        contact('c1', 'Ada', phones: <String>['+44 1'])
            .applyEdits(notes: 'met at the lab'),
        contact('c3', 'Hedy'),
      ],
    );

    final int count = await importer(source).run(preCoreAccount: true);

    expect(count, 3);
    final List<VaultContact> contacts = await saved();
    expect(contacts.map((VaultContact c) => c.displayName),
        <String>['Ada', 'Grace', 'Hedy']);
    expect(contacts.first.notes, 'met at the lab');
    expect(source.forgotten, isTrue);
    expect(await store.legacyImportDone(LegacyContactsImporter.sourceId),
        isTrue);
    // Synced as separate encrypted items.
    await engine.sync();
    expect(server.rows.keys, containsAll(<String>['contacts/c1', 'contacts/c3']));
  });

  test('a new phone needs the password once, and refuses a wrong one',
      () async {
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: await oldBlob(<VaultContact>[contact('c1', 'Ada')], oldKey),
      legacySalt: salt,
    );

    await expectLater(
      importer(source).run(preCoreAccount: true),
      throwsA(isA<LegacyPasswordNeeded>()
          .having((e) => e.wrongPassword, 'wrong', isFalse)),
    );
    await expectLater(
      importer(source).run(preCoreAccount: true, password: 'not it at all'),
      throwsA(isA<LegacyPasswordNeeded>()
          .having((e) => e.wrongPassword, 'wrong', isTrue)),
    );
    expect(await saved(), isEmpty);

    expect(
        await importer(source).run(preCoreAccount: true, password: password),
        1);
    expect((await saved()).single.displayName, 'Ada');
  });

  test('another account\'s old database on this phone is left alone',
      () async {
    final Uint8List someoneElse = Uint8List.fromList(List<int>.filled(32, 1));
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: await oldBlob(<VaultContact>[contact('c1', 'Ada')], oldKey),
      legacySalt: salt,
      deviceKey: someoneElse,
      localContacts: <VaultContact>[contact('x9', 'Not mine')],
    );

    // Can't tell whose the database is without the password.
    await expectLater(importer(source).run(preCoreAccount: true),
        throwsA(isA<LegacyPasswordNeeded>()));

    expect(
        await importer(source).run(preCoreAccount: true, password: password),
        1);
    expect((await saved()).map((VaultContact c) => c.id), <String>['c1']);
    expect(source.forgotten, isFalse);
  });

  test('accounts made on the core, or with nothing saved, finish at once',
      () async {
    final FakeLegacySource source = FakeLegacySource(offline: true);
    expect(await importer(source).run(preCoreAccount: false), 0);
    expect(await store.legacyImportDone(LegacyContactsImporter.sourceId),
        isTrue);

    final ZtLocalStore other =
        await ZtLocalStore.open(appKey: Uint8List.fromList(List.filled(32, 2)));
    final LegacyContactsImporter empty = LegacyContactsImporter(
        source: FakeLegacySource(), engine: engine, ledger: other);
    expect(await empty.run(preCoreAccount: true), 0);
    expect(await other.legacyImportDone(LegacyContactsImporter.sourceId),
        isTrue);
    await other.close();
  });

  test('offline: nothing is marked done, so it runs again later', () async {
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: await oldBlob(<VaultContact>[contact('c1', 'Ada')], oldKey),
      deviceKey: oldKey,
      offline: true,
    );
    await expectLater(importer(source).run(preCoreAccount: true),
        throwsA(isA<StateError>()));
    expect(await store.legacyImportDone(LegacyContactsImporter.sourceId),
        isFalse);
    source.offline = false;
    expect(await importer(source).run(preCoreAccount: true), 1);
  });

  test('never overwrites a contact another device already imported and edited',
      () async {
    await engine.save(
        'c1',
        contactsCollection
            .encode(contact('c1', 'Ada').applyEdits(notes: 'edited later')));
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: await oldBlob(
          <VaultContact>[contact('c1', 'Ada'), contact('c2', 'Grace')],
          oldKey),
      deviceKey: oldKey,
    );
    expect(await importer(source).run(preCoreAccount: true), 1);
    expect(
        (await saved()).firstWhere((VaultContact c) => c.id == 'c1').notes,
        'edited later');
  });

  test('the earliest plain-JSON cloud copy imports without a key', () async {
    final FakeLegacySource source = FakeLegacySource(
      cloudBlob: jsonEncode(<String, dynamic>{
        'contacts': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'p1', 'firstName': 'Katherine'},
        ],
      }),
    );
    expect(await importer(source).run(preCoreAccount: true), 1);
    expect((await saved()).single.displayName, 'Katherine');
  });

  test('reads the old sqflite database file', () {
    final Directory dir = Directory.systemTemp.createTempSync('ztc');
    final String path = '${dir.path}/vault_contacts.db';
    final Database db = sqlite3.open(path);
    db.execute('CREATE TABLE contacts (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'payload TEXT NOT NULL)');
    db.execute('INSERT INTO contacts (payload) VALUES (?)',
        <Object?>[contact('c1', 'Ada').toStoragePayload()]);
    db.execute('INSERT INTO contacts (payload) VALUES (?)', <Object?>[
      jsonEncode(<String, dynamic>{'id': 'c2', 'firstName': 'Grace'})
    ]);
    db.close();

    final List<VaultContact> read =
        DeviceLegacyContactsSource.readContactsDatabase(path);
    expect(read.map((VaultContact c) => c.displayName),
        unorderedEquals(<String>['Ada', 'Grace']));
    dir.deleteSync(recursive: true);
  });

  moverAndFileTests();
}

void moverAndFileTests() {
  group('photo mover', () {
    late Map<String, VaultContact> saved;
    late InMemoryAttachmentBackend files;
    late ContactPhotos photos;

    setUp(() {
      saved = <String, VaultContact>{};
      files = InMemoryAttachmentBackend();
      photos = ContactPhotos(ZtAttachments(
        appId: 'contacts',
        userId: 'u1',
        backend: files,
        cache: InMemoryAttachmentCache(),
      ));
    });

    LegacyPhotoMover mover(FakeLegacySource source,
            {void Function()? whileUploading}) =>
        LegacyPhotoMover(
          source: source,
          photos: photos,
          load: () async => saved.values.toList(),
          find: (String id) async {
            whileUploading?.call();
            whileUploading = null;
            return saved[id];
          },
          save: (VaultContact c) async => saved[c.id] = c,
        );

    test('keeps an edit made while the photo was uploading', () async {
      saved['c1'] = contact('c1', 'Ada').copyWith(photoPath: 'c1');
      final FakeLegacySource source = FakeLegacySource(
          photos: <String, Uint8List>{'c1': Uint8List.fromList(<int>[1])});

      final int moved = await mover(source, whileUploading: () {
        saved['c1'] = saved['c1']!.applyEdits(notes: 'edited meanwhile');
      }).run();

      expect(moved, 1);
      expect(saved['c1']!.notes, 'edited meanwhile');
      expect(saved['c1']!.photo, isNotNull);
      expect(saved['c1']!.photoPath, isNull);
    });

    test('doesn\'t bring back a contact deleted meanwhile', () async {
      saved['c1'] = contact('c1', 'Ada').copyWith(photoPath: 'c1');
      final FakeLegacySource source = FakeLegacySource(
          photos: <String, Uint8List>{'c1': Uint8List.fromList(<int>[1])});

      await mover(source, whileUploading: () => saved.remove('c1')).run();

      expect(saved, isEmpty);
    });
  });

  test('local file updates at the same time all land', () async {
    final InMemoryLocalVaultFile file = InMemoryLocalVaultFile();
    await Future.wait(<Future<void>>[
      for (var i = 0; i < 20; i++)
        file.update((Map<String, Object?> data) {
          data['n'] = ((data['n'] as int?) ?? 0) + 1;
        }),
    ]);
    expect((await file.read())['n'], 20);
  });
}
