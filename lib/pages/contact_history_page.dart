import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

/// Earlier versions of one contact, from this device's restore points, to
/// undo changes to just that contact. Pops with the restored contact.
class ContactHistoryPage extends ConsumerStatefulWidget {
  const ContactHistoryPage({super.key, required this.contact});

  final VaultContact contact;

  @override
  ConsumerState<ContactHistoryPage> createState() =>
      _ContactHistoryPageState();
}

class _ContactHistoryPageState extends ConsumerState<ContactHistoryPage> {
  late final VaultRepository _repo = requireRepository(ref);
  late final Future<List<ContactVersion>> _versions =
      _repo.contactHistory(widget.contact.id);
  bool _busy = false;

  static String _when(DateTime at) {
    final DateTime t = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// What differs from the current contact, in a few words.
  static String _changes(VaultContact then, VaultContact now) {
    final List<String> parts = <String>[
      if (then.displayName != now.displayName) 'name: ${then.displayName}',
      if (then.phones.join() != now.phones.join())
        then.phones.isEmpty ? 'no phone' : 'phone: ${then.phones.join(', ')}',
      if (then.emails.join() != now.emails.join())
        then.emails.isEmpty ? 'no email' : 'email: ${then.emails.join(', ')}',
      if (then.company != now.company)
        then.company.isEmpty ? 'no company' : 'company: ${then.company}',
      if (then.addresses.join() != now.addresses.join()) 'other address',
      if (then.labels.join() != now.labels.join()) 'other labels',
      if (then.notes != now.notes) 'other notes',
      if (then.birthdays.join() != now.birthdays.join()) 'other birthday',
      if (then.isFavorite != now.isFavorite)
        then.isFavorite ? 'favourite' : 'not a favourite',
      if (then.isBlocked != now.isBlocked)
        then.isBlocked ? 'blocked' : 'not blocked',
    ];
    return parts.isEmpty ? 'Small differences' : parts.join(' · ');
  }

  Future<void> _restore(ContactVersion version) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Go back to this version?'),
        content: Text(
          '${widget.contact.displayName} goes back to how it was on '
          '${_when(version.savedAt)}, on every device. The photo stays as it '
          'is now.',
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go back')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final VaultContact restored = await _repo.restoreVersion(version.contact);
      if (mounted) Navigator.of(context).pop(restored);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Undo changes')),
      body: FutureBuilder<List<ContactVersion>>(
        future: _versions,
        builder: (BuildContext context,
            AsyncSnapshot<List<ContactVersion>> snap) {
          final List<ContactVersion>? versions = snap.data;
          if (versions == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (versions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No earlier versions of this contact on this phone yet.\n'
                  'Versions come from the daily, weekly and before-import '
                  'restore points.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: <Widget>[
              for (final ContactVersion v in versions)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(_when(v.savedAt)),
                  subtitle: Text(_changes(v.contact, widget.contact)),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _restore(v),
                    child: const Text('Go back'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
