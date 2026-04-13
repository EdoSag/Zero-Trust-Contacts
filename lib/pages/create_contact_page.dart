import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

@NowaGenerated()
class CreateContactPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const CreateContactPage({super.key});

  @override
  State<CreateContactPage> createState() {
    return _CreateContactPageState();
  }
}

@NowaGenerated()
class _CreateContactPageState extends State<CreateContactPage> {
  final TextEditingController _firstNameController = TextEditingController();

  final TextEditingController _lastNameController = TextEditingController();

  final TextEditingController _companyController = TextEditingController();

  final TextEditingController _notesController = TextEditingController();

  final List<TextEditingController> _phoneControllers = [
    TextEditingController(),
  ];

  final List<TextEditingController> _emailControllers = [];

  final List<TextEditingController> _addressControllers = [];

  final List<TextEditingController> _labelControllers = [];

  final List<TextEditingController> _birthdayControllers = [];

  bool _showEmail = false;

  bool _showBirthday = false;

  bool _showAddress = false;

  bool _showLabels = false;

  bool _showOther = false;

  final List<TextEditingController> _otherControllers = [];

  bool _isSaving = false;
  bool _isFavorite = false;
  File? _pickedPhotoFile;

  Future<void> _pickContactPhoto() async {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final XFile? picked = await showModalBottomSheet<XFile?>(
      context: context,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined,
                    color: colorScheme.primary),
                title: const Text('Choose from gallery'),
                onTap: () async {
                  final XFile? f =
                      await ContactPhotoService().pickFromGallery();
                  if (ctx.mounted) Navigator.of(ctx).pop(f);
                },
              ),
              ListTile(
                leading: Icon(Icons.camera_alt_outlined,
                    color: colorScheme.primary),
                title: const Text('Take a photo'),
                onTap: () async {
                  final XFile? f =
                      await ContactPhotoService().pickFromCamera();
                  if (ctx.mounted) Navigator.of(ctx).pop(f);
                },
              ),
              if (_pickedPhotoFile != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colorScheme.error),
                  title: const Text('Remove photo'),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _pickedPhotoFile = File(picked.path));
    }
  }

  List<String> _allValuesFromControllers(
      List<TextEditingController> controllers) {
    return controllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String _buildDisplayName({
    required String firstName,
    required String lastName,
    required String company,
    required List<String> phones,
  }) {
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }
    if (company.isNotEmpty) {
      return company;
    }
    if (phones.isNotEmpty) {
      return phones.first;
    }
    return 'Unnamed Contact';
  }

  Future<void> _handleSaveContact() async {
    if (_isSaving) {
      return;
    }

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final company = _companyController.text.trim();
    final notes = _notesController.text.trim();
    final phones = _allValuesFromControllers(_phoneControllers);
    final emails = _allValuesFromControllers(_emailControllers);
    final addresses = _allValuesFromControllers(_addressControllers);
    final labels = _allValuesFromControllers(_labelControllers);
    final birthdays = _allValuesFromControllers(_birthdayControllers);
    final others = _allValuesFromControllers(_otherControllers);

    final hasAnyData = firstName.isNotEmpty ||
        lastName.isNotEmpty ||
        company.isNotEmpty ||
        notes.isNotEmpty ||
        phones.isNotEmpty ||
        emails.isNotEmpty ||
        addresses.isNotEmpty ||
        labels.isNotEmpty ||
        birthdays.isNotEmpty ||
        others.isNotEmpty;

    if (!hasAnyData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add at least one contact detail to save.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final String contactId = VaultContact.generateId();
      final File? photoToSave = _pickedPhotoFile;

      final payload = <String, dynamic>{
        'id': contactId,
        'displayName': _buildDisplayName(
          firstName: firstName,
          lastName: lastName,
          company: company,
          phones: phones,
        ),
        'firstName': firstName,
        'lastName': lastName,
        'company': company,
        'notes': notes,
        'phones': phones,
        'emails': emails,
        'addresses': addresses,
        'labels': labels,
        'birthdays': birthdays,
        'other': others,
        'source': 'Saved',
        'isFavorite': _isFavorite,
        'isPinned': false,
        'photoPath': photoToSave != null ? contactId : null,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await VaultRepository().upsertSavedContact(
        VaultContact.fromLegacyPayload(payload),
        activity: 'contact_create',
      );

      if (photoToSave != null) {
        await ContactPhotoService().saveLocally(contactId, photoToSave);
      }

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save contact: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _removeController(List<TextEditingController> controllers, int index) {
    if (index < 0 || index >= controllers.length) {
      return;
    }
    final controller = controllers.removeAt(index);
    controller.dispose();
  }

  DateTime? _parseBirthday(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }

    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  String _formatBirthday(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _pickBirthday(TextEditingController controller) async {
    final now = DateTime.now();
    final parsedValue = _parseBirthday(controller.text);
    final DateTime initialDate = parsedValue ?? DateTime(now.year - 18, 1, 1);
    final DateTime firstDate = DateTime(1900, 1, 1);
    final DateTime lastDate = DateTime(now.year + 5, 12, 31);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate:
          initialDate.isBefore(firstDate) || initialDate.isAfter(lastDate)
              ? now
              : initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select birthday',
    );
    if (pickedDate == null) {
      return;
    }

    setState(() {
      controller.text = _formatBirthday(pickedDate);
    });
  }

  Widget _buildPictureAndCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 180.0,
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24.0),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 12.0,
            right: 12.0,
            child: IconButton(
              icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
              onPressed: () {},
            ),
          ),
          Positioned(
            top: 16.0,
            left: 16.0,
            child: Text(
              'Picture & calling card',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 16.0,
              ),
            ),
          ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _pickContactPhoto,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 50.0,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: _pickedPhotoFile != null
                            ? FileImage(_pickedPhotoFile!)
                            : null,
                        child: _pickedPhotoFile == null
                            ? Icon(
                                Icons.person,
                                size: 60.0,
                                color: colorScheme.onPrimaryContainer,
                              )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          size: 16.0,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24.0),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Container(
                      width: 70.0,
                      height: 120.0,
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 30.0,
                            height: 2.0,
                            color: colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(height: 4.0),
                          Container(
                            width: 20.0,
                            height: 2.0,
                            color: colorScheme.onTertiaryContainer,
                          ),
                          const SizedBox(height: 8.0),
                          Icon(
                            Icons.image,
                            color: colorScheme.onTertiaryContainer,
                          ),
                          const Spacer(),
                          Container(
                            margin: const EdgeInsets.only(bottom: 8.0),
                            width: 40.0,
                            height: 8.0,
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(8.0, -8),
                      child: Container(
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add,
                          size: 16.0,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, void Function() onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(24.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.onSecondaryContainer, size: 20.0),
            const SizedBox(width: 8.0),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontSize: 14.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isPhone = false,
    int maxLines = 1,
    bool readOnly = false,
    void Function()? onTap,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      style: TextStyle(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        suffixIcon: suffixIcon,
        prefixIcon: isPhone
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'IL',
                      style: TextStyle(
                        fontSize: 14.0,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8.0),
                    Text(
                      '+972',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16.0,
                      ),
                    ),
                  ],
                ),
              )
            : null,
        prefixIconConstraints:
            isPhone ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
        enabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: colorScheme.outline.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(8.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary),
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0.0,
        leading: IconButton(
          icon: Icon(Icons.close, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Create contact',
          style: TextStyle(color: colorScheme.onSurface, fontSize: 20.0),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star : Icons.star_border,
              color: _isFavorite ? colorScheme.primary : colorScheme.onSurface,
            ),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleSaveContact,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.0),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 16.0,
                      width: 16.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Text('Save'),
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: colorScheme.onSurface),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPictureAndCard(),
              const SizedBox(height: 24.0),
              _buildTextField('First name', _firstNameController),
              const SizedBox(height: 16.0),
              _buildTextField('Last name', _lastNameController),
              const SizedBox(height: 16.0),
              _buildTextField('Company', _companyController),
              const SizedBox(height: 24.0),
              ..._phoneControllers.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              'Phone (Mobile)',
                              entry.value,
                              isPhone: true,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          IconButton(
                            icon: Icon(
                              Icons.remove_circle_outline,
                              color: colorScheme.error,
                            ),
                            onPressed: () {
                              setState(() {
                                _removeController(_phoneControllers, entry.key);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _phoneControllers.add(TextEditingController());
                  });
                },
                child: Text(
                  'Add phone',
                  style: TextStyle(color: colorScheme.primary),
                ),
              ),
              if (_showEmail) ...[
                const SizedBox(height: 16.0),
                ..._emailControllers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                                child: _buildTextField('Email', entry.value)),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removeController(
                                      _emailControllers, entry.key);
                                  if (_emailControllers.isEmpty) {
                                    _showEmail = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_showAddress) ...[
                const SizedBox(height: 16.0),
                ..._addressControllers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                                child: _buildTextField('Address', entry.value)),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removeController(
                                      _addressControllers, entry.key);
                                  if (_addressControllers.isEmpty) {
                                    _showAddress = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_showLabels) ...[
                const SizedBox(height: 16.0),
                ..._labelControllers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                                child: _buildTextField('Label', entry.value)),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removeController(
                                      _labelControllers, entry.key);
                                  if (_labelControllers.isEmpty) {
                                    _showLabels = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_showBirthday) ...[
                const SizedBox(height: 16.0),
                ..._birthdayControllers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                'Birthday',
                                entry.value,
                                readOnly: true,
                                onTap: () {
                                  _pickBirthday(entry.value);
                                },
                                suffixIcon: Icon(
                                  Icons.calendar_month_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removeController(
                                      _birthdayControllers, entry.key);
                                  if (_birthdayControllers.isEmpty) {
                                    _showBirthday = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              if (_showOther) ...[
                const SizedBox(height: 16.0),
                ..._otherControllers.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          children: [
                            Expanded(
                                child: _buildTextField('Other', entry.value)),
                            const SizedBox(width: 8.0),
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                color: colorScheme.error,
                              ),
                              onPressed: () {
                                setState(() {
                                  _removeController(
                                      _otherControllers, entry.key);
                                  if (_otherControllers.isEmpty) {
                                    _showOther = false;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 16.0),
              _buildTextField('Notes', _notesController, maxLines: 3),
              const SizedBox(height: 32.0),
              Center(
                child: Text(
                  'Add more info',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14.0,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              _buildInfoButtons(),
              const SizedBox(height: 32.0),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Saving to Local Vault',
                    style:
                        TextStyle(color: colorScheme.onSurface, fontSize: 14.0),
                  ),
                  const SizedBox(width: 8.0),
                  Container(
                    width: 20.0,
                    height: 20.0,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person,
                      size: 12.0,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 32.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoButtons() {
    return Wrap(
      spacing: 12.0,
      runSpacing: 12.0,
      alignment: WrapAlignment.center,
      children: [
        _buildInfoChip(Icons.email_outlined, 'Email', () {
          setState(() {
            _showEmail = true;
            _emailControllers.add(TextEditingController());
          });
        }),
        _buildInfoChip(Icons.cake_outlined, 'Birthday', () {
          setState(() {
            _showBirthday = true;
            _birthdayControllers.add(TextEditingController());
          });
        }),
        _buildInfoChip(Icons.location_on_outlined, 'Address', () {
          setState(() {
            _showAddress = true;
            _addressControllers.add(TextEditingController());
          });
        }),
        _buildInfoChip(Icons.label_outline, 'Labels', () {
          setState(() {
            _showLabels = true;
            _labelControllers.add(TextEditingController());
          });
        }),
        _buildInfoChip(Icons.add_box_outlined, 'Other', () {
          setState(() {
            _showOther = true;
            _otherControllers.add(TextEditingController());
          });
        }),
      ],
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _companyController.dispose();
    _notesController.dispose();
    for (var controller in _phoneControllers) {
      controller.dispose();
    }
    for (var controller in _emailControllers) {
      controller.dispose();
    }
    for (var controller in _addressControllers) {
      controller.dispose();
    }
    for (var controller in _labelControllers) {
      controller.dispose();
    }
    for (var controller in _birthdayControllers) {
      controller.dispose();
    }
    for (var controller in _otherControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
