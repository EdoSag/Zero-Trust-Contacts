import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:zerotrust_contacts/import/mecard.dart';
import 'package:zerotrust_contacts/pages/google_import_page.dart';

/// Scans a contact QR code (a vCard or MECARD, like the one "Show QR code"
/// makes) with the camera. The picture never leaves the phone: the code is
/// read on the device.
///
/// Pops with the contact as vCard text, or null.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Scans a code, then shows what importing it would add. True when a
  /// contact was imported.
  static Future<bool> scanAndImport(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    final String? vCard = await navigator.push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (vCard == null) {
      return false;
    }
    final bool? imported = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => GoogleImportPage(vCardText: vCard, vCardName: 'QR code'),
      ),
    );
    return imported == true;
  }

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final GlobalKey _viewKey = GlobalKey(debugLabel: 'qr');
  StreamSubscription<Barcode>? _scans;
  bool _done = false;
  bool _denied = false;
  String? _hint;

  void _onCreated(QRViewController controller) {
    _scans = controller.scannedDataStream.listen((Barcode scan) {
      final String? code = scan.code;
      if (_done || code == null || !mounted) {
        return;
      }
      final String? vCard = vCardFromQr(code);
      if (vCard == null) {
        setState(() => _hint = 'That code is not a contact.');
        return;
      }
      _done = true;
      controller.pauseCamera();
      Navigator.of(context).pop(vCard);
    });
  }

  @override
  void dispose() {
    _scans?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a contact QR code')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _denied
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Allow the camera for ZT Contacts in the phone\'s '
                        'settings to scan a code.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : QRView(
                    key: _viewKey,
                    onQRViewCreated: _onCreated,
                    formatsAllowed: const <BarcodeFormat>[BarcodeFormat.qrcode],
                    overlay: QrScannerOverlayShape(
                      borderColor: colors.primary,
                      borderRadius: 16,
                      borderLength: 32,
                      borderWidth: 8,
                      cutOutSize: 260,
                    ),
                    onPermissionSet: (QRViewController _, bool granted) {
                      if (!granted && mounted) {
                        setState(() => _denied = true);
                      }
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _hint ??
                  'Point the camera at a contact QR code. It is read on this '
                  'phone only.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
