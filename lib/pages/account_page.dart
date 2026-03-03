import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

@NowaGenerated()
class AccountPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final AuthService _authService = AuthService();
  final VaultRepository _vaultRepository = VaultRepository();

  bool _busy = false;
  String? _error;

  List<VaultSnapshot> _snapshots = <VaultSnapshot>[];
  List<SecurityActivityEntry> _activity = <SecurityActivityEntry>[];
  List<ContactMergeConflict> _conflicts = <ContactMergeConflict>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final List<VaultSnapshot> snapshots =
        await _vaultRepository.readSnapshots(limit: 12);
    final List<SecurityActivityEntry> activity =
        await _vaultRepository.readActivityEntries(limit: 20);
    final List<ContactMergeConflict> conflicts =
        await _vaultRepository.readPendingConflicts();
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshots = snapshots;
      _activity = activity;
      _conflicts = conflicts;
    });
  }

  Future<void> _runTask(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _loadData();
    } catch (error) {
      final String message = error.toString().replaceFirst('Exception: ', '');
      _showSnack(message);
      if (mounted) {
        setState(() {
          _error = message;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showSnack(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String?> _showSingleInputDialog({
    required String title,
    required String label,
    bool multiline = false,
  }) async {
    final TextEditingController controller = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: multiline ? 8 : 1,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<List<String>?> _showTwoInputsDialog({
    required String title,
    required String firstLabel,
    required String secondLabel,
    bool firstMultiline = false,
  }) async {
    final TextEditingController first = TextEditingController();
    final TextEditingController second = TextEditingController();
    final List<String>? value = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: first,
                  maxLines: firstMultiline ? 8 : 1,
                  minLines: firstMultiline ? 4 : 1,
                  decoration: InputDecoration(labelText: firstLabel),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: second,
                  decoration: InputDecoration(labelText: secondLabel),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                <String>[first.text.trim(), second.text.trim()],
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    first.dispose();
    second.dispose();
    return value;
  }

  Future<void> _handleSyncNow() async {
    await _runTask(() async {
      final SyncResult result =
          await _vaultRepository.syncWithCloud(auto: false);
      _showSnack(
        'Merged ${result.mergedCount} contacts. Conflicts: ${result.conflicts.length}',
      );
    });
  }

  Future<void> _handlePushLocal() async {
    await _runTask(() async {
      final int pushed = await _vaultRepository.pushLocalToCloud();
      _showSnack('Pushed $pushed contacts to cloud.');
    });
  }

  Future<void> _handlePullCloud() async {
    await _runTask(() async {
      final int pulled = await _vaultRepository.pullCloudToLocal();
      _showSnack('Pulled $pulled contacts from cloud.');
    });
  }

  Future<void> _handleExportEncrypted() async {
    final String? passphrase = await _showSingleInputDialog(
      title: 'Export encrypted JSON',
      label: 'Passphrase',
    );
    if (passphrase == null || passphrase.length < 8) {
      _showSnack('Passphrase must be at least 8 characters.');
      return;
    }
    await _runTask(() async {
      final String package =
          await _vaultRepository.exportEncryptedJson(passphrase: passphrase);
      await Clipboard.setData(ClipboardData(text: package));
      _showSnack('Encrypted export copied to clipboard.');
    });
  }

  Future<void> _handleImportEncrypted() async {
    final List<String>? inputs = await _showTwoInputsDialog(
      title: 'Import encrypted JSON',
      firstLabel: 'Encrypted package JSON',
      secondLabel: 'Passphrase',
      firstMultiline: true,
    );
    if (inputs == null) {
      return;
    }
    if (inputs[0].isEmpty || inputs[1].isEmpty) {
      _showSnack('Both package JSON and passphrase are required.');
      return;
    }
    await _runTask(() async {
      final int imported = await _vaultRepository.importEncryptedJson(
        encryptedPackage: inputs[0],
        passphrase: inputs[1],
      );
      _showSnack('Imported $imported contacts.');
    });
  }

  Future<void> _handleExportVCard() async {
    await _runTask(() async {
      final contacts = await _vaultRepository.loadSavedContacts();
      final String vcard = _vaultRepository.exportVCard(contacts);
      await Clipboard.setData(ClipboardData(text: vcard));
      _showSnack('vCard export copied to clipboard.');
    });
  }

  Future<void> _handleImportVCard() async {
    final String? vcard = await _showSingleInputDialog(
      title: 'Import vCard',
      label: 'Paste vCard text',
      multiline: true,
    );
    if (vcard == null || vcard.isEmpty) {
      return;
    }
    await _runTask(() async {
      final int imported = await _vaultRepository.importVCard(vcard);
      _showSnack('Imported $imported contacts from vCard.');
    });
  }

  Future<void> _handleCreateSnapshot() async {
    await _runTask(() async {
      final VaultSnapshot snapshot = await _vaultRepository.createSnapshot(
        reason: 'Manual restore point',
      );
      _showSnack('Created snapshot ${snapshot.id}.');
    });
  }

  Future<void> _handleRestoreSnapshot(String snapshotId) async {
    await _runTask(() async {
      final int restored = await _vaultRepository.restoreSnapshot(snapshotId);
      _showSnack('Restored $restored contacts.');
    });
  }

  Future<void> _handleSignOut() async {
    await _runTask(() async {
      if (SupabaseService().currentUser != null) {
        await _authService.signOut();
      }
      if (mounted) {
        context.go('/onboarding');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String email =
        SupabaseService().currentUser?.email ?? 'No active session';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & Vault'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(),
              ),
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: const Text('Signed in as'),
                subtitle: Text(email),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _handleSyncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _handlePushLocal,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Push local'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _handlePullCloud,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Pull cloud'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await context.push('/merge-conflicts');
                          await _loadData();
                        },
                  icon: const Icon(Icons.merge_type_outlined),
                  label: Text('Conflicts (${_conflicts.length})'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Import / Export', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _busy ? null : _handleExportEncrypted,
                          child: const Text('Export encrypted JSON'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : _handleImportEncrypted,
                          child: const Text('Import encrypted JSON'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : _handleExportVCard,
                          child: const Text('Export vCard'),
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : _handleImportVCard,
                          child: const Text('Import vCard'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Restore points',
                            style: theme.textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: _busy ? null : _handleCreateSnapshot,
                          child: const Text('Create snapshot'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (_snapshots.isEmpty)
                      Text(
                        'No snapshots yet',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ..._snapshots.map((VaultSnapshot snapshot) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(snapshot.reason),
                        subtitle: Text(
                          '${snapshot.cadence.toUpperCase()}  ${snapshot.createdAt.toLocal()}',
                        ),
                        trailing: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _handleRestoreSnapshot(snapshot.id),
                          child: const Text('Restore'),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Security activity',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_activity.isEmpty)
                      Text(
                        'No activity yet',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ..._activity.map((SecurityActivityEntry entry) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          entry.isError
                              ? Icons.error_outline
                              : Icons.shield_outlined,
                          color: entry.isError
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        title: Text(entry.action),
                        subtitle: Text(
                          '${entry.createdAt.toLocal()}${entry.details.isNotEmpty ? ' • ${entry.details}' : ''}',
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _handleSignOut,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
