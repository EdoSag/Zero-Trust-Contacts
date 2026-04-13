import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';

/// Manages local storage and cloud sync of contact profile pictures.
class ContactPhotoService {
  ContactPhotoService._();

  static final ContactPhotoService _instance = ContactPhotoService._();

  factory ContactPhotoService() => _instance;

  final ImagePicker _picker = ImagePicker();

  Future<Directory> _photosDir() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${appDir.path}/contact_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ── Picking ────────────────────────────────────────────────────────────────

  Future<XFile?> pickFromGallery() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
  }

  Future<XFile?> pickFromCamera() {
    return _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
  }

  // ── Local storage ──────────────────────────────────────────────────────────

  /// Copies [sourceFile] into the app's photo directory keyed by [contactId].
  Future<File> saveLocally(String contactId, File sourceFile) async {
    final Directory dir = await _photosDir();
    final File dest = File('${dir.path}/$contactId.jpg');
    return sourceFile.copy(dest.path);
  }

  /// Returns the local [File] for [contactId], or null if none exists.
  Future<File?> getLocalFile(String contactId) async {
    final Directory dir = await _photosDir();
    final File file = File('${dir.path}/$contactId.jpg');
    if (await file.exists()) return file;
    return null;
  }

  /// Deletes the local photo for [contactId] if it exists.
  Future<void> deleteLocally(String contactId) async {
    final Directory dir = await _photosDir();
    final File file = File('${dir.path}/$contactId.jpg');
    if (await file.exists()) await file.delete();
  }

  // ── Cloud sync ─────────────────────────────────────────────────────────────

  /// Uploads the local photo to Supabase Storage.
  /// Does nothing if there is no local photo.
  Future<void> uploadToCloud(String userId, String contactId) async {
    final File? file = await getLocalFile(contactId);
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    await SupabaseService().uploadContactPhoto(
      userId: userId,
      contactId: contactId,
      bytes: bytes,
    );
  }

  /// Downloads a photo from Supabase Storage and saves it locally.
  /// Returns true if the photo was downloaded successfully.
  Future<bool> downloadFromCloud(String userId, String contactId) async {
    final Uint8List? bytes = await SupabaseService().downloadContactPhoto(
      userId: userId,
      contactId: contactId,
    );
    if (bytes == null) return false;
    final Directory dir = await _photosDir();
    final File file = File('${dir.path}/$contactId.jpg');
    await file.writeAsBytes(bytes);
    return true;
  }

  /// Deletes the photo from Supabase Storage.
  Future<void> deleteFromCloud(String userId, String contactId) async {
    await SupabaseService().deleteContactPhoto(
      userId: userId,
      contactId: contactId,
    );
  }
}
