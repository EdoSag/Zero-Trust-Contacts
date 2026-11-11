import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/import/android_account_contacts.dart';
import 'package:zerotrust_contacts/import/contact_file_text.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/import/csv_contacts.dart';
import 'package:zerotrust_contacts/import/ios_address_book.dart';
import 'package:zerotrust_contacts/import/photo_downloader.dart';
import 'package:zerotrust_contacts/import/sim_contacts.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// "Import contacts" in a few taps.
///
/// None of the ways in signs in to Google, Apple or Microsoft or sends
/// contacts anywhere: read an account already on this phone (Google,
/// Samsung, Outlook/Exchange, the phone itself), the SIM card, the iPhone
/// address book, or an export file (vCard from Google, iCloud or Outlook;
/// CSV from Google, Outlook or a spreadsheet). Contacts are parsed on the
/// device and written straight into the encrypted vault.
class ImportContactsPage extends ConsumerStatefulWidget {
  const ImportContactsPage({
    super.key,
    this.fileText,
    this.fileName,
    this.isIOS,
    this.addressBook = const IosAddressBook(),
  });

  /// Whether to offer the iPhone address book. Null asks the platform.
  final bool? isIOS;

  /// Reads the iPhone address book; replaced in tests.
  final IosAddressBook addressBook;

  /// A vCard or CSV file to preview straight away (a .vcf file opened with
  /// or shared to the app, a scanned QR code, a file picked in Settings).
  /// The page then only shows that preview.
  final String? fileText;

  /// Where [fileText] came from, for the preview and the activity log.
  final String? fileName;

  @override
  ConsumerState<ImportContactsPage> createState() => _ImportContactsPageState();
}

class _ImportContactsPageState extends ConsumerState<ImportContactsPage> {
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
    final String? text = widget.fileText;
    if (text == null) {
      _loadAccounts();
    } else {
      _loadingAccounts = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _withBusy(
          context.l10n.reading,
          () => _previewFile(text, widget.fileName ?? 'vCard'),
        );
      });
    }
  }

  bool get _fileOnly => widget.fileText != null;

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
          .loadAllImportAccounts();
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
    final String title = _accountTitle(account);
    await _withBusy(context.l10n.readingName(title), () async {
      final List<Map<String, dynamic>> rows = await _deviceService
          .loadAccountContacts(account.name, accountType: account.type);
      final AccountImport read = accountImportFromFields(rows);
      await _preparePreview(
        sourceLabel: title,
        logLabel: account.kind == ImportAccountKind.google
            ? 'Google (${account.name})'
            : account.name.isEmpty
            ? _kindLabel(account.kind)
            : '${_kindLabel(account.kind)} (${account.name})',
        fromGoogle: account.kind == ImportAccountKind.google,
        incoming: read.contacts,
        photos: <String, PhotoLoader>{
          for (final MapEntry<String, int> e in read.photoRawIds.entries)
            e.key: () => _deviceService.loadRawContactPhoto(e.value),
        },
      );
    });
  }

  /// Reads the contacts saved on the SIM card itself (Android).
  Future<void> _previewSim() async {
    await _withBusy(context.l10n.readingSimCard, () async {
      final bool granted = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(_deviceService.requestPermission);
      if (!granted) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
      final List<VaultContact> contacts = vaultContactsFromSim(
        await _deviceService.loadSimContacts(),
      );
      if (contacts.isEmpty) {
        throw StateError(currentL10n.noContactsOnSim);
      }
      await _preparePreview(
        sourceLabel: currentL10n.simCard,
        logLabel: 'SIM card',
        incoming: contacts,
      );
    });
  }

  String _kindLabel(ImportAccountKind kind) => switch (kind) {
    ImportAccountKind.google => context.l10n.accountKindGoogle,
    ImportAccountKind.sim => context.l10n.simCard,
    ImportAccountKind.exchange => context.l10n.accountKindExchange,
    ImportAccountKind.samsung => context.l10n.accountKindSamsung,
    ImportAccountKind.phone => context.l10n.accountKindPhone,
    ImportAccountKind.other => context.l10n.accountKindOther,
  };

  /// The account's name, or what kind it is when it has none.
  String _accountTitle(ImportAccount account) =>
      account.name.isEmpty ? _kindLabel(account.kind) : account.name;

  IconData _kindIcon(ImportAccountKind kind) => switch (kind) {
    ImportAccountKind.sim => Icons.sim_card_outlined,
    ImportAccountKind.exchange => Icons.business_outlined,
    ImportAccountKind.phone => Icons.smartphone,
    _ => Icons.account_circle_outlined,
  };

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
      await _previewFile(decodeContactFile(bytes), file.name);
    });
  }

  /// Previews a vCard (.vcf) or spreadsheet (.csv) file, whichever [text]
  /// turns out to be.
  Future<void> _previewFile(String text, String name) async {
    switch (detectContactFileKind(text)) {
      case ContactFileKind.vCard:
        await _previewVCard(text, name);
      case ContactFileKind.csv:
        final CsvContactsImport parsed = const CsvContactsParser().parse(text);
        if (parsed.contacts.isEmpty) {
          throw StateError(currentL10n.thatFileIsNotA);
        }
        final String format = switch (parsed.format) {
          CsvContactFormat.google => 'Google CSV',
          CsvContactFormat.outlook => 'Outlook CSV',
          CsvContactFormat.generic => 'CSV',
        };
        await _preparePreview(
          sourceLabel: '$name ($format)',
          incoming: parsed.contacts,
        );
      case ContactFileKind.unknown:
        throw StateError(currentL10n.thatFileIsNotA);
    }
  }

  Future<void> _previewVCard(String text, String name) async {
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
    String? logLabel,
    bool fromGoogle = false,
    required List<VaultContact> incoming,
    Map<String, PhotoLoader> photos = const <String, PhotoLoader>{},
    Map<String, Uri> linkedPhotos = const <String, Uri>{},
  }) async {
    if (incoming.isEmpty) {
      throw StateError(currentL10n.noContactsFoundIn(sourceLabel));
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
          logLabel: logLabel ?? sourceLabel,
          fromGoogle: fromGoogle,
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
        sourceLabel: pending.logLabel,
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
      ).showSnackBar(SnackBar(content: Text(_summary(done, pending))));
      Navigator.of(context).pop(true);
    });
  }

  String _summary(ContactImportPlan plan, _PendingImport pending) {
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
    return pending.fromGoogle
        ? context.l10n.importedFromGoogleSummary(details)
        : _fromThisPhone
        ? context.l10n.importedFromIphoneSummary(details)
        : context.l10n.importedSummary(details);
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
      canPop: _pending == null || _busy || _fileOnly,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && !_busy) {
          setState(() => _pending = null);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.importContacts),
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _pending == null
                  ? (_fileOnly
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _busy
                                    ? context.l10n.reading
                                    : widget.fileName == null
                                          ? context.l10n.nothingToImportFromFile
                                          : context.l10n.nothingToImportFrom(widget.fileName!),
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
            context.l10n.accountsOnThisPhone,
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
                subtitle: Text(context.l10n.neededToReadPhoneAccounts),
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
                title: Text(context.l10n.noOtherContactsOnThisPhone),
                subtitle: Text(context.l10n.addAccountOrUseFile),
              ),
            )
          else
            ..._accounts.map((ImportAccount account) {
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      _kindIcon(account.kind),
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  title: Text(_accountTitle(account)),
                  subtitle: Text(
                    account.name.isEmpty
                        ? context.l10n.nContacts(account.contactCount)
                        : '${_kindLabel(account.kind)} · '
                              '${context.l10n.nContacts(account.contactCount)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _previewAccount(account),
                ),
              );
            }),
          const SizedBox(height: 20),
          Text(context.l10n.simCard, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.simCardHelp),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _previewSim,
                    icon: const Icon(Icons.sim_card_outlined),
                    label: Text(context.l10n.importFromSimCard),
                  ),
                ],
              ),
            ),
          ),
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
        Text(context.l10n.fromAnExportFile, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.fromAnExportFileHelp),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _pickExportFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(context.l10n.chooseFile),
                ),
                const SizedBox(height: 4),
                _HowToExport(
                  title: context.l10n.exportHelpGoogleTitle,
                  steps: context.l10n.exportHelpGoogle,
                ),
                _HowToExport(
                  title: context.l10n.exportHelpIcloudTitle,
                  steps: context.l10n.exportHelpIcloud,
                ),
                _HowToExport(
                  title: context.l10n.exportHelpOutlookTitle,
                  steps: context.l10n.exportHelpOutlook,
                ),
                _HowToExport(
                  title: context.l10n.exportHelpSpreadsheetTitle,
                  steps: context.l10n.exportHelpSpreadsheet,
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
    required this.logLabel,
    required this.fromGoogle,
    required this.incoming,
    required this.plan,
    required this.photos,
    required this.linkedPhotos,
    required this.newPhotos,
    required this.newLinkedPhotos,
  });

  final String sourceLabel;

  /// Where the contacts came from, in the activity log (kept in English).
  final String logLabel;

  /// Read from a Google account on this phone.
  final bool fromGoogle;
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

/// "How do I get this file from Google / iCloud / Outlook?", folded away
/// until tapped.
class _HowToExport extends StatelessWidget {
  const _HowToExport({required this.title, required this.steps});

  final String title;
  final String steps;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsetsDirectional.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(title),
      children: [Text(steps)],
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
