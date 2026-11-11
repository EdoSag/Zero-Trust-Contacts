import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/contacts_collection.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// Deleted contacts, kept for 30 days so they can be put back. Synced: a
/// contact deleted on one phone shows up here on every phone.
class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key});

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  late final VaultRepository _repo = requireRepository(ref);
  StreamSubscription<Set<String>>? _changes;
  List<TrashedContact>? _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _changes = _repo.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final List<TrashedContact> items = await _repo.loadTrash();
    if (mounted) setState(() => _items = items);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final String message = await action();
      await _load();
      if (mounted) _snack(message);
    } on Object catch (error) {
      if (mounted) _snack(currentL10n.thatDidntWork('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action)),
          ],
        ),
      ) ==
      true;

  Future<void> _restore(TrashedContact item) => _run(() async {
        await _repo.restoreFromTrash(item.contact.id);
        return currentL10n.isBackInContacts(item.contact.displayName);
      });

  Future<void> _deleteForever(TrashedContact item) async {
    if (!await _confirm(
        context.l10n.deleteForGood,
        context.l10n.deletedEverywhereName(item.contact.displayName),
        context.l10n.delete)) {
      return;
    }
    await _run(() async {
      await _repo.deleteForever(item.contact.id);
      return currentL10n.deletedForGood;
    });
  }

  Future<void> _emptyTrash() async {
    final int count = _items?.length ?? 0;
    if (count == 0 ||
        !await _confirm(
            context.l10n.emptyTheTrash,
            context.l10n.deletedEverywhereN(count),
            context.l10n.emptyTrash)) {
      return;
    }
    await _run(() async {
      final int done = await _repo.emptyTrash();
      return currentL10n.deletedNForGood(done);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<TrashedContact>? items = _items;
    final DateTime now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.trash),
        actions: <Widget>[
          if (items != null && items.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _emptyTrash,
              child: Text(context.l10n.emptyTrash),
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      context.l10n.theTrashIsEmptyDeleted,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(context.l10n.contactsInTheTrashAre),
                    ),
                    for (final TrashedContact item in items)
                      ListTile(
                        leading: ContactAvatar(contact: item.contact),
                        title: Text(item.contact.displayName),
                        subtitle: Text(_daysLeftText(item.daysLeft(now))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: context.l10n.restore,
                              onPressed: _busy ? null : () => _restore(item),
                              icon: const Icon(Icons.restore_from_trash),
                            ),
                            IconButton(
                              tooltip: context.l10n.deleteForGoodX,
                              onPressed:
                                  _busy ? null : () => _deleteForever(item),
                              icon: const Icon(Icons.delete_forever_outlined),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  static String _daysLeftText(int days) => switch (days) {
        0 => currentL10n.deletedForGoodToday,
        _ => currentL10n.daysLeft(days),
      };
}
