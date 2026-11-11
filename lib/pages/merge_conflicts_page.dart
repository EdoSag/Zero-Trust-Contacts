import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/compact_button_style.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// Edits made on this device that were replaced by a newer edit of the same
/// contact from another device. The newer edit is what's saved; here the
/// user can bring theirs back, or combine the two field by field.
class MergeConflictsPage extends ConsumerStatefulWidget {
  const MergeConflictsPage({super.key});

  @override
  ConsumerState<MergeConflictsPage> createState() => _MergeConflictsPageState();
}

class _MergeConflictsPageState extends ConsumerState<MergeConflictsPage> {
  final Set<String> _handled = <String>{};

  Future<void> _resolve(
      List<ContactConflict> all, ContactConflict conflict, VaultContact? keep) async {
    if (keep != null) {
      await requireRepository(ref).resolveConflict(keep);
    }
    setState(() => _handled.add(conflict.contactId));
    if (all.every((ContactConflict c) => _handled.contains(c.contactId))) {
      ref.read(ztSyncControllerProvider.notifier).clearConflicts();
      _handled.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SyncStatus status = ref.watch(ztSyncControllerProvider);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.syncConflicts)),
      body: FutureBuilder<List<ContactConflict>>(
        future: requireRepository(ref).conflictsFrom(status),
        builder: (BuildContext context,
            AsyncSnapshot<List<ContactConflict>> snap) {
          final List<ContactConflict>? all = snap.data;
          if (all == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<ContactConflict> open = all
              .where((ContactConflict c) => !_handled.contains(c.contactId))
              .toList();
          if (open.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  context.l10n.noConflictsWhenTheSame,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: <Widget>[
              for (final ContactConflict c in open)
                Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(c.mine.displayName,
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          c.current == null
                              ? context.l10n.deletedOnAnotherDeviceAfter
                              : context.l10n.editedOnAnotherDeviceAfter,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton(
                              style: compactButtonStyle,
                              onPressed: () => _resolve(all, c, null),
                              child: Text(c.current == null
                                  ? context.l10n.keepDeleted
                                  : context.l10n.keepTheNewerOne),
                            ),
                            OutlinedButton(
                              style: compactButtonStyle,
                              onPressed: () => _resolve(all, c, c.mine),
                              child: Text(context.l10n.useMine),
                            ),
                            if (c.current != null)
                              FilledButton(
                                style: compactButtonStyle,
                                onPressed: () => _resolve(
                                    all, c, c.current!.mergeWith(c.mine)),
                                child: Text(context.l10n.combine),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
