import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

@NowaGenerated()
class MergeConflictsPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const MergeConflictsPage({super.key});

  @override
  State<MergeConflictsPage> createState() => _MergeConflictsPageState();
}

class _MergeConflictsPageState extends State<MergeConflictsPage> {
  final VaultRepository _vaultRepository = VaultRepository();

  bool _loading = true;
  List<ContactMergeConflict> _conflicts = <ContactMergeConflict>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<ContactMergeConflict> conflicts =
        await _vaultRepository.readPendingConflicts();
    if (!mounted) {
      return;
    }
    setState(() {
      _conflicts = conflicts;
      _loading = false;
    });
  }

  Future<void> _resolve(
      ContactMergeConflict conflict, VaultContact selected) async {
    await _vaultRepository.resolveConflict(
      contactId: conflict.contactId,
      resolvedContact: selected,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge Conflicts'),
        actions: [
          TextButton(
            onPressed: _conflicts.isEmpty
                ? null
                : () async {
                    for (final ContactMergeConflict conflict in _conflicts) {
                      await _resolve(conflict, conflict.merged);
                    }
                  },
            child: const Text('Auto resolve'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conflicts.isEmpty
              ? const Center(
                  child: Text('No pending conflicts'),
                )
              : ListView.builder(
                  itemCount: _conflicts.length,
                  itemBuilder: (BuildContext context, int index) {
                    final ContactMergeConflict conflict = _conflicts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conflict.merged.displayName,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Local: ${conflict.local.updatedAt.toLocal()}',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant),
                            ),
                            Text(
                              'Cloud: ${conflict.remote.updatedAt.toLocal()}',
                              style: TextStyle(
                                  color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () =>
                                      _resolve(conflict, conflict.local),
                                  child: const Text('Keep local'),
                                ),
                                OutlinedButton(
                                  onPressed: () =>
                                      _resolve(conflict, conflict.remote),
                                  child: const Text('Keep cloud'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      _resolve(conflict, conflict.merged),
                                  child: const Text('Use merged'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
