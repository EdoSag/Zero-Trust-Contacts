import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zerotrust_contacts/l10n/l10n.dart';

String _when(DateTime at) {
  final DateTime t = at.toLocal();
  return DateFormat.yMMMd().add_Hm().format(t);
}

/// Restore points kept on this device: taken before imports, merges,
/// deletes and restores, plus daily and weekly ones.
class RestorePointsPage extends ConsumerStatefulWidget {
  const RestorePointsPage({super.key});

  @override
  ConsumerState<RestorePointsPage> createState() => _RestorePointsPageState();
}

class _RestorePointsPageState extends ConsumerState<RestorePointsPage> {
  List<VaultSnapshot>? _snapshots;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<VaultSnapshot> snapshots =
        await requireRepository(ref).readSnapshots();
    if (mounted) setState(() => _snapshots = snapshots);
  }

  Future<void> _busyRun(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final String message = await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(VaultSnapshot snapshot) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.restoreThisPoint),
        content: Text(
          context.l10n.restorePointExplained(_when(snapshot.createdAt), snapshot.contacts.length),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.restore)),
        ],
      ),
    );
    if (ok != true) return;
    await _busyRun(() async {
      final int count =
          await requireRepository(ref).restoreSnapshot(snapshot.id);
      return currentL10n.restoredN(count);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultSnapshot>? snapshots = _snapshots;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.restorePoints),
        actions: <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => _busyRun(() async {
                      await requireRepository(ref)
                          .createSnapshot(reason: 'Manual restore point');
                      return currentL10n.restorePointSaved;
                    }),
            child: Text(context.l10n.saveNow),
          ),
        ],
      ),
      body: snapshots == null
          ? const Center(child: CircularProgressIndicator())
          : snapshots.isEmpty
              ? Center(child: Text(context.l10n.noRestorePointsYet))
              : ListView(
                  children: <Widget>[
                    for (final VaultSnapshot s in snapshots)
                      ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: Text(restorePointLabel(s.reason)),
                        subtitle: Text(
                            '${_when(s.createdAt)} · ${context.l10n.nContacts(s.contacts.length)}'),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _restore(s),
                          child: Text(context.l10n.restore),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// What happened in the vault on this device.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.activityOnThisDevice)),
      body: FutureBuilder<List<SecurityActivityEntry>>(
        future: requireRepository(ref).readActivityEntries(),
        builder: (BuildContext context,
            AsyncSnapshot<List<SecurityActivityEntry>> snap) {
          final List<SecurityActivityEntry>? entries = snap.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return Center(child: Text(context.l10n.noActivityYet));
          }
          return ListView(
            children: <Widget>[
              for (final SecurityActivityEntry e in entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    e.isError ? Icons.error_outline : Icons.shield_outlined,
                    color: e.isError ? colors.error : colors.primary,
                  ),
                  title: Text(e.details.isEmpty ? e.action : e.details),
                  subtitle: Text(_when(e.createdAt)),
                ),
            ],
          );
        },
      ),
    );
  }
}
