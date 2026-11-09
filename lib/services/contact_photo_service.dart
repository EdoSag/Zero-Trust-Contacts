import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Contact photos as encrypted attachments: each photo has its own key,
/// kept inside the contact, and is encrypted on the phone before upload.
class ContactPhotos {
  ContactPhotos(this._attachments);

  final ZtAttachments _attachments;

  /// Encrypts and stores [bytes]; returns the reference to keep in the
  /// contact (`VaultContact.photo`).
  Future<Map<String, Object?>> store(Uint8List bytes) async {
    final ZtAttachmentRef ref =
        await _attachments.put(bytes, mimeType: 'image/jpeg');
    return ref.toJson();
  }

  Future<Map<String, Object?>> storeFile(File file) async =>
      store(await file.readAsBytes());

  /// The photo of [contact], or null when it has none (or it can't be
  /// fetched right now).
  Future<Uint8List?> read(VaultContact contact) async {
    final Map<String, Object?>? json = contact.photo;
    if (json == null) {
      return null;
    }
    try {
      return await _attachments.read(ZtAttachmentRef.fromJson(json));
    } on Object {
      return null;
    }
  }

  Future<void> deletePhotoOf(VaultContact contact) async {
    final Map<String, Object?>? json = contact.photo;
    if (json == null) {
      return;
    }
    try {
      await _attachments.delete(ZtAttachmentRef.fromJson(json));
    } on Object {
      // Best effort: an orphaned encrypted file reveals nothing.
    }
  }
}

/// Picks a photo. Call through `VaultController.whileShowingSystemUi`, so
/// the vault doesn't lock while the picker covers the app.
class PhotoPicker {
  const PhotoPicker();

  static final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickFromGallery() => _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

  Future<XFile?> pickFromCamera() => _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
}
