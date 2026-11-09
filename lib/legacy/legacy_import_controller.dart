import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_crypto.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_importer.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_source.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

enum LegacyImportStatus {
  /// Not checked yet in this unlock, or checking.
  unknown,

  /// Earlier contacts exist and need the password from before the update.
  needsPassword,

  /// Nothing (left) to import on this device.
  done,

  /// The last attempt failed (offline, say); it runs again on next unlock.
  failed,
}

/// Overridable so tests can supply a fake source.
final legacyContactsSourceProvider =
    Provider<LegacyContactsSource Function(String userId)>(
  (ref) => (String userId) => DeviceLegacyContactsSource(userId: userId),
);

/// KDF settings for the old key. Tests use fewer rounds.
final legacyContactsKdfProvider =
    Provider<KdfParams>((ref) => LegacyContactsCrypto.params);

/// Runs the one-time import of contacts from before the update, and the
/// move of old photos into encrypted attachments.
class LegacyImportController extends Notifier<LegacyImportStatus> {
  Future<void>? _running;

  @override
  LegacyImportStatus build() {
    // A new unlock (or account) starts over.
    ref.watch(vaultRepositoryProvider.select((r) => r.hasValue));
    return LegacyImportStatus.unknown;
  }

  /// Runs without asking: works when this device still has the old key,
  /// or there's nothing to import.
  Future<void> runQuietly() =>
      _running ??= _run(null).whenComplete(() => _running = null);

  /// Runs with the password from before the update. Throws
  /// [LegacyPasswordNeeded] when it's wrong. Returns contacts imported.
  Future<int> runWithPassword(String password) => _run(password);

  Future<int> _run(String? password) async {
    final VaultState vault = ref.read(vaultControllerProvider);
    final String? userId = ref.read(accountServiceProvider).currentUserId;
    if (vault is! VaultUnlocked || userId == null) return 0;
    final bool preCore = vault.legacyKey != null;
    final LegacyContactsSource source;
    final VaultRepository repo;
    int imported = 0;
    try {
      source = ref.read(legacyContactsSourceProvider)(userId);
      repo = await ref.read(vaultRepositoryProvider.future);
      final ItemSyncEngine engine = await ref.read(ztSyncEngineProvider.future);
      final LocalItemStore store = await ref.read(ztLocalStoreProvider.future);
      if (store is! LegacyImportLedger) {
        throw StateError('The local store does not record imports');
      }
      final LegacyContactsImporter importer = LegacyContactsImporter(
        source: source,
        engine: engine,
        ledger: store as LegacyImportLedger,
        kdf: ref.read(legacyContactsKdfProvider),
      );
      if (!await importer.isDone()) {
        imported =
            await importer.run(preCoreAccount: preCore, password: password);
        if (imported > 0) {
          await repo.logActivity('legacy_import',
              details: 'Brought over $imported contacts from before the '
                  'update');
          unawaited(ref.read(ztSyncControllerProvider.notifier).syncNow());
        }
      }
      // Contacts never reads data under the core's legacy key.
      ref.read(vaultControllerProvider.notifier).forgetLegacyKey();
      _set(LegacyImportStatus.done);
    } on LegacyPasswordNeeded {
      _set(LegacyImportStatus.needsPassword);
      if (password != null) rethrow;
      return 0;
    } on Object {
      _set(LegacyImportStatus.failed);
      if (password != null) rethrow;
      return 0;
    }
    await _movePhotos(source, repo);
    return imported;
  }

  Future<void> _movePhotos(
      LegacyContactsSource source, VaultRepository repo) async {
    try {
      final ContactPhotos photos =
          await ref.read(contactPhotosProvider.future);
      await LegacyPhotoMover(
        source: source,
        photos: photos,
        load: repo.loadSavedContacts,
        find: repo.findSavedContactById,
        save: (contact) =>
            repo.upsertSavedContact(contact, activity: 'legacy_photo_moved'),
      ).run();
    } on Object {
      // Retried on the next unlock.
    }
  }

  void _set(LegacyImportStatus status) {
    if (ref.mounted) state = status;
  }
}

final legacyImportProvider =
    NotifierProvider<LegacyImportController, LegacyImportStatus>(
        LegacyImportController.new);
