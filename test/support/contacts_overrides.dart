import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_source.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_controller.dart';
import 'package:zerotrust_contacts/main.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';

/// Fast KDF for tests (the real one is 600k rounds).
const KdfParams testKdf = KdfParams(iterations: 1000);

/// Everything Contacts needs to run without Supabase, a keychain or a disk.
List<Override> contactsTestOverrides({
  required SyncBackend server,
  required String deviceId,
  LegacyContactsSource Function(String userId)? legacySource,
  AttachmentBackend? attachmentServer,
}) =>
    <Override>[
      ztAppConfigProvider.overrideWithValue(contactsAppConfig),
      ztSyncBackendProvider.overrideWithValue(server),
      ztDeviceIdStoreProvider
          .overrideWithValue(InMemoryDeviceIdStore()..id = deviceId),
      ztPreferencesStoreProvider.overrideWithValue(InMemoryPreferencesStore()),
      ztLocalStoreProvider.overrideWith((ref) async {
        final appKey = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (appKey == null) throw const VaultIsLocked();
        final store = await ZtLocalStore.open(appKey: appKey);
        ref.onDispose(store.close);
        return store;
      }),
      localVaultFileProvider.overrideWith((ref) {
        final unlocked = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (unlocked == null) throw const VaultIsLocked();
        return InMemoryLocalVaultFile();
      }),
      ztAttachmentBackendProvider
          .overrideWithValue(attachmentServer ?? InMemoryAttachmentBackend()),
      ztAttachmentCacheProvider.overrideWith((ref) {
        final unlocked = ref.watch(vaultControllerProvider
            .select((v) => v is VaultUnlocked ? v.appKey : null));
        if (unlocked == null) throw const VaultIsLocked();
        return InMemoryAttachmentCache();
      }),
      ztBreachedPasswordCheckerProvider.overrideWithValue(const NoBreachCheck()),
      legacyContactsKdfProvider.overrideWithValue(testKdf),
      legacyContactsSourceProvider.overrideWithValue(
          legacySource ?? (String _) => throw StateError('no legacy source')),
    ];
