import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/app/text_direction.dart';
import 'package:zerotrust_contacts/import/contact_import_planner.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

/// The one contact editor: a new contact, a new contact filled in from
/// somewhere else ([prefill]: a phone contact, a number another app asked
/// to save), or changes to a saved one ([existing]).
///
/// Pops with the saved [VaultContact], or null when nothing was saved.
class CreateContactPage extends ConsumerStatefulWidget {
  const CreateContactPage({
    super.key,
    this.existing,
    this.prefill,
    this.createActivity = 'contact_create',
  });

  /// A saved contact to change.
  final VaultContact? existing;

  /// Details to start a new contact from.
  final VaultContact? prefill;

  /// What the activity log calls saving a new contact from here.
  final String createActivity;

  @override
  ConsumerState<CreateContactPage> createState() => _CreateContactPageState();
}

/// One phone, email or address row: the value and its kind (Mobile, Work…).
class _TypedRow {
  _TypedRow(String value, this.type)
    : controller = TextEditingController(text: value);

  final TextEditingController controller;

  /// A kind from the field's list, or '' for none.
  String type;
}

enum _DuplicateChoice { open, addTo, saveAnyway }

class _CreateContactPageState extends ConsumerState<CreateContactPage> {
  late final VaultContact? _base = widget.existing ?? widget.prefill;
  bool get _editing => widget.existing != null;

  late final TextEditingController _firstName = TextEditingController(
    text: _base?.firstName ?? '',
  );
  late final TextEditingController _lastName = TextEditingController(
    text: _base?.lastName ?? '',
  );
  late final TextEditingController _company = TextEditingController(
    text: _base?.company ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: _base?.notes ?? '',
  );

  late final List<_TypedRow> _phones = _rowsFor('phone', _base?.phones);
  late final List<_TypedRow> _emails = _rowsFor('email', _base?.emails);
  late final List<_TypedRow> _addresses = _rowsFor('address', _base?.addresses);
  late final List<TextEditingController> _birthdays = _plain(_base?.birthdays);
  late final List<TextEditingController> _labels = _plain(_base?.labels);
  late final List<TextEditingController> _other = _plain(_base?.other);

  late bool _isFavorite = _base?.isFavorite ?? false;
  bool _isSaving = false;
  File? _pickedPhotoFile;
  bool _photoCleared = false;

  List<_TypedRow> _rowsFor(String field, List<String>? values) => <_TypedRow>[
    for (final String value in values ?? const <String>[])
      _TypedRow(value, _base?.typeOf(field, value) ?? ''),
  ];

  List<TextEditingController> _plain(List<String>? values) =>
      <TextEditingController>[
        for (final String value in values ?? const <String>[])
          TextEditingController(text: value),
      ];

  @override
  void initState() {
    super.initState();
    if (_phones.isEmpty && !_editing) {
      _phones.add(_TypedRow('', 'mobile'));
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _firstName,
      _lastName,
      _company,
      _notes,
      ..._birthdays,
      ..._labels,
      ..._other,
      for (final _TypedRow row in <_TypedRow>[
        ..._phones,
        ..._emails,
        ..._addresses,
      ])
        row.controller,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _hasPhoto =>
      _pickedPhotoFile != null ||
      (!_photoCleared && (widget.existing?.hasPhoto ?? false));

  Future<void> _pickPhoto() async {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final VaultController vault = ref.read(vaultControllerProvider.notifier);
    final Object? picked = await showModalBottomSheet<Object?>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Choose from gallery'),
              onTap: () async {
                final XFile? file = await vault.whileShowingSystemUi(
                  const PhotoPicker().pickFromGallery,
                );
                if (ctx.mounted) Navigator.of(ctx).pop(file);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.camera_alt_outlined,
                color: colorScheme.primary,
              ),
              title: const Text('Take a photo'),
              onTap: () async {
                final XFile? file = await vault.whileShowingSystemUi(
                  const PhotoPicker().pickFromCamera,
                );
                if (ctx.mounted) Navigator.of(ctx).pop(file);
              },
            ),
            if (_hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: const Text('Remove photo'),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (picked is XFile) {
      setState(() {
        _pickedPhotoFile = File(picked.path);
        _photoCleared = false;
      });
    } else if (picked == 'remove') {
      setState(() {
        _pickedPhotoFile = null;
        _photoCleared = true;
      });
    }
  }

  static List<String> _values(List<TextEditingController> controllers) =>
      _unique(controllers.map((TextEditingController c) => c.text));

  static List<String> _unique(Iterable<String> values) {
    final Set<String> seen = <String>{};
    return values
        .map((String v) => v.trim())
        .where((String v) => v.isNotEmpty && seen.add(v.toLowerCase()))
        .toList();
  }

  /// The kinds of every typed row, by [VaultContact.typeKey]. An empty kind
  /// is kept ('' clears one the contact had).
  Map<String, String> _types() => <String, String>{
    for (final (String field, List<_TypedRow> rows)
        in <(String, List<_TypedRow>)>[
          ('phone', _phones),
          ('email', _emails),
          ('address', _addresses),
        ])
      for (final _TypedRow row in rows)
        if (row.controller.text.trim().isNotEmpty)
          VaultContact.typeKey(field, row.controller.text): row.type,
  };

  /// The contact as the form has it now (without a new photo).
  VaultContact _fromForm() {
    final String firstName = _firstName.text.trim();
    final String lastName = _lastName.text.trim();
    final String company = _company.text.trim();
    final List<String> phones = _unique(
      _phones.map((_TypedRow r) => r.controller.text),
    );
    final List<String> emails = _unique(
      _emails.map((_TypedRow r) => r.controller.text),
    );
    final List<String> addresses = _unique(
      _addresses.map((_TypedRow r) => r.controller.text),
    );
    final String fullName = '$firstName $lastName'.trim();
    final String displayName = fullName.isNotEmpty
        ? fullName
        : company.isNotEmpty
        ? company
        : phones.isNotEmpty
        ? phones.first
        : emails.isNotEmpty
        ? emails.first
        : 'Unnamed Contact';

    final VaultContact? existing = widget.existing;
    if (existing != null) {
      final bool nameChanged =
          firstName != existing.firstName ||
          lastName != existing.lastName ||
          (fullName.isEmpty && company != existing.company);
      return existing.applyEdits(
        // A name typed here replaces the shown name; an untouched one (it
        // may have come from an import) stays as it is.
        displayName: nameChanged ? displayName : null,
        firstName: firstName,
        lastName: lastName,
        company: company,
        notes: _notes.text.trim(),
        phones: phones,
        emails: emails,
        addresses: addresses,
        birthdays: _values(_birthdays),
        labels: _values(_labels),
        other: _values(_other),
        isFavorite: _isFavorite,
        valueTypes: _types(),
      );
    }
    final DateTime now = DateTime.now().toUtc();
    return VaultContact.fromLegacyPayload(<String, dynamic>{
      'id': VaultContact.generateId(),
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'company': company,
      'notes': _notes.text.trim(),
      'phones': phones,
      'emails': emails,
      'addresses': addresses,
      'labels': _values(_labels),
      'birthdays': _values(_birthdays),
      'other': _values(_other),
      'source': 'Saved',
      'isFavorite': _isFavorite,
      'isPinned': false,
      'valueTypes': <String, String>{
        for (final MapEntry<String, String> e in _types().entries)
          if (e.value.isNotEmpty) e.key: e.value,
      },
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }

  bool _isEmpty(VaultContact c) =>
      c.firstName.isEmpty &&
      c.lastName.isEmpty &&
      c.company.isEmpty &&
      c.notes.isEmpty &&
      c.phones.isEmpty &&
      c.emails.isEmpty &&
      c.addresses.isEmpty &&
      c.labels.isEmpty &&
      c.birthdays.isEmpty &&
      c.other.isEmpty;

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    VaultContact contact = _fromForm();
    if (_isEmpty(contact) && !_hasPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one contact detail to save.'),
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final VaultRepository repo = requireRepository(ref);
      String activity = _editing ? 'contact_edit' : widget.createActivity;

      if (!_editing) {
        // Warn before the same person is saved twice.
        final List<VaultContact> matches = const ContactImportPlanner()
            .matchesFor(contact, await repo.loadSavedContacts());
        if (matches.isNotEmpty) {
          if (!mounted) return;
          final (_DuplicateChoice, VaultContact)? choice =
              await _askAboutDuplicate(matches);
          if (choice == null || !mounted) {
            return;
          }
          switch (choice.$1) {
            case _DuplicateChoice.open:
              // Leave the editor for that contact's page.
              unawaited(
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<bool>(
                    builder: (_) => ContactDetailPage(contact: choice.$2),
                  ),
                ),
              );
              return;
            case _DuplicateChoice.addTo:
              contact = const ContactImportPlanner().merge(choice.$2, contact);
              activity = 'contact_edit';
            case _DuplicateChoice.saveAnyway:
              break;
          }
        }
      }

      final File? photoFile = _pickedPhotoFile;
      if (photoFile != null) {
        final Map<String, Object?> photo = await (await ref.read(
          contactPhotosProvider.future,
        )).storeFile(photoFile);
        // Adding to a contact that already has a photo keeps that one.
        if (activity != 'contact_edit' || _editing || !contact.hasPhoto) {
          contact = contact.applyEdits(photo: photo);
        }
      } else if (_photoCleared && contact.hasPhoto && _editing) {
        contact = contact.applyEdits(clearPhoto: true);
      }

      await repo.upsertSavedContact(contact, activity: activity);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(contact);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save contact: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<(_DuplicateChoice, VaultContact)?> _askAboutDuplicate(
    List<VaultContact> matches,
  ) {
    return showDialog<(_DuplicateChoice, VaultContact)>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          matches.length == 1
              ? 'You may already have this contact'
              : 'You may already have these contacts',
        ),
        contentPadding: const EdgeInsets.only(top: 12),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final VaultContact match in matches.take(5))
                ListTile(
                  leading: ContactAvatar(contact: match, radius: 20),
                  title: Text(match.displayName),
                  subtitle: Text(
                    <String>[
                      ...match.phones.take(1),
                      ...match.emails.take(1),
                    ].join(' · '),
                  ),
                  trailing: PopupMenuButton<_DuplicateChoice>(
                    tooltip: 'What to do with ${match.displayName}',
                    onSelected: (_DuplicateChoice c) =>
                        Navigator.of(ctx).pop((c, match)),
                    itemBuilder: (_) =>
                        const <PopupMenuEntry<_DuplicateChoice>>[
                          PopupMenuItem<_DuplicateChoice>(
                            value: _DuplicateChoice.addTo,
                            child: Text('Add the new details to this contact'),
                          ),
                          PopupMenuItem<_DuplicateChoice>(
                            value: _DuplicateChoice.open,
                            child: Text('Open this contact instead'),
                          ),
                        ],
                  ),
                  onTap: () =>
                      Navigator.of(ctx).pop((_DuplicateChoice.addTo, match)),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  'Tap a contact to add the new details to it, or save a '
                  'separate contact anyway.',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(
              ctx,
            ).pop((_DuplicateChoice.saveAnyway, matches.first)),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBirthday(TextEditingController controller) async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(1900);
    final DateTime last = DateTime(now.year + 5, 12, 31);
    DateTime initial =
        DateTime.tryParse(controller.text) ?? DateTime(now.year - 18);
    if (initial.isBefore(first) || initial.isAfter(last)) {
      initial = now;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Select birthday',
    );
    if (picked == null) {
      return;
    }
    final String month = picked.month.toString().padLeft(2, '0');
    final String day = picked.day.toString().padLeft(2, '0');
    setState(() => controller.text = '${picked.year}-$month-$day');
  }

  static String _typeName(String type) =>
      '${type[0].toUpperCase()}${type.substring(1)}';

  Widget _typedSection({
    required String title,
    required String addLabel,
    required IconData icon,
    required List<_TypedRow> rows,
    required List<String> types,
    required String hint,
    TextInputType? keyboardType,
    bool forceLtr = false,
    int maxLines = 1,
  }) {
    return _Section(
      icon: icon,
      addLabel: addLabel,
      onAdd: () => setState(() => rows.add(_TypedRow('', types.first))),
      children: <Widget>[
        for (final _TypedRow row in rows)
          Padding(
            key: ObjectKey(row),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: DirectionalTextField(
                    controller: row.controller,
                    keyboardType: keyboardType,
                    forceLtr: forceLtr,
                    maxLines: maxLines,
                    decoration: InputDecoration(
                      labelText: title,
                      hintText: hint,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: DropdownButton<String>(
                    value: types.contains(row.type) ? row.type : '',
                    underline: const SizedBox.shrink(),
                    items: <DropdownMenuItem<String>>[
                      for (final String type in types)
                        DropdownMenuItem<String>(
                          value: type,
                          child: Text(_typeName(type)),
                        ),
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('No label'),
                      ),
                    ],
                    onChanged: (String? value) =>
                        setState(() => row.type = value ?? ''),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    rows.remove(row);
                    row.controller.dispose();
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _plainSection({
    required String title,
    required String addLabel,
    required IconData icon,
    required List<TextEditingController> rows,
    String? hint,
    bool birthday = false,
  }) {
    return _Section(
      icon: icon,
      addLabel: addLabel,
      onAdd: () {
        final TextEditingController controller = TextEditingController();
        setState(() => rows.add(controller));
        if (birthday) {
          _pickBirthday(controller);
        }
      },
      children: <Widget>[
        for (final TextEditingController controller in rows)
          Padding(
            key: ObjectKey(controller),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: DirectionalTextField(
                    controller: controller,
                    readOnly: birthday,
                    forceLtr: birthday,
                    onTap: birthday ? () => _pickBirthday(controller) : null,
                    decoration: InputDecoration(
                      labelText: title,
                      hintText: hint,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    rows.remove(controller);
                    controller.dispose();
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final VaultContact? existing = widget.existing;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_editing ? 'Edit contact' : 'New contact'),
        actions: <Widget>[
          IconButton(
            tooltip: _isFavorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(_isFavorite ? Icons.star : Icons.star_border),
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Center(
              child: FilledButton(
                // The app theme makes filled buttons full width.
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  alignment: AlignmentDirectional.bottomEnd,
                  children: <Widget>[
                    if (existing != null && !_photoCleared)
                      ContactAvatar(
                        contact: existing,
                        radius: 48,
                        overridePhoto: _pickedPhotoFile,
                      )
                    else
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: _pickedPhotoFile == null
                            ? null
                            : FileImage(_pickedPhotoFile!),
                        child: _pickedPhotoFile == null
                            ? Icon(
                                Icons.add_a_photo_outlined,
                                size: 32,
                                color: colorScheme.onPrimaryContainer,
                              )
                            : null,
                      ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit,
                        size: 16,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              icon: Icons.person_outline,
              children: <Widget>[
                DirectionalTextField(
                  controller: _firstName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 8),
                DirectionalTextField(
                  controller: _lastName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 8),
                DirectionalTextField(
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Company'),
                ),
                const SizedBox(height: 8),
              ],
            ),
            _typedSection(
              title: 'Phone',
              addLabel: 'Add phone',
              icon: Icons.phone_outlined,
              rows: _phones,
              types: VaultContact.phoneTypes,
              hint: 'With country code, like +972 50 123 4567',
              keyboardType: TextInputType.phone,
              forceLtr: true,
            ),
            _typedSection(
              title: 'Email',
              addLabel: 'Add email',
              icon: Icons.email_outlined,
              rows: _emails,
              types: VaultContact.emailTypes,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              forceLtr: true,
            ),
            _typedSection(
              title: 'Address',
              addLabel: 'Add address',
              icon: Icons.place_outlined,
              rows: _addresses,
              types: VaultContact.addressTypes,
              hint: 'Street, city, country',
              keyboardType: TextInputType.streetAddress,
              maxLines: 2,
            ),
            _plainSection(
              title: 'Birthday',
              addLabel: 'Add birthday',
              icon: Icons.cake_outlined,
              rows: _birthdays,
              birthday: true,
            ),
            _plainSection(
              title: 'Label',
              addLabel: 'Add label',
              icon: Icons.label_outline,
              rows: _labels,
              hint: 'Family, Work, Gym…',
            ),
            _plainSection(
              title: 'Website or other',
              addLabel: 'Add website or other detail',
              icon: Icons.link,
              rows: _other,
            ),
            _Section(
              icon: Icons.notes_outlined,
              children: <Widget>[
                DirectionalTextField(
                  controller: _notes,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A group of editor rows with its icon at the start and an "Add …" button.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.children,
    this.addLabel,
    this.onAdd,
  });

  final IconData icon;
  final List<Widget> children;
  final String? addLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 14, end: 16),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...children,
                if (addLabel != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(addLabel!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
