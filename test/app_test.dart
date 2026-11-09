import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, User;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/auth_providers.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_crypto.dart';
import 'package:zerotrust_contacts/main.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';

import 'legacy_import_test.dart' show contact, oldBlob;
import 'support/contacts_overrides.dart';
import 'support/fake_account_backend.dart';
import 'support/fake_legacy_source.dart';
import 'support/fake_sync_backend.dart';

const String email = 'edo@example.com';
const String password = 'Vivid-Otter-Lamp-93!';
const String legacySalt = 'AAECAwQFBgcICQoLDA0ODw';

/// A valid 1x1 PNG, standing in for an old contact photo.
final Uint8List onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class FakeUser extends Notifier<User?> {
  @override
  User? build() => null;

  void set(String? email) => state = email == null
      ? null
      : User(
          id: email,
          appMetadata: const <String, dynamic>{},
          userMetadata: const <String, dynamic>{},
          aud: 'authenticated',
          createdAt: '2026-11-09T00:00:00Z',
          email: email,
        );
}

final NotifierProvider<FakeUser, User?> fakeUserProvider =
    NotifierProvider<FakeUser, User?>(FakeUser.new);

void main() {
  late ProviderContainer container;
  late FakeAccountBackend backend;
  late FakeLegacySource legacy;
  late InMemoryAttachmentBackend files;

  setUp(() {
    legacy = FakeLegacySource();
    files = InMemoryAttachmentBackend();
    container = ProviderContainer(
      // A locked vault is an error by design; don't retry it on a timer.
      retry: (int _, Object __) => null,
      overrides: [
        ...contactsTestOverrides(
          server: FakeSyncBackend(),
          deviceId: 'test-device',
          legacySource: (_) => legacy,
          attachmentServer: files,
        ),
        authStateChangesProvider
            .overrideWith((ref) => const Stream<AuthState>.empty()),
        currentUserProvider.overrideWith((ref) => ref.watch(fakeUserProvider)),
        accountServiceProvider.overrideWith(
          (ref) => AccountService(backend,
              params: testKdf, legacyParams: testKdf),
        ),
      ],
    );
    backend = FakeAccountBackend(
      onUserChanged: (String? email) =>
          container.read(fakeUserProvider.notifier).set(email),
    );
  });

  tearDown(() => container.dispose());

  /// Crypto and the database run on real timers; let them finish, and let
  /// page transitions finish too.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const ZeroTrustContactsApp()));
  }

  Future<void> confirmRecoveryKey(WidgetTester tester) async {
    expect(find.text('Save your recovery key'), findsOneWidget);
    expect(container.read(vaultControllerProvider), isA<VaultLocked>());
    await tester.tap(find.text('I saved my recovery key somewhere safe'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settle(tester);
  }

  testWidgets('new account: recovery key first, then contacts; lock and unlock',
      (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text('Zero-Trust Contacts'), findsOneWidget);

    await tester.tap(find.text('Create a Zero-Trust account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await settle(tester);
    await confirmRecoveryKey(tester);

    expect(find.text('Bring your Google contacts'), findsOneWidget);
    // Nothing to bring over for an account made on the core.
    expect(find.text('Bring over your contacts from before the update'),
        findsNothing);

    final repo = await container.read(vaultRepositoryProvider.future);
    final Future<void> saving = repo.upsertSavedContact(contact('c1', 'Ada'));
    await settle(tester);
    await saving;
    await settle(tester);
    expect(find.text('Ada'), findsWidgets);
    // Up to the server, so the next unlock (with a fresh in-memory store)
    // gets it back.
    final Future<void> syncing =
        container.read(ztSyncControllerProvider.notifier).syncNow();
    await settle(tester);
    await syncing;

    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Zero-Trust Contacts is locked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(find.text('Ada'), findsWidgets);

    // Auto-lock while the editor is open: back to the lock screen, cleanly.
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.byType(CreateContactPage), findsOneWidget);
    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Zero-Trust Contacts is locked'), findsOneWidget);
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester);
    expect(find.text('Ada'), findsWidgets);

    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Restore points'), 200);
    expect(find.text('Import from Google'), findsOneWidget);

    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
    expect(find.text('Zero-Trust Contacts is locked'), findsOneWidget);
  });

  testWidgets(
      'pre-core account: signs in, upgrades, and brings over its contacts '
      'and photo', (WidgetTester tester) async {
    // An account from before the core, with contacts in encrypted_contacts.
    backend.authPasswords[email] = password;
    backend.profiles[email] = const ProfileRecord(legacySalt: legacySalt);
    final Uint8List oldKey = await LegacyContactsCrypto.deriveKey(
        password: password, legacySalt: legacySalt, kdf: testKdf);
    final VaultContact ada =
        contact('c1', 'Ada').copyWith(photoPath: 'c1');
    legacy
      ..legacySalt = legacySalt
      ..cloudBlob = await oldBlob(<VaultContact>[ada, contact('c2', 'Grace')],
          oldKey)
      ..photos['c1'] = onePixelPng;

    await pumpApp(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    // Upgraded to the core's keys: a recovery key comes first.
    await confirmRecoveryKey(tester);
    expect(backend.authPasswords[email], isNot(password));

    // This phone never had Contacts, so the old key needs the password.
    expect(find.text('Bring over your contacts from before the update'),
        findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Bring over'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, password);
    await tester.tap(find.widgetWithText(FilledButton, 'Bring over').last);
    await settle(tester);
    await settle(tester);

    expect(find.text('Brought over 2 contacts.'), findsOneWidget);
    expect(find.text('Ada'), findsWidgets);
    expect(find.text('Grace'), findsWidgets);
    expect(find.text('Bring over your contacts from before the update'),
        findsNothing);

    // The old plain photo is now an encrypted attachment.
    final repo = await container.read(vaultRepositoryProvider.future);
    final Future<VaultContact?> finding = repo.findSavedContactById('c1');
    await settle(tester);
    final VaultContact? moved = await finding;
    expect(moved!.photoPath, isNull);
    expect(moved.photo, isNotNull);
    expect(container.read(vaultControllerProvider),
        isA<VaultUnlocked>().having((v) => v.legacyKey, 'legacyKey', isNull));

    container.read(vaultControllerProvider.notifier).lock();
    await settle(tester);
  });
}
