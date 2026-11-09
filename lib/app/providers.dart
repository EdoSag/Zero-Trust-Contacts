import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/local_vault_file.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

/// The unlocked app key, or null while locked.
final _appKeyProvider = Provider<Uint8List?>((ref) => ref.watch(
    vaultControllerProvider
        .select((s) => s is VaultUnlocked ? s.appKey : null)));

/// Restore points and the activity log of the unlocked account.
final localVaultFileProvider = FutureProvider<LocalVaultFile>((ref) async {
  final Uint8List? unlocked = ref.watch(_appKeyProvider);
  if (unlocked == null) throw const VaultIsLocked();
  final Uint8List appKey = Uint8List.fromList(unlocked);
  final String? userId = ref.watch(accountServiceProvider).currentUserId;
  if (userId == null) throw StateError('Not signed in');
  try {
    final SealedLocalVaultFile file =
        await SealedLocalVaultFile.open(appKey: appKey, userId: userId);
    ref.onDispose(file.close);
    return file;
  } finally {
    appKey.fillRange(0, appKey.length, 0);
  }
});

final contactPhotosProvider = FutureProvider<ContactPhotos>(
    (ref) async => ContactPhotos(await ref.watch(ztAttachmentsProvider.future)));

/// The address book of the unlocked account. Rebuilt on every unlock.
final vaultRepositoryProvider = FutureProvider<VaultRepository>((ref) async {
  final LocalItemStore store = await ref.watch(ztLocalStoreProvider.future);
  final LocalVaultFile localFile =
      await ref.watch(localVaultFileProvider.future);
  ContactPhotos? photos;
  try {
    photos = await ref.watch(contactPhotosProvider.future);
  } on VaultIsLocked {
    rethrow;
  } on Object {
    photos = null; // Photos unavailable; contacts still work.
  }
  return VaultRepository(
    store: store,
    sync: ref.watch(ztSyncControllerProvider.notifier),
    localFile: localFile,
    photos: photos,
    changes: store is ZtLocalStore ? store.changes : null,
  );
});

/// The repository once open, for widgets below the gate (which only shows
/// them after [vaultRepositoryProvider] has loaded).
VaultRepository requireRepository(WidgetRef ref) =>
    switch (ref.read(vaultRepositoryProvider)) {
      AsyncData(:final VaultRepository value) => value,
      _ => throw const VaultIsLocked(),
    };
