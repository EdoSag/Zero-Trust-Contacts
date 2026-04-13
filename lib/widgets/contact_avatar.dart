import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';

/// Displays a contact's profile picture if one is saved locally, otherwise
/// falls back to the default person icon.
///
/// Pass [overridePhoto] to show a freshly-picked image before it is persisted
/// (e.g. while creating or editing a contact).
class ContactAvatar extends StatefulWidget {
  const ContactAvatar({
    super.key,
    required this.contact,
    this.radius = 20.0,
    this.overridePhoto,
  });

  final VaultContact contact;
  final double radius;

  /// When non-null this file is shown directly without a disk look-up.
  final File? overridePhoto;

  @override
  State<ContactAvatar> createState() => _ContactAvatarState();
}

class _ContactAvatarState extends State<ContactAvatar> {
  File? _localPhoto;

  @override
  void initState() {
    super.initState();
    if (widget.overridePhoto != null) {
      _localPhoto = widget.overridePhoto;
    } else {
      _loadFromDisk();
    }
  }

  @override
  void didUpdateWidget(ContactAvatar old) {
    super.didUpdateWidget(old);
    if (widget.overridePhoto != old.overridePhoto) {
      setState(() => _localPhoto = widget.overridePhoto);
    } else if (widget.contact.photoPath != old.contact.photoPath ||
        widget.contact.id != old.contact.id) {
      _loadFromDisk();
    }
  }

  Future<void> _loadFromDisk() async {
    if (widget.contact.photoPath == null) {
      if (mounted) setState(() => _localPhoto = null);
      return;
    }
    final File? file =
        await ContactPhotoService().getLocalFile(widget.contact.id);
    if (mounted) setState(() => _localPhoto = file);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    if (_localPhoto != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: FileImage(_localPhoto!),
      );
    }

    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(
        Icons.person,
        size: widget.radius,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }
}
