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

  /// Bumped when the phone's copy is removed; a run started before that
  /// stops before its next write.
  int _epoch = 0;

  /// Completes when the run in progress ends. Removal waits for it, so no
  /// write can land after the copy has been removed.
  Future<void>? _inFlight;

  /// The choice of details the phone's copies were last fully written
  /// with. It trails `state.fields` from the moment the choice changes
  /// until the next run has rewritten every copy.
  PhoneSyncFields? _written;

  Future<void> _stopRuns() async {
    _debounce?.cancel();
    _epoch++;
    try {
      await _inFlight;
    } on Object {
      // The run's own error is already in state.
    }
  }

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
        // Saved before this was tracked: the copies match the choice.
        _written = json['written'] is Map
            ? PhoneSyncFields.fromJson(
                Map<String, Object?>.from(json['written']! as Map))
            : loaded.fields;
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
        if (_written != null) 'written': _written!.toJson(),
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
    _written = fields; // Nothing is on the phone yet.
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
    state = state.copyWith(enabled: false, onPhone: 0, clearError: true);
    await _stopRuns();
    _written = null;
    await _save();
    if (isSupported) await _bridge.disable();
  }

  /// On sign-out the phone's copy goes too, and the setting is reset so the
  /// next account on this phone starts with it off.
  Future<void> signedOut() async {
    final bool wasEnabled = state.enabled;
    state = state.copyWith(enabled: false, onPhone: 0);
    await _stopRuns();
    _written = null;
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
    final Completer<void> done = Completer<void>();
    _inFlight = done.future;
    final int epoch = _epoch;
    try {
      do {
        _rerun = false;
        await _runOnce(repo, epoch);
      } while (_rerun && state.enabled && ref.mounted && epoch == _epoch);
    } on Object catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
            error: 'Couldn\'t update the phone\'s contacts: $error');
      }
    } finally {
      done.complete();
      if (ref.mounted) state = state.copyWith(running: false);
    }
  }

  Future<void> _runOnce(VaultRepository repo, int epoch) async {
    bool cancelled() => epoch != _epoch || !state.enabled || !ref.mounted;
    await _pullPhoneChanges(repo, cancelled);
    if (cancelled()) return;
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
        if (cancelled()) return;
        final List<Map<String, Object?>> chunk = <Map<String, Object?>>[];
        for (final PhoneSyncEntry entry in plan.upserts.skip(i).take(50)) {
          Uint8List? photo;
          if (entry.photoId != null && photos != null) {
            photo = await photos.read(byId[entry.id]!);
          }
          // A photo that couldn't be read (offline, say) is written without
          // it under a hash that won't match, so the next run tries again.
          final bool photoMissing = entry.photoId != null && photo == null;
          chunk.add(<String, Object?>{
            ...entry.fields,
            'id': entry.id,
            'hash': photoMissing ? '${entry.hash}:no-photo' : entry.hash,
            if (photo != null) 'photo': photo,
          });
        }
        // Photo reads take time: removal may have started meanwhile.
        if (cancelled()) return;
        await _bridge.apply(chunk, i == 0 ? plan.deletes : const <String>[]);
      }
    }
    // Every copy now follows this choice of details.
    if (jsonEncode(_written?.toJson()) != jsonEncode(fields.toJson())) {
      _written = fields;
      await _save();
    }
    if (ref.mounted) {
      state = state.copyWith(
          onPhone: contacts.length, lastUpdated: DateTime.now());
    }
  }

  /// Takes changes made in the phone's contacts app (an edited, new or
  /// deleted ZT Contacts contact) into the vault, before the vault is
  /// written back out.
  Future<void> _pullPhoneChanges(
    VaultRepository repo,
    bool Function() cancelled,
  ) async {
    final List<PhoneChange> changes = await _bridge.changes();
    const PhoneSyncPlanner planner = PhoneSyncPlanner();
    // What the changed copies were written with, not what was just chosen:
    // a detail that was never on the phone can't have been removed there.
    final PhoneSyncFields onPhone =
        state.fields.intersect(_written ?? state.fields);
    for (final PhoneChange change in changes) {
      if (cancelled()) return;
      final String? id = change.sourceId;
      final VaultContact? current = id == null
          ? null
          : await repo.findSavedContactById(id);
      if (change.deleted) {
        // Deleted on the phone: to the trash here, where it can be restored.
        if (current != null) await repo.deleteSavedContact(current.id);
        await _bridge.acknowledge(change);
        continue;
      }
      if (id != null && current == null) {
        // Its vault contact is gone (deleted on another device): the copy
        // goes too rather than coming back.
        await _bridge.acknowledge(change);
        continue;
      }
      final VaultContact merged = planner.mergePhoneEdit(
        current,
        change,
        onPhone,
      );
      if (!identical(merged, current)) {
        await repo.upsertSavedContact(
          merged,
          activity: current == null
              ? 'contact_saved_from_phone'
              : 'contact_edit_from_phone',
        );
      }
      await _bridge.acknowledge(change, vaultId: merged.id);
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
