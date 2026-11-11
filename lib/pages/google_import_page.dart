import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/ios_address_book.dart';
import 'package:zerotrust_contacts/import/photo_downloader.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// "Import from Google" in a few taps.
///
/// Two ways in, neither of which signs in to Google or sends contacts
/// anywhere: read the Google account already synced to this phone (Android),
/// or open the .vcf file Google Contacts exports. Contacts are parsed on the
/// device and written straight into the encrypted vault.
class GoogleImportPage extends ConsumerStatefulWidget {
  const GoogleImportPage({
    super.key,
    this.vCardText,
    this.vCardName,
    this.isIOS,
    this.addressBook = const IosAddressBook(),
  });

  /// Whether to offer the iPhone address book. Null asks the platform.
  final bool? isIOS;

  /// Reads the iPhone address book; replaced in tests.
  final IosAddressBook addressBook;

  /// A vCard to preview straight away (a .vcf file opened with or shared to
  /// the app, a scanned QR code, a file picked in Settings). The page then
  /// only shows that preview.
  final String? vCardText;

  /// Where [vCardText] came from, for the preview and the activity log.
  final String? vCardName;

  @override
  ConsumerState<GoogleImportPage> createState() => _GoogleImportPageState();
}

class _GoogleImportPageState extends ConsumerState<GoogleImportPage> {
  final DeviceContactsService _deviceService = DeviceContactsService();
  late final VaultRepository _vaultRepository = requireRepository(ref);

  bool _loadingAccounts = true;
  bool _permissionDenied = false;
  List<ImportAccount> _accounts = <ImportAccount>[];

  bool _busy = false;
  String? _busyText;

  /// Set once a source is read: what the import will do, before it does it.
  _PendingImport? _pending;

  bool get _isAndroid => Platform.isAndroid;
  bool get _isIOS => widget.isIOS ?? Platform.isIOS;

  /// True after iOS refused access to the address book.
  bool _addressBookDenied = false;

  /// The source being previewed is this phone's own address book, not
  /// Google, so the summary and the activity log say so.
  bool _fromThisPhone = false;

  Future<void> _previewAddressBook() async {
    await _withBusy(context.l10n.readingThisIphonesContacts, () async {
      final bool granted = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(widget.addressBook.requestPermission);
      if (mounted) setState(() => _addressBookDenied = !granted);
      if (!granted) {
        return;
      }
      final AddressBookImport read = await widget.addressBook.read();
      await _preparePreview(
        sourceLabel: currentL10n.iphoneContacts,
        incoming: read.contacts,
        photos: <String, PhotoLoader>{
          for (final MapEntry<String, String> e in read.photoIds.entries)
            e.key: () => widget.addressBook.photo(e.value),
        },
      );
      if (mounted) setState(() => _fromThisPhone = true);
    });
  }

  @override
  void initState() {
    super.initState();
    final String? text = widget.vCardText;
    if (text == null) {
      _loadAccounts();
    } else {
      _loadingAccounts = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _withBusy(
          context.l10n.reading,
          () => _previewVCard(text, widget.vCardName ?? 'vCard'),
        );
      });
    }
  }

  bool get _vCardOnly => widget.vCardText != null;

  Future<void> _loadAccounts() async {
    if (!_isAndroid) {
      setState(() => _loadingAccounts = false);
      return;
    }
    try {
      final bool granted = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(_deviceService.requestPermission);
      if (!granted) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _loadingAccounts = false;
          });
        }
        return;
      }
      final List<ImportAccount> accounts = await _deviceService
          .loadImportAccounts();
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _permissionDenied = false;
          _loadingAccounts = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingAccounts = false);
      }
    }
  }

  Future<void> _previewAccount(ImportAccount account) async {
    await _withBusy(context.l10n.readingName(account.name), () async {
      final List<Map<String, dynamic>> rows = await _deviceService
          .loadAccountContacts(account.name);
      final AccountImport read = accountImportFromFields(rows);
      await _preparePreview(
        sourceLabel: account.name,
        incoming: read.contacts,
        photos: <String, PhotoLoader>{
          for (final MapEntry<String, int> e in read.photoRawIds.entries)
            e.key: () => _deviceService.loadRawContactPhoto(e.value),
        },
      );
    });
  }

  Future<void> _pickExportFile() async {
    final List<PlatformFile> picked = await ref
        .read(vaultControllerProvider.notifier)
        .whileShowingSystemUi(() => FilePicker.pickFiles(type: FileType.any));
    final PlatformFile? file = picked.singleOrNull;
    if (file == null) {
      return;
    }
    await _withBusy(currentL10n.readingName(file.name), () async {
      final List<int> bytes = await file.xFile.readAsBytes();
      final String text = utf8.decode(bytes, allowMalformed: true);
      if (!text.toUpperCase().contains('BEGIN:VCARD')) {
        throw StateError(
          currentL10n.thatFileIsNotA,
        );
      }
      await _previewVCard(text, file.name);
    });
  }

  Future<void> _previewVCard(String text, String name) async {
    if (!text.toUpperCase().contains('BEGIN:VCARD')) {
      throw StateError('$name has no contacts in it.');
    }
    final VCardImport parsed = const VCardParser().parseWithPhotos(text);
    await _preparePreview(
      sourceLabel: name,
      incoming: parsed.contacts,
      photos: <String, PhotoLoader>{
        for (final MapEntry<String, VCardPhoto> e in parsed.photos.entries)
          if (e.value.bytes case final Uint8List bytes)
            e.key: () async => bytes,
      },
      linkedPhotos: <String, Uri>{
        for (final MapEntry<String, VCardPhoto> e in parsed.photos.entries)
          if (e.value.url case final Uri url) e.key: url,
      },
    );
  }

  Future<void> _preparePreview({
    required String sourceLabel,
    required List<VaultContact> incoming,
    Map<String, PhotoLoader> photos = const <String, PhotoLoader>{},
    Map<String, Uri> linkedPhotos = const <String, Uri>{},
  }) async {
    if (incoming.isEmpty) {
      throw StateError('No contacts found in $sourceLabel.');
    }
    final ContactImportPlan plan = await _vaultRepository.planImport(incoming);
    final int newPhotos = await _vaultRepository.countPhotosToAdd(
      plan,
      photos.keys,
    );
    final int newLinkedPhotos = await _vaultRepository.countPhotosToAdd(
      plan,
      linkedPhotos.keys.where((String id) => !photos.containsKey(id)),
    );
    if (mounted) {
      setState(() {
        _downloadLinkedPhotos = false;
        _fromThisPhone = false;
        _pending = _PendingImport(
          sourceLabel: sourceLabel,
          incoming: incoming,
          plan: plan,
          photos: photos,
          linkedPhotos: linkedPhotos,
          newPhotos: newPhotos,
          newLinkedPhotos: newLinkedPhotos,
        );
      });
    }
  }

  /// Whether to fetch photos a Google export only links to. Off unless the
  /// user turns it on, since it connects to Google's photo server.
  bool _downloadLinkedPhotos = false;

  Future<void> _confirmImport() async {
    final _PendingImport? pending = _pending;
    if (pending == null) {
      return;
    }
    final PhotoDownloader? downloader =
        _downloadLinkedPhotos && pending.linkedPhotos.isNotEmpty
        ? PhotoDownloader()
        : null;
    final Map<String, PhotoLoader> photos = <String, PhotoLoader>{
      if (downloader != null)
        for (final MapEntry<String, Uri> e in pending.linkedPhotos.entries)
          e.key: () => downloader.download(e.value),
      ...pending.photos,
    };
    await _withBusy(context.l10n.encryptingAndSaving, () async {
      final ContactImportPlan done = await _vaultRepository.importContacts(
        pending.incoming,
        sourceLabel: _vCardOnly || _fromThisPhone
            ? pending.sourceLabel
            : 'Google (${pending.sourceLabel})',
        photos: photos,
        onPhotoProgress: (int doneCount, int total) {
          if (mounted && total > 0) {
            setState(
              () => _busyText = currentL10n.encryptingPhotos(doneCount, total),
            );
          }
        },
      );
      downloader?.close();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_summary(done))));
      Navigator.of(context).pop(true);
    });
  }

  String _summary(ContactImportPlan plan) {
    if (plan.isEmpty && plan.photosAdded == 0) {
      return context.l10n.everythingWasAlreadyInYour;
    }
    final List<String> parts = <String>[
      if (plan.toAdd.isNotEmpty) context.l10n.nAdded(plan.toAdd.length),
      if (plan.toUpdate.isNotEmpty) context.l10n.nUpdated(plan.toUpdate.length),
      if (plan.photosAdded > 0)
        context.l10n.nPhotos(plan.photosAdded),
    ];
    final String details = parts.join(', ');
    return _vCardOnly
        ? context.l10n.importedSummary(details)
        : _fromThisPhone
        ? context.l10n.importedFromIphoneSummary(details)
        : context.l10n.importedFromGoogleSummary(details);
  }

  Future<void> _withBusy(String text, Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final String message = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyText = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _pending == null || _busy || _vCardOnly,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && !_busy) {
          setState(() => _pending = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _vCardOnly || _isIOS ? context.l10n.importContacts : context.l10n.importFromGoogle,
          ),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _pending == null
                  ? (_vCardOnly
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _busy
                                    ? context.l10n.reading
                                    : widget.vCardName == null
                                          ? context.l10n.nothingToImportFromFile
                                          : context.l10n.nothingToImportFrom(widget.vCardName!),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _buildSources(context))
                  : _buildPreview(context, _pending!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSources(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PrivacyNote(colors: colors),
        const SizedBox(height: 16),
        if (_isAndroid) ...[
          Text(
            context.l10n.googleAccountsOnThisPhone,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_loadingAccounts)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_permissionDenied)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(context.l10n.allowAccessToContacts),
                subtitle: Text(
                  context.l10n.neededToReadTheGoogle,
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : _loadAccounts,
                  child: Text(context.l10n.allow),
                ),
              ),
            )
          else if (_accounts.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_off_outlined),
                title: Text(context.l10n.noGoogleContactsOnThis),
                subtitle: Text(
                  context.l10n.addYourGoogleAccountIn,
                ),
              ),
            )
          else
            ..._accounts.map((ImportAccount account) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.account_circle_outlined,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  title: Text(account.name),
                  subtitle: Text(context.l10n.nContacts(account.contactCount)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _previewAccount(account),
                ),
              );
            }),
          const SizedBox(height: 20),
        ],
        if (_isIOS) ...[
          Text(context.l10n.contactsOnThisIphone, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _addressBookDenied
                        ? context.l10n.ztContactsIsNotAllowed
                        : context.l10n.copiesEverythingTheIphoneContacts,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _previewAddressBook,
                    icon: const Icon(Icons.phone_iphone),
                    label: Text(context.l10n.importFromThisIphone),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        Text(context.l10n.googleContactsExportFile, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Step(
                  number: 1,
                  text: context.l10n.openContactsGoogleComAnd,
                ),
                _Step(
                  number: 2,
                  text: context.l10n.chooseVcardForIosContacts,
                ),
                _Step(number: 3, text: context.l10n.pickThatFileHere),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickExportFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(context.l10n.chooseExportFile),
                ),
              ],
            ),
          ),
        ),
        if (_busyText != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _busyText!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  bool _hasWork(_PendingImport pending) =>
      !pending.plan.isEmpty ||
      pending.newPhotos > 0 ||
      (_downloadLinkedPhotos && pending.newLinkedPhotos > 0);

  Widget _buildPreview(BuildContext context, _PendingImport pending) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final ContactImportPlan plan = pending.plan;
    final List<VaultContact> sample = <VaultContact>[
      ...plan.toAdd,
      ...plan.toUpdate,
    ].take(50).toList();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(context.l10n.readyToImport, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                context.l10n.fromSource(pending.sourceLabel),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _CountTile(
                    label: context.l10n.newLabel,
                    count: plan.toAdd.length,
                    colors: colors,
                  ),
                  const SizedBox(width: 8),
                  _CountTile(
                    label: context.l10n.updated,
                    count: plan.toUpdate.length,
                    colors: colors,
                  ),
                  const SizedBox(width: 8),
                  _CountTile(
                    label: context.l10n.alreadyHere,
                    count: plan.unchangedCount,
                    colors: colors,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                plan.isEmpty
                    ? context.l10n.everythingInThisSourceIs
                    : context.l10n.matchingContactsGet,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              if (pending.newPhotos > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.photo_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.l10n.photosAddedToo(pending.newPhotos),
                      ),
                    ),
                  ],
                ),
              ],
              if (pending.newLinkedPhotos > 0) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _downloadLinkedPhotos,
                  onChanged: _busy
                      ? null
                      : (bool on) => setState(() => _downloadLinkedPhotos = on),
                  title: Text(
                    context.l10n.downloadPhotosFromGoogle(pending.newLinkedPhotos),
                  ),
                  subtitle: Text(
                    context.l10n.thisExportLinksToPhotos,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              ...sample.map((VaultContact contact) {
                final bool isNew = plan.toAdd.contains(contact);
                final String detail = <String>[
                  if (contact.phones.isNotEmpty) contact.phones.first,
                  if (contact.emails.isNotEmpty) contact.emails.first,
                ].join(' · ');
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isNew ? Icons.person_add_alt : Icons.sync_alt,
                    color: colors.primary,
                  ),
                  title: Text(contact.displayName),
                  subtitle: detail.isEmpty ? null : Text(detail),
                  trailing: Text(
                    isNew ? context.l10n.newLabel : context.l10n.update,
                    style: theme.textTheme.labelSmall,
                  ),
                );
              }),
              if (plan.changeCount > sample.length)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.l10n.andNMore(plan.changeCount - sample.length),
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _pending = null),
                    child: Text(context.l10n.back),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy || !_hasWork(pending)
                        ? null
                        : _confirmImport,
                    child: Text(
                      !_hasWork(pending)
                          ? context.l10n.nothingToImport
                          : plan.isEmpty
                          ? context.l10n.importPhotos
                          : context.l10n.importNContacts(plan.changeCount),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingImport {
  _PendingImport({
    required this.sourceLabel,
    required this.incoming,
    required this.plan,
    required this.photos,
    required this.linkedPhotos,
    required this.newPhotos,
    required this.newLinkedPhotos,
  });

  final String sourceLabel;
  final List<VaultContact> incoming;
  final ContactImportPlan plan;

  /// Photos read on the phone (account photos, or embedded in the file).
  final Map<String, PhotoLoader> photos;

  /// Photos the file only links to, fetched only if the user agrees.
  final Map<String, Uri> linkedPhotos;

  /// How many contacts would get a photo they don't have yet.
  final int newPhotos;
  final int newLinkedPhotos;
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: colors.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.noGoogleSignInNeeded,
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            child: Text('$number', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    required this.colors,
  });

  final String label;
  final int count;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text('$count', style: Theme.of(context).textTheme.titleLarge),
            Text(
              label,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
