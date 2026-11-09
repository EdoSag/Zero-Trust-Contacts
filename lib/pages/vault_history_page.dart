import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

String _when(DateTime at) {
  final DateTime t = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
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
        title: const Text('Restore this point?'),
        content: Text(
          'Your contacts go back to how they were on '
          '${_when(snapshot.createdAt)} (${snapshot.contacts.length} '
          'contacts), on every device. A restore point of the current state '
          'is taken first, so you can undo this.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await _busyRun(() async {
      final int count =
          await requireRepository(ref).restoreSnapshot(snapshot.id);
      return 'Restored $count contacts.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultSnapshot>? snapshots = _snapshots;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restore points'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy
                ? null
                : () => _busyRun(() async {
                      await requireRepository(ref)
                          .createSnapshot(reason: 'Manual restore point');
                      return 'Restore point saved.';
                    }),
            child: const Text('Save now'),
          ),
        ],
      ),
      body: snapshots == null
          ? const Center(child: CircularProgressIndicator())
          : snapshots.isEmpty
              ? const Center(child: Text('No restore points yet.'))
              : ListView(
                  children: <Widget>[
                    for (final VaultSnapshot s in snapshots)
                      ListTile(
                        leading: const Icon(Icons.restore_outlined),
                        title: Text(s.reason),
                        subtitle: Text(
                            '${_when(s.createdAt)} · ${s.contacts.length} contacts'),
                        trailing: TextButton(
                          onPressed: _busy ? null : () => _restore(s),
                          child: const Text('Restore'),
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
      appBar: AppBar(title: const Text('Activity on this device')),
      body: FutureBuilder<List<SecurityActivityEntry>>(
        future: requireRepository(ref).readActivityEntries(),
        builder: (BuildContext context,
            AsyncSnapshot<List<SecurityActivityEntry>> snap) {
          final List<SecurityActivityEntry>? entries = snap.data;
          if (entries == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entries.isEmpty) {
            return const Center(child: Text('No activity yet.'));
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
