import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

@NowaGenerated()
class ContactDetailPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const ContactDetailPage({
    super.key,
    required this.contact,
  });

  final VaultContact contact;

  @override
  State<ContactDetailPage> createState() => _ContactDetailPageState();
}

class _ContactDetailPageState extends State<ContactDetailPage> {
  final VaultRepository _vaultRepository = VaultRepository();
  final DeviceContactsService _deviceContactsService = DeviceContactsService();

  late VaultContact _contact;

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _companyController;
  late TextEditingController _phonesController;
  late TextEditingController _emailsController;
  late TextEditingController _labelsController;
  late TextEditingController _notesController;

  bool _isEditing = false;
  bool _isSavedContact = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _firstNameController = TextEditingController(text: _contact.firstName);
    _lastNameController = TextEditingController(text: _contact.lastName);
    _companyController = TextEditingController(text: _contact.company);
    _phonesController = TextEditingController(text: _contact.phones.join(', '));
    _emailsController = TextEditingController(text: _contact.emails.join(', '));
    _labelsController = TextEditingController(text: _contact.labels.join(', '));
    _notesController = TextEditingController(text: _contact.notes);
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

  List<String> _splitValues(String value) {
    return value
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      final VaultContact edited = _contact.applyEdits(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        company: _companyController.text.trim(),
        phones: _splitValues(_phonesController.text),
        emails: _splitValues(_emailsController.text),
        labels: _splitValues(_labelsController.text),
        notes: _notesController.text.trim(),
        source: 'Saved',
      );

      final VaultContact toSave = _isSavedContact
          ? edited
          : edited.copyWith(
              id: VaultContact.generateId(),
              createdAt: DateTime.now().toUtc(),
            );
      await _vaultRepository.upsertSavedContact(
        toSave,
        activity:
            _isSavedContact ? 'contact_edit' : 'contact_saved_from_device',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _contact = toSave;
        _isSavedContact = true;
        _isEditing = false;
      });
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save contact: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    if (!_isSavedContact || _busy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete contact'),
          content:
              const Text('This will remove the contact from your local vault.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _busy = true;
    });
    final bool deleted = await _vaultRepository.deleteSavedContact(_contact.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
    });
    if (deleted) {
      Navigator.of(context).pop(true);
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

  Future<void> _callContact() async {
    if (_contact.phones.isEmpty) {
      return;
    }
    await _deviceContactsService.launchDialer(_contact.phones.first);
    if (_isSavedContact) {
      await _vaultRepository.markContactInteraction(_contact.id);
      await _refreshSavedState();
    }
  }

  Future<void> _messageContact() async {
    if (_contact.phones.isEmpty) {
      return;
    }
    await _deviceContactsService.launchSms(_contact.phones.first);
    if (_isSavedContact) {
      await _vaultRepository.markContactInteraction(_contact.id);
      await _refreshSavedState();
    }
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
        if (_contact.phones.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.phone_outlined),
            title: Text(_contact.phones.first),
            subtitle: const Text('Phone'),
          ),
        if (_contact.emails.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(_contact.emails.first),
            subtitle: const Text('Email'),
          ),
        if (_contact.company.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.apartment_outlined),
            title: Text(_contact.company),
            subtitle: const Text('Company'),
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
          Text(
            _contact.notes,
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

  Widget _buildEditBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _firstNameController,
          decoration: const InputDecoration(labelText: 'First name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lastNameController,
          decoration: const InputDecoration(labelText: 'Last name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _companyController,
          decoration: const InputDecoration(labelText: 'Company'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phonesController,
          decoration:
              const InputDecoration(labelText: 'Phones (comma separated)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailsController,
          decoration:
              const InputDecoration(labelText: 'Emails (comma separated)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _labelsController,
          decoration:
              const InputDecoration(labelText: 'Labels (comma separated)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notes'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_contact.displayName),
        actions: [
          IconButton(
            onPressed: _busy ? null : _shareSecurePackage,
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Secure share',
          ),
          IconButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _isEditing = !_isEditing;
                    });
                  },
            icon: Icon(
                _isEditing ? Icons.visibility_outlined : Icons.edit_outlined),
            tooltip: _isEditing ? 'View' : 'Edit',
          ),
          if (_isSavedContact)
            IconButton(
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _contact.phones.isEmpty ? null : _callContact,
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call'),
                ),
                OutlinedButton.icon(
                  onPressed: _contact.phones.isEmpty ? null : _messageContact,
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Message'),
                ),
                OutlinedButton.icon(
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
                  onPressed: (!_isSavedContact || _busy) ? null : _togglePinned,
                  icon: Icon(
                    _contact.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                  label: const Text('Pin'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isEditing ? _buildEditBody() : _buildReadOnlyBody(),
          ),
        ],
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_busy ? 'Saving...' : 'Save'),
            )
          : null,
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _phonesController.dispose();
    _emailsController.dispose();
    _labelsController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}
