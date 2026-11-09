import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_banner.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_controller.dart';
import 'package:zerotrust_contacts/pages/google_import_page.dart';
import 'package:zerotrust_contacts/pages/merge_conflicts_page.dart';
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
          title: const Text('Import from Google'),
          subtitle: const Text('Accounts on this phone, or a Google export'),
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
          title: const Text('Export encrypted backup'),
          subtitle: const Text('Copied to the clipboard, sealed with a '
              'passphrase you choose'),
          onTap: () => _exportEncrypted(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.lock_open_outlined),
          title: const Text('Import encrypted backup'),
          onTap: () => _importEncrypted(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.contact_page_outlined),
          title: const Text('Export as vCard'),
          subtitle: const Text('Unencrypted, copied to the clipboard'),
          onTap: () => _exportVCard(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.contact_mail_outlined),
          title: const Text('Import vCard text'),
          onTap: () => _importVCard(context, ref),
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

  Future<void> _exportEncrypted(BuildContext context, WidgetRef ref) async {
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
      await Clipboard.setData(ClipboardData(text: package));
      return 'Encrypted backup copied to the clipboard.';
    });
  }

  Future<void> _importEncrypted(BuildContext context, WidgetRef ref) async {
    final List<String>? values = await showTextInputsDialog(
      context,
      title: 'Import encrypted backup',
      labels: const <String>['Backup text', 'Passphrase'],
      multilineFirst: true,
    );
    if (values == null || !context.mounted) return;
    if (values[0].isEmpty || values[1].isEmpty) {
      _snack(context, 'Paste the backup and enter its passphrase.');
      return;
    }
    await _run(context, () async {
      final int count = await requireRepository(ref).importEncryptedJson(
          encryptedPackage: values[0], passphrase: values[1]);
      return 'Imported $count contacts.';
    });
  }

  Future<void> _exportVCard(BuildContext context, WidgetRef ref) async {
    await _run(context, () async {
      final VaultRepository repo = requireRepository(ref);
      final String vcard = repo.exportVCard(await repo.loadSavedContacts());
      await Clipboard.setData(ClipboardData(text: vcard));
      return 'vCard copied to the clipboard.';
    });
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
