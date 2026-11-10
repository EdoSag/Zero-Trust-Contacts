import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/import/vcard_writer.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/contact_history_page.dart';
import 'package:zerotrust_contacts/services/contact_actions.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zerotrust_contacts/widgets/compact_button_style.dart';

class ContactDetailPage extends ConsumerStatefulWidget {
  const ContactDetailPage({
    super.key,
    required this.contact,
  });

  final VaultContact contact;

  @override
  ConsumerState<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends ConsumerState<ContactDetailPage> {
  late final VaultRepository _vaultRepository = requireRepository(ref);

  late VaultContact _contact;

  bool _isSavedContact = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _refreshSavedState();
  }

  Future<void> _refreshSavedState() async {
    final VaultContact? saved =
        await _vaultRepository.findSavedContactById(_contact.id);
    if (!mounted) {
      return;
    }
    if (saved != null) {
      setState(() {
        _contact = saved;
        _isSavedContact = true;
      });
    } else {
      setState(() {
        _isSavedContact = _contact.source == 'Saved';
      });
    }
  }

  /// Opens the editor: changes to a saved contact, or a phone contact
  /// saved into the vault as a new one.
  Future<void> _edit() async {
    final VaultContact? saved = await Navigator.of(context).push<VaultContact>(
      MaterialPageRoute<VaultContact>(
        builder: (_) => _isSavedContact
            ? CreateContactPage(existing: _contact)
            : CreateContactPage(
                prefill: _contact,
                createActivity: 'contact_saved_from_device',
              ),
      ),
    );
    if (saved == null || !mounted) {
      return;
    }
    setState(() {
      _contact = saved;
      _isSavedContact = true;
    });
    await _refreshSavedState();
  }

  /// Moves the contact to the trash (kept 30 days), with an Undo.
  Future<void> _delete() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    final VaultRepository repo = _vaultRepository;
    final String id = _contact.id;
    final bool deleted = await repo.deleteSavedContact(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
    if (!deleted) {
      return;
    }
    // The messenger outlives this page, so Undo still works after it closes.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${_contact.displayName} moved to the trash'),
        // Flutter keeps a snackbar with an action open until it is tapped.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.restoreFromTrash(id),
        ),
      ));
    Navigator.of(context).pop(true);
  }

  Future<void> _openHistory() async {
    final VaultContact? restored = await Navigator.of(context).push(
      MaterialPageRoute<VaultContact>(
        builder: (_) => ContactHistoryPage(contact: _contact),
      ),
    );
    if (restored == null || !mounted) {
      return;
    }
    await _refreshSavedState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes undone on every device.')));
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    await _vaultRepository.toggleFavorite(_contact.id);
    await _refreshSavedState();
  }

  Future<void> _togglePinned() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    await _vaultRepository.togglePinned(_contact.id);
    await _refreshSavedState();
  }

  Future<void> _blockContact() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    final TextEditingController reasonController = TextEditingController();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.block, color: colorScheme.error),
              const SizedBox(width: 8),
              const Text('Block contact'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This contact will be marked as blocked.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g. Spam, unwanted contact…',
                  labelStyle: TextStyle(color: colorScheme.error),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colorScheme.error),
                  ),
                  counterStyle:
                      TextStyle(color: colorScheme.error.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style:
                  FilledButton.styleFrom(backgroundColor: colorScheme.error),
              child: const Text('Block'),
            ),
          ],
        );
      },
    );
    final String? reason =
        (confirmed == true && reasonController.text.trim().isNotEmpty)
            ? reasonController.text.trim()
            : null;
    reasonController.dispose();
    if (confirmed != true) {
      return;
    }
    setState(() {
      _busy = true;
    });
    await _vaultRepository.blockContact(_contact.id, reason: reason);
    await _refreshSavedState();
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _unblockContact() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Unblock contact'),
        content: const Text('This contact will be unblocked.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _busy = true;
    });
    await _vaultRepository.unblockContact(_contact.id);
    await _refreshSavedState();
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  /// Opens [uri] in another app (dialer, messages, mail, WhatsApp, Signal,
  /// maps). Counts as an interaction unless [interaction] is false.
  Future<void> _open(Uri? uri, {bool interaction = true}) async {
    if (uri == null) {
      return;
    }
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (!mounted) {
      return;
    }
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_noAppMessage(uri))),
      );
      return;
    }
    if (interaction && _isSavedContact) {
      await _vaultRepository.markContactInteraction(_contact.id);
      await _refreshSavedState();
    }
  }

  static String _noAppMessage(Uri uri) => switch (uri.host) {
        'wa.me' => 'WhatsApp isn\'t installed, or doesn\'t know this number.',
        'signal.me' => 'Signal isn\'t installed.',
        _ => 'No app on this phone can open that.',
      };

  String? get _firstPhone =>
      _contact.phones.isEmpty ? null : _contact.phones.first;

  bool get _isIOS => Theme.of(context).platform == TargetPlatform.iOS;

  /// Shares the contact as a .vcf file (with its photo) through the
  /// system share sheet. The receiving app gets it unencrypted.
  Future<void> _shareVCard() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final Uint8List? photo = _contact.photo == null
          ? null
          : await (await ref.read(contactPhotosProvider.future)).read(_contact);
      final String card = const VCardWriter().write(_contact, photo: photo);
      final String name = VCardWriter.fileNameFor(_contact);
      await ref.read(vaultControllerProvider.notifier).whileShowingSystemUi(
            () => SharePlus.instance.share(ShareParams(
              files: <XFile>[
                XFile.fromData(Uint8List.fromList(utf8.encode(card)),
                    mimeType: 'text/x-vcard', name: name),
              ],
              fileNameOverrides: <String>[name],
              subject: _contact.displayName,
            )),
          );
      await _vaultRepository.logActivity('contact_share_vcard',
          details: 'Shared ${_contact.displayName} as a vCard');
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t share: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// Shows the contact as a QR code another phone's camera can scan into
  /// its contacts. Notes and the photo are left out to keep it scannable.
  Future<void> _showQrCode() async {
    final String card =
        const VCardWriter().write(_contact, includeNotes: false);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(
          _contact.displayName,
          textDirection: directionOf(_contact.displayName),
        ),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: card,
                  size: 256,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  semanticsLabel: 'QR code for ${_contact.displayName}',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Scan with another phone\'s camera to add this contact. '
                'Anyone who can see the code can read it.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareSecurePackage() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final SecureSharePackage package =
          await _vaultRepository.createSecureSharePackage(
        contact: _contact,
      );
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Secure share package'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Passphrase: ${package.passphrase}'),
                const SizedBox(height: 8),
                Text('Expires: ${package.expiresAt.toLocal()}'),
                const SizedBox(height: 12),
                const Text(
                    'Copy both package and passphrase to share securely.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: package.passphrase));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passphrase copied')),
                    );
                  }
                },
                child: const Text('Copy passphrase'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: package.payload));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Package copied')),
                    );
                  }
                },
                child: const Text('Copy package'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _buildReadOnlyBody() {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final String phone in _contact.phones)
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            // A phone number reads left-to-right on any screen.
            title: Align(
              alignment: AlignmentDirectional.centerStart,
              // Only as tall as the text: without this it fills the row and
              // the name and number are drawn over each other.
              heightFactor: 1,
              child: Text(phone, textDirection: TextDirection.ltr),
            ),
            subtitle: Text(_contact.typeLabel('phone', phone, fallback: 'Phone')),
            onTap: () => _open(ContactActions.call(phone)),
            onLongPress: () => _copy(phone),
            trailing: IconButton(
              tooltip: 'Text $phone',
              icon: const Icon(Icons.sms_outlined),
              onPressed: () => _open(ContactActions.text(phone)),
            ),
          ),
        for (final String email in _contact.emails)
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Align(
              alignment: AlignmentDirectional.centerStart,
              // Only as tall as the text: without this it fills the row and
              // the name and number are drawn over each other.
              heightFactor: 1,
              child: Text(email, textDirection: TextDirection.ltr),
            ),
            subtitle: Text(_contact.typeLabel('email', email, fallback: 'Email')),
            onTap: () => _open(ContactActions.email(email)),
            onLongPress: () => _copy(email),
          ),
        for (final String address in _contact.addresses)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(address),
            subtitle:
                Text(_contact.typeLabel('address', address, fallback: 'Address')),
            onTap: () => _open(
                ContactActions.directions(address, isIOS: _isIOS),
                interaction: false),
            onLongPress: () => _copy(address),
            trailing: const Icon(Icons.directions_outlined),
          ),
        if (_contact.company.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.apartment_outlined),
            title: Text(_contact.company),
            subtitle: const Text('Company'),
          ),
        for (final String birthday in _contact.birthdays)
          ListTile(
            leading: const Icon(Icons.cake_outlined),
            title: Text(birthday),
            subtitle: const Text('Birthday'),
          ),
        if (_contact.labels.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _contact.labels
                .map((String label) => Chip(label: Text(label)))
                .toList(),
          ),
        if (_contact.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Notes',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          SelectableText(
            _contact.notes,
            textDirection: directionOf(_contact.notes),
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Interaction count: ${_contact.interactionCount}',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Copied')));
    }
  }

  /// Call, text, email, WhatsApp, Signal and directions, for the first
  /// phone, email and address. Each detail row below has its own too.
  List<Widget> _quickActions() {
    final String? phone = _firstPhone;
    final String? email = _contact.emails.isEmpty ? null : _contact.emails.first;
    final String? address =
        _contact.addresses.isEmpty ? null : _contact.addresses.first;
    Widget action(IconData icon, String label, Uri? uri,
            {bool interaction = true}) =>
        OutlinedButton.icon(
          style: compactButtonStyle,
          onPressed:
              uri == null ? null : () => _open(uri, interaction: interaction),
          icon: Icon(icon),
          label: Text(label),
        );
    return <Widget>[
      action(Icons.call_outlined, 'Call',
          phone == null ? null : ContactActions.call(phone)),
      action(Icons.sms_outlined, 'Text',
          phone == null ? null : ContactActions.text(phone)),
      if (email != null)
        action(Icons.email_outlined, 'Email', ContactActions.email(email)),
      if (phone != null)
        action(Icons.chat_outlined, 'WhatsApp', ContactActions.whatsApp(phone)),
      if (phone != null && ContactActions.signal(phone) != null)
        action(Icons.forum_outlined, 'Signal', ContactActions.signal(phone)),
      if (address != null)
        action(Icons.directions_outlined, 'Directions',
            ContactActions.directions(address, isIOS: _isIOS),
            interaction: false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact.displayName),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onSelected: (String choice) => switch (choice) {
              'vcard' => _shareVCard(),
              'qr' => _showQrCode(),
              _ => _shareSecurePackage(),
            },
            itemBuilder: (BuildContext context) => const [
              PopupMenuItem<String>(
                value: 'vcard',
                child: ListTile(
                  leading: Icon(Icons.contact_page_outlined),
                  title: Text('Share as vCard'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'qr',
                child: ListTile(
                  leading: Icon(Icons.qr_code_2),
                  title: Text('Show QR code'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'secure',
                child: ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('Encrypted share'),
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: _busy ? null : _edit,
            icon: Icon(
                _isSavedContact ? Icons.edit_outlined : Icons.person_add_alt),
            tooltip: _isSavedContact ? 'Edit' : 'Save to the vault',
          ),
          if (_isSavedContact)
            PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (String choice) => switch (choice) {
                'history' => _openHistory(),
                _ => _delete(),
              },
              itemBuilder: (BuildContext context) => const [
                PopupMenuItem<String>(
                  value: 'history',
                  child: ListTile(
                    leading: Icon(Icons.history),
                    title: Text('Undo changes'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'trash',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Move to trash'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Photo header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: ContactAvatar(contact: _contact, radius: 48),
          ),
          if (_isSavedContact && _contact.isBlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.block,
                      color:
                          Theme.of(context).colorScheme.onErrorContainer,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Blocked',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (_contact.blockReason != null &&
                              _contact.blockReason!.isNotEmpty)
                            Text(
                              _contact.blockReason!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._quickActions(),
                OutlinedButton.icon(
                  style: compactButtonStyle,
                  onPressed:
                      (!_isSavedContact || _busy) ? null : _toggleFavorite,
                  icon: Icon(
                    _contact.isFavorite
                        ? Icons.star
                        : Icons.star_border_outlined,
                  ),
                  label: const Text('Favorite'),
                ),
                OutlinedButton.icon(
                  style: compactButtonStyle,
                  onPressed: (!_isSavedContact || _busy) ? null : _togglePinned,
                  icon: Icon(
                    _contact.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                  label: const Text('Pin'),
                ),
                if (_isSavedContact)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : (_contact.isBlocked
                            ? _unblockContact
                            : _blockContact),
                    icon: Icon(
                      _contact.isBlocked
                          ? Icons.lock_open_outlined
                          : Icons.block_outlined,
                      color: (_busy || _contact.isBlocked)
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      _contact.isBlocked ? 'Unblock' : 'Block',
                      style: TextStyle(
                        color: (_busy || _contact.isBlocked)
                            ? null
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    style: _contact.isBlocked
                        ? compactButtonStyle
                        : OutlinedButton.styleFrom(
                            minimumSize: const Size(64, 40),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .error
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _buildReadOnlyBody(),
          ),
        ],
      ),
    );
  }
}
