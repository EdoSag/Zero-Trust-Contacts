import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/create_contact_page.dart';
import 'package:zerotrust_contacts/scan/business_card_parser.dart';

/// Takes the picture of a business card and reads the text on it.
///
/// The reading is done by Tesseract, an open-source recogniser that is part
/// of the app and runs on the phone. The picture is never uploaded, there
/// is no Google or cloud service involved, and the picture is deleted from
/// the app's temporary files as soon as it has been read.
class CardScanner {
  const CardScanner();

  static final ImagePicker _picker = ImagePicker();

  bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// The path of a picture from the camera or the photo library, or null
  /// when the user backs out. Big enough for small print to stay readable.
  Future<String?> takePicture({required bool fromCamera}) async {
    final XFile? file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
    );
    return file?.path;
  }

  /// The text on the card. Read twice, once for Hebrew and once for
  /// English, because reading for both at once muddles the word order.
  Future<String> readText(String imagePath) async {
    // 11: find text wherever it is, which suits the scattered blocks of a
    // card better than expecting one tidy paragraph.
    const Map<String, String> args = <String, String>{'psm': '11'};
    final String english = await FlutterTesseractOcr.extractText(
      imagePath,
      language: 'eng',
      args: args,
    );
    final String hebrew = await FlutterTesseractOcr.extractText(
      imagePath,
      language: 'heb',
      args: args,
    );
    return BusinessCardParser.mergeReadings(hebrew: hebrew, english: english);
  }

  /// Removes the picture once it has been read.
  Future<void> discard(String imagePath) async {
    try {
      await File(imagePath).delete();
    } on Object {
      // Already gone: nothing to do.
    }
  }
}

final cardScannerProvider = Provider<CardScanner>((_) => const CardScanner());

/// Scan a card, then open the contact editor filled in with what was read
/// so the user can fix anything before saving. Returns the saved contact,
/// or null when nothing was saved.
Future<VaultContact?> scanBusinessCard(
  BuildContext context,
  WidgetRef ref,
) async {
  final CardScanner scanner = ref.read(cardScannerProvider);
  final NavigatorState navigator = Navigator.of(context);
  // Outlives the screen that started the scan, which a lock takes away.
  final ProviderContainer container = ProviderScope.containerOf(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final bool? fromCamera = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'The card is read on this phone. The picture is not uploaded '
              'and is deleted once it has been read.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo of the card'),
            onTap: () => Navigator.of(context).pop(true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
  if (fromCamera == null) return null;

  final String? path = await ref
      .read(vaultControllerProvider.notifier)
      .whileShowingSystemUi(() => scanner.takePicture(fromCamera: fromCamera));
  if (path == null || !navigator.mounted) return null;

  final DialogRoute<void> reading = DialogRoute<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Reading the card…')),
          ],
        ),
      ),
    ),
  );
  navigator.push(reading).ignore();

  ScannedCard? card;
  String? problem;
  try {
    card = const BusinessCardParser().parse(await scanner.readText(path));
  } on Object catch (error) {
    problem = 'The card could not be read: $error';
  } finally {
    // The picker hands over its own temporary copy, never the original
    // in the photo library, so this only removes the app's copy.
    await scanner.discard(path);
  }
  if (!navigator.mounted) return null;
  // The vault can lock while the card is being read (the app went to the
  // background, the auto-lock ran out). The lock screen has then already
  // cleared the pages above it, and nothing may open over it.
  final bool stillOpen = reading.isActive;
  if (stillOpen) navigator.removeRoute(reading);
  if (!stillOpen || container.read(vaultControllerProvider) is! VaultUnlocked) {
    return null;
  }

  if (card == null || card.isEmpty) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            problem ??
                'No details could be read from that picture. Try again '
                    'in good light with the card filling the frame.',
          ),
        ),
      );
    return null;
  }
  return navigator.push<VaultContact>(
    MaterialPageRoute<VaultContact>(
      builder: (_) => CreateContactPage(
        prefill: card!.toContact(),
        createActivity: 'contact_scan_card',
      ),
    ),
  );
}
