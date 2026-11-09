import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/phone_sync/phone_contacts_bridge.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

final phoneContactsBridgeProvider = Provider<PhoneContactsBridge>(
    (ref) => const MethodChannelPhoneContactsBridge());

class PhoneSyncStatus {
  const PhoneSyncStatus({
    this.loaded = false,
    this.enabled = false,
    this.fields = const PhoneSyncFields(),
    this.running = false,
    this.onPhone,
    this.lastUpdated,
    this.error,
  });

  /// The saved setting has been read.
  final bool loaded;
  final bool enabled;
  final PhoneSyncFields fields;
  final bool running;

  /// How many contacts the phone holds from the vault, once known.
  final int? onPhone;
  final DateTime? lastUpdated;
  final String? error;

  PhoneSyncStatus copyWith({
    bool? loaded,
    bool? enabled,
    PhoneSyncFields? fields,
    bool? running,
    int? onPhone,
    DateTime? lastUpdated,
    String? error,
    bool clearError = false,
  }) =>
      PhoneSyncStatus(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        fields: fields ?? this.fields,
        running: running ?? this.running,
        onPhone: onPhone ?? this.onPhone,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        error: clearError ? null : (error ?? this.error),
      );
}

/// "Show in Phone and Messages": keeps a copy of chosen contact details in
/// the phone's own contacts, so the dialer, caller ID and messaging apps
/// know who's calling. Off by default; the copy is only refreshed while the
/// vault is unlocked (that's when contacts can be decrypted) and is removed
/// when the feature is turned off or the account signs out.
class PhoneSyncController extends Notifier<PhoneSyncStatus> {
  static const String _key = 'contacts_phone_sync';

  StreamSubscription<Set<String>>? _changes;
  Timer? _debounce;
  bool _rerun = false;

  PhoneContactsBridge get _bridge => ref.read(phoneContactsBridgeProvider);

  @override
  PhoneSyncStatus build() {
    ref.onDispose(() {
      _changes?.cancel();
      _debounce?.cancel();
    });
    ref.listen<AsyncValue<VaultRepository>>(vaultRepositoryProvider,
        (_, AsyncValue<VaultRepository> next) => _attach(next));
    _load();
    return const PhoneSyncStatus();
  }

  bool get isSupported => _bridge.isSupported;

  Future<void> _load() async {
    PhoneSyncStatus loaded = const PhoneSyncStatus(loaded: true);
    await Future<void>.value(); // Let build() return first.
    try {
      final String? raw = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (raw != null) {
        final Map<String, Object?> json =
            Map<String, Object?>.from(jsonDecode(raw) as Map);
        loaded = loaded.copyWith(
          enabled: json['enabled'] == true && isSupported,
          fields: PhoneSyncFields.fromJson(Map<String, Object?>.from(
              (json['fields'] as Map?) ?? const <String, Object?>{})),
        );
      }
    } on Object {
      // Unreadable setting: stays off.
    }
    if (!ref.mounted) return;
    state = loaded;
    _attach(ref.read(vaultRepositoryProvider));
  }

  Future<void> _save() => ref.read(ztPreferencesStoreProvider).write(
      _key,
      jsonEncode(<String, Object?>{
        'enabled': state.enabled,
        'fields': state.fields.toJson(),
      }));

  void _attach(AsyncValue<VaultRepository> repo) {
    _changes?.cancel();
    _changes = null;
    if (repo case AsyncData(:final VaultRepository value)) {
      _changes = value.changes.listen((_) {
        if (state.enabled) _schedule(const Duration(seconds: 2));
      });
      if (state.enabled) _schedule(const Duration(seconds: 1));
    }
  }

  void _schedule(Duration after) {
    _debounce?.cancel();
    _debounce = Timer(after, () => unawaited(run()));
  }

  /// Turns it on with [fields] after asking for contacts permission.
  /// Returns false when the permission was refused.
  Future<bool> enable(PhoneSyncFields fields) async {
    if (!isSupported) return false;
    final bool granted = await ref
        .read(vaultControllerProvider.notifier)
        .whileShowingSystemUi(_bridge.requestPermission);
    if (!granted) {
      state = state.copyWith(
          error: 'Contacts permission is needed to show contacts in the '
              'Phone and Messages apps.');
      return false;
    }
    state = state.copyWith(enabled: true, fields: fields, clearError: true);
    await _save();
    await run();
    return true;
  }

  Future<void> setFields(PhoneSyncFields fields) async {
    state = state.copyWith(fields: fields);
    await _save();
    if (state.enabled) await run();
  }

  /// Turns it off and removes every contact it put on the phone.
  Future<void> disable() async {
    _debounce?.cancel();
    state = state.copyWith(enabled: false, onPhone: 0, clearError: true);
    await _save();
    if (isSupported) await _bridge.disable();
  }

  /// On sign-out the phone's copy goes too, and the setting is reset so the
  /// next account on this phone starts with it off.
  Future<void> signedOut() async {
    _debounce?.cancel();
    final bool wasEnabled = state.enabled;
    state = state.copyWith(enabled: false, onPhone: 0);
    if (!isSupported) return;
    try {
      if (wasEnabled || (await _bridge.state()).accountExists) {
        await _bridge.disable();
      }
      await _save();
    } on Object {
      // Best effort; the account is removed next time it's turned off.
    }
  }

  /// Brings the phone's copy up to date with the vault.
  Future<void> run() async {
    if (!state.enabled || !isSupported) return;
    if (state.running) {
      _rerun = true;
      return;
    }
    final VaultRepository? repo = switch (ref.read(vaultRepositoryProvider)) {
      AsyncData(:final VaultRepository value) => value,
      _ => null,
    };
    if (repo == null) return; // Locked: updated on the next unlock.
    state = state.copyWith(running: true, clearError: true);
    try {
      do {
        _rerun = false;
        await _runOnce(repo);
      } while (_rerun && state.enabled && ref.mounted);
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
            error: 'Couldn\'t update the phone\'s contacts: $error');
      }
    } finally {
      if (ref.mounted) state = state.copyWith(running: false);
    }
  }

  Future<void> _runOnce(VaultRepository repo) async {
    final List<VaultContact> contacts = await repo.loadSavedContacts();
    final PhoneContactsState onPhone = await _bridge.state();
    final PhoneSyncFields fields = state.fields;
    final PhoneSyncPlan plan = const PhoneSyncPlanner().plan(
      contacts: contacts,
      fields: fields,
      onPhone: onPhone.accountExists ? onPhone.hashes : const <String, String>{},
    );
    if (!plan.isEmpty) {
      final ContactPhotos? photos = await _photos();
      final Map<String, VaultContact> byId = <String, VaultContact>{
        for (final VaultContact c in contacts) c.id: c,
      };
      // In chunks, so a big address book's photos aren't all in memory.
      for (int i = 0; i < plan.upserts.length || i == 0; i += 50) {
        if (!state.enabled || !ref.mounted) return;
        final List<Map<String, Object?>> chunk = <Map<String, Object?>>[];
        for (final PhoneSyncEntry entry in plan.upserts.skip(i).take(50)) {
          Uint8List? photo;
          if (entry.photoId != null && photos != null) {
            photo = await photos.read(byId[entry.id]!);
          }
          chunk.add(<String, Object?>{
            ...entry.fields,
            'id': entry.id,
            'hash': entry.hash,
            if (photo != null) 'photo': photo,
          });
        }
        await _bridge.apply(chunk, i == 0 ? plan.deletes : const <String>[]);
      }
    }
    if (ref.mounted) {
      state = state.copyWith(
          onPhone: contacts.length, lastUpdated: DateTime.now());
    }
  }

  Future<ContactPhotos?> _photos() async {
    try {
      return await ref.read(contactPhotosProvider.future);
    } on Object {
      return null; // Photos unavailable: contacts go without them.
    }
  }
}

final phoneSyncProvider =
    NotifierProvider<PhoneSyncController, PhoneSyncStatus>(
        PhoneSyncController.new);
