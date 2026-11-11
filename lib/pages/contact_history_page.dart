import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

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
    return DateFormat.yMMMd().add_Hm().format(t);
  }

  /// What differs from the current contact, in a few words.
  static String _changes(VaultContact then, VaultContact now) {
    final List<String> parts = <String>[
      if (then.displayName != now.displayName) currentL10n.histName(then.displayName),
      if (then.phones.join() != now.phones.join())
        then.phones.isEmpty ? currentL10n.noPhone : currentL10n.histPhone(then.phones.join(', ')),
      if (then.emails.join() != now.emails.join())
        then.emails.isEmpty ? currentL10n.noEmail : currentL10n.histEmail(then.emails.join(', ')),
      if (then.company != now.company)
        then.company.isEmpty ? currentL10n.noCompany : currentL10n.histCompany(then.company),
      if (then.addresses.join() != now.addresses.join()) currentL10n.otherAddress,
      if (then.labels.join() != now.labels.join()) currentL10n.otherLabels,
      if (then.notes != now.notes) currentL10n.otherNotes,
      if (then.birthdays.join() != now.birthdays.join()) currentL10n.otherBirthday,
      if (then.isFavorite != now.isFavorite)
        then.isFavorite ? currentL10n.histFavourite : currentL10n.notAFavourite,
      if (then.isBlocked != now.isBlocked)
        then.isBlocked ? currentL10n.histBlocked : currentL10n.notBlocked,
    ];
    return parts.isEmpty ? currentL10n.smallDifferences : parts.join(' · ');
  }

  Future<void> _restore(ContactVersion version) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.l10n.goBackToThisVersion),
        content: Text(
          context.l10n.goesBackTo(widget.contact.displayName, _when(version.savedAt)),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.goBack)),
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
      appBar: AppBar(title: Text(context.l10n.undoChanges)),
      body: FutureBuilder<List<ContactVersion>>(
        future: _versions,
        builder: (BuildContext context,
            AsyncSnapshot<List<ContactVersion>> snap) {
          final List<ContactVersion>? versions = snap.data;
          if (versions == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (versions.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  context.l10n.noEarlierVersionsOfThis,
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
                    child: Text(context.l10n.goBack),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
