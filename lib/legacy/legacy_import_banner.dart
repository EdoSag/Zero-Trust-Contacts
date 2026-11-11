import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/legacy/legacy_contacts_importer.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_controller.dart';
import 'package:zerotrust_contacts/widgets/compact_button_style.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// Asks for the password from before the update and brings the earlier
/// contacts over. Returns the number imported, or null when cancelled.
Future<int?> showLegacyImportDialog(BuildContext context) => showDialog<int>(
    context: context, builder: (_) => const _LegacyImportDialog());

/// Shown on the contact list while earlier contacts wait for the password.
class LegacyImportBanner extends ConsumerStatefulWidget {
  const LegacyImportBanner({super.key});

  @override
  ConsumerState<LegacyImportBanner> createState() => _LegacyImportBannerState();
}

class _LegacyImportBannerState extends ConsumerState<LegacyImportBanner> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final bool pending =
        ref.watch(legacyImportProvider) == LegacyImportStatus.needsPassword;
    if (!pending || _hidden) return const SizedBox.shrink();
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Card(
        color: colors.secondaryContainer,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.bringOverYourContactsFrom,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSecondaryContainer),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.contactsNowUsesYourZero,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    style: compactButtonStyle,
                    onPressed: () => setState(() => _hidden = true),
                    child: Text(context.l10n.later),
                  ),
                  FilledButton(
                    style: compactButtonStyle,
                    onPressed: () async {
                      final int? count = await showLegacyImportDialog(context);
                      if (count == null || !context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(context.l10n.broughtOver(count))));
                    },
                    child: Text(context.l10n.bringOver),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegacyImportDialog extends ConsumerStatefulWidget {
  const _LegacyImportDialog();

  @override
  ConsumerState<_LegacyImportDialog> createState() =>
      _LegacyImportDialogState();
}

class _LegacyImportDialogState extends ConsumerState<_LegacyImportDialog> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final int count = await ref
          .read(legacyImportProvider.notifier)
          .runWithPassword(_password.text);
      if (mounted) Navigator.pop(context, count);
    } on LegacyPasswordNeeded {
      if (mounted) {
        setState(() => _error =
            context.l10n.thatPasswordDoesntOpenYour);
      }
    } on Object {
      if (mounted) {
        setState(
            () => _error = context.l10n.couldntBringThemOverCheck);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.earlierContacts),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.enterThePasswordYouUsed,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            decoration: InputDecoration(
                labelText: context.l10n.passwordFromBefore, errorText: _error),
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            onSubmitted: (_) => _import(),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
            onPressed: _busy ? null : _import, child: Text(context.l10n.bringOver)),
      ],
    );
  }
}
