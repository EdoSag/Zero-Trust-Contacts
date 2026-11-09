import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/services/contact_photo_service.dart';

/// A contact's photo (decrypted on the phone), or the default person icon.
///
/// Pass [overridePhoto] to show a freshly picked image before it is saved
/// (while creating or editing a contact).
class ContactAvatar extends ConsumerStatefulWidget {
  const ContactAvatar({
    super.key,
    required this.contact,
    this.radius = 20.0,
    this.overridePhoto,
  });

  final VaultContact contact;
  final double radius;
  final File? overridePhoto;

  @override
  ConsumerState<ContactAvatar> createState() => _ContactAvatarState();
}

class _ContactAvatarState extends ConsumerState<ContactAvatar> {
  /// Decrypted photos by attachment id, for this session's lists.
  static final Map<String, Uint8List> _memory = <String, Uint8List>{};

  Uint8List? _bytes;

  String? get _photoId => widget.contact.photo?['id'] as String?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ContactAvatar old) {
    super.didUpdateWidget(old);
    if (old.contact.photo?['id'] != _photoId) _load();
  }

  Future<void> _load() async {
    final String? id = _photoId;
    if (id == null) {
      if (_bytes != null) setState(() => _bytes = null);
      return;
    }
    final Uint8List? cached = _memory[id];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final ContactPhotos photos =
          await ref.read(contactPhotosProvider.future);
      final Uint8List? bytes = await photos.read(widget.contact);
      if (bytes == null || !mounted || _photoId != id) return;
      if (_memory.length > 300) _memory.clear();
      _memory[id] = bytes;
      setState(() => _bytes = bytes);
    } on Object {
      // Locked or offline: keep the default icon.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final File? picked = widget.overridePhoto;
    final Uint8List? bytes = _bytes;
    if (picked != null || bytes != null) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundImage: picked != null
            ? FileImage(picked)
            : MemoryImage(bytes!) as ImageProvider,
        // A photo that doesn't decode leaves the plain avatar behind it.
        onBackgroundImageError: (Object _, StackTrace? __) {},
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
