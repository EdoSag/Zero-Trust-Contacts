import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_banner.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_controller.dart';
import 'package:zerotrust_contacts/pages/google_import_page.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/merge_conflicts_page.dart';
import 'package:zerotrust_contacts/pages/qr_scan_page.dart';
import 'package:zerotrust_contacts/pages/trash_page.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_controller.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_page.dart';
import 'package:zerotrust_contacts/pages/vault_history_page.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

/// The shared Zero-Trust settings screen, with Contacts' own rows: Google
/// import, restore points, sync conflicts, activity, and backups.
class ContactsSettingsPage extends ConsumerWidget {
  const ContactsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int conflicts = ref.watch(
        ztSyncControllerProvider.select((SyncStatus s) => s.conflicts.length));
    final bool legacyPending =
        ref.watch(legacyImportProvider) == LegacyImportStatus.needsPassword;

    final PhoneSyncStatus phoneSync = ref.watch(phoneSyncProvider);
    final bool phoneSyncSupported =
        ref.watch(phoneContactsBridgeProvider).isSupported;

    void push(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));

    return ZtSettingsPage(
      showSyncStatus: true,
      onSignedOut: () =>
          Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst),
      onOpenUrl: (Uri url) =>
          launchUrl(url, mode: LaunchMode.externalApplication),
      appSection: <Widget>[
        if (legacyPending)
          ListTile(
            leading: const Icon(Icons.move_down_outlined),
            title: const Text('Bring over contacts from before the update'),
            subtitle: const Text('Needs your password from before, once'),
            onTap: () => showLegacyImportDialog(context),
          ),
        if (phoneSyncSupported)
          ListTile(
            leading: const Icon(Icons.phone_in_talk_outlined),
            title: const Text('Show in Phone and Messages'),
            subtitle: Text(phoneSync.enabled
                ? 'On: caller ID and the dialer show your contacts'
                : 'Off: calls from contacts show only the number'),
            onTap: () => push(const PhoneSyncPage()),
          ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(defaultTargetPlatform == TargetPlatform.iOS
              ? 'Import contacts'
              : 'Import from Google'),
          subtitle: Text(defaultTargetPlatform == TargetPlatform.iOS
              ? 'From this iPhone, or a Google export'
              : 'Accounts on this phone, or a Google export'),
          onTap: () => push(const GoogleImportPage()),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Trash'),
          subtitle: const Text('Deleted contacts, kept for 30 days'),
          onTap: () => push(const TrashPage()),
        ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore points'),
          subtitle: const Text('Undo an import, merge or restore'),
          onTap: () => push(const RestorePointsPage()),
        ),
        ListTile(
          leading: const Icon(Icons.call_split_outlined),
          title: const Text('Sync conflicts'),
          subtitle: Text(conflicts == 0
              ? 'None'
              : '$conflicts ${conflicts == 1 ? 'edit' : 'edits'} replaced '
                  'by a newer one from another device'),
          onTap: () => push(const MergeConflictsPage()),
        ),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('Activity on this device'),
          onTap: () => push(const ActivityPage()),
        ),
      ],
      backupSection: <Widget>[
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Save an encrypted backup'),
          subtitle: const Text('A file sealed with a passphrase you choose'),
          onTap: () => _exportEncrypted(context, ref, toFile: true),
          trailing: IconButton(
            tooltip: 'Copy to the clipboard instead',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _exportEncrypted(context, ref, toFile: false),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Restore an encrypted backup'),
          subtitle: const Text('From a backup file'),
          onTap: () => _importEncrypted(context, ref, fromFile: true),
          trailing: IconButton(
            tooltip: 'Paste the backup text instead',
            icon: const Icon(Icons.paste_outlined),
            onPressed: () => _importEncrypted(context, ref, fromFile: false),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.contact_page_outlined),
          title: const Text('Export contacts as a vCard file'),
          subtitle: const Text(
              'Not encrypted. Works with Google, Apple and other apps'),
          onTap: () => _exportVCard(context, ref, toFile: true),
          trailing: IconButton(
            tooltip: 'Copy to the clipboard instead',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _exportVCard(context, ref, toFile: false),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.contact_mail_outlined),
          title: const Text('Import a vCard file'),
          subtitle: const Text('A .vcf file from any contacts app'),
          onTap: () => _importVCardFile(context, ref),
          trailing: IconButton(
            tooltip: 'Paste vCard text instead',
            icon: const Icon(Icons.paste_outlined),
            onPressed: () => _importVCard(context, ref),
          ),
        ),
        if (QrScanPage.isSupported)
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan a contact QR code'),
            subtitle: const Text('Add a contact someone shows you'),
            onTap: () => QrScanPage.scanAndImport(context),
          ),
      ],
    );
  }

  static void _snack(BuildContext context, String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  static Future<void> _run(BuildContext context,
      Future<String> Function() action) async {
    try {
      final String message = await action();
      if (context.mounted) _snack(context, message);
    } on Object catch (error) {
      if (context.mounted) {
        _snack(context, error is StateError ? error.message : '$error');
      }
    }
  }

  static String _today() {
    final DateTime now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  /// Asks where to save [text] as a file. False when cancelled.
  static Future<bool> _saveFile(
    WidgetRef ref, {
    required String name,
    required String mimeType,
    required String text,
  }) async {
    final Uri? saved = await ref
        .read(vaultControllerProvider.notifier)
        .whileShowingSystemUi(() => FilePicker.saveFile(
              fileName: name,
              mimeType: mimeType,
              bytes: Uint8List.fromList(utf8.encode(text)),
            ));
    return saved != null;
  }

  /// Lets the user pick a file and returns its name and text.
  static Future<(String, String)?> _pickTextFile(WidgetRef ref) async {
    final PlatformFile? file = await ref
        .read(vaultControllerProvider.notifier)
        .whileShowingSystemUi(() => FilePicker.pickFile(type: FileType.any));
    if (file == null) {
      return null;
    }
    final Uint8List bytes = await file.xFile.readAsBytes();
    return (file.name, utf8.decode(bytes, allowMalformed: true));
  }

  Future<void> _exportEncrypted(BuildContext context, WidgetRef ref,
      {required bool toFile}) async {
    final List<String>? values = await showTextInputsDialog(
      context,
      title: 'Export encrypted backup',
      labels: const <String>['Passphrase (8+ characters)'],
      obscure: true,
    );
    if (values == null || !context.mounted) return;
    if (values[0].length < 8) {
      _snack(context, 'The passphrase needs at least 8 characters.');
      return;
    }
    await _run(context, () async {
      final VaultRepository repo = requireRepository(ref);
      final String package =
          await repo.exportEncryptedJson(passphrase: values[0]);
      if (!toFile) {
        await Clipboard.setData(ClipboardData(text: package));
        return 'Encrypted backup copied to the clipboard.';
      }
      final bool saved = await _saveFile(
        ref,
        name: 'zt-contacts-backup-${_today()}.ztbackup',
        mimeType: 'application/octet-stream',
        text: package,
      );
      return saved ? 'Encrypted backup saved.' : 'Nothing was saved.';
    });
  }

  Future<void> _importEncrypted(BuildContext context, WidgetRef ref,
      {required bool fromFile}) async {
    String? backup;
    if (fromFile) {
      try {
        backup = (await _pickTextFile(ref))?.$2.trim();
      } on Object catch (error) {
        if (context.mounted) _snack(context, 'Couldn\'t read that file: $error');
        return;
      }
      if (backup == null || !context.mounted) return;
    }
    final List<String>? values = await showTextInputsDialog(
      context,
      title: 'Restore encrypted backup',
      labels: <String>[if (!fromFile) 'Backup text', 'Passphrase'],
      multilineFirst: !fromFile,
      obscure: fromFile,
    );
    if (values == null || !context.mounted) return;
    final String text = backup ?? values.first;
    final String passphrase = values.last;
    if (text.isEmpty || passphrase.isEmpty) {
      _snack(context, 'The backup and its passphrase are both needed.');
      return;
    }
    await _run(context, () async {
      final int count = await requireRepository(ref).importEncryptedJson(
          encryptedPackage: text, passphrase: passphrase);
      return 'Imported $count contacts.';
    });
  }

  Future<void> _exportVCard(BuildContext context, WidgetRef ref,
      {required bool toFile}) async {
    await _run(context, () async {
      final VaultRepository repo = requireRepository(ref);
      final List<VaultContact> contacts = await repo.loadSavedContacts();
      if (contacts.isEmpty) {
        return 'There are no contacts to export yet.';
      }
      final String vcard = repo.exportVCard(contacts);
      if (!toFile) {
        await Clipboard.setData(ClipboardData(text: vcard));
        return 'vCard copied to the clipboard.';
      }
      final bool saved = await _saveFile(
        ref,
        name: 'zt-contacts-${_today()}.vcf',
        mimeType: 'text/x-vcard',
        text: vcard,
      );
      if (saved) {
        await repo.logActivity('contacts_export_vcard',
            details: 'Exported ${contacts.length} contacts as a vCard file');
      }
      return saved
          ? '${contacts.length} contacts saved as a vCard file.'
          : 'Nothing was saved.';
    });
  }

  /// Picks a .vcf file and shows what importing it would do first.
  Future<void> _importVCardFile(BuildContext context, WidgetRef ref) async {
    try {
      final (String, String)? file = await _pickTextFile(ref);
      if (file == null || !context.mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<bool>(
        builder: (_) =>
            GoogleImportPage(vCardText: file.$2, vCardName: file.$1),
      ));
    } on Object catch (error) {
      if (context.mounted) _snack(context, 'Couldn\'t read that file: $error');
    }
  }

  Future<void> _importVCard(BuildContext context, WidgetRef ref) async {
    final List<String>? values = await showTextInputsDialog(
      context,
      title: 'Import vCard',
      labels: const <String>['Paste vCard text'],
      multilineFirst: true,
    );
    if (values == null || values[0].isEmpty || !context.mounted) return;
    await _run(context, () async {
      final int count = await requireRepository(ref).importVCard(values[0]);
      return 'Imported $count contacts from the vCard.';
    });
  }
}

/// Asks for one or more text values. Null when cancelled.
Future<List<String>?> showTextInputsDialog(
  BuildContext context, {
  required String title,
  required List<String> labels,
  bool multilineFirst = false,
  bool obscure = false,
}) async {
  final List<TextEditingController> controllers = <TextEditingController>[
    for (final String _ in labels) TextEditingController(),
  ];
  final List<String>? result = await showDialog<List<String>>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < labels.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: TextField(
                  controller: controllers[i],
                  autofocus: i == 0,
                  obscureText: obscure || (i > 0 && multilineFirst),
                  maxLines: i == 0 && multilineFirst ? 8 : 1,
                  minLines: i == 0 && multilineFirst ? 4 : 1,
                  decoration: InputDecoration(labelText: labels[i]),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(<String>[
            for (final TextEditingController c in controllers) c.text.trim(),
          ]),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  for (final TextEditingController c in controllers) {
    c.dispose();
  }
  return result;
}
