import 'dart:convert';
import 'dart:typed_data';

import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Writes contacts as vCard 3.0, the format every contacts app imports
/// (Android, iOS, Google, Outlook). The reverse of `VCardParser`.
class VCardWriter {
  const VCardWriter();

  /// One card for [contact]. [photo] (JPEG) is embedded when given; leave it
  /// out for QR codes, which can't hold an image. [includeNotes] is off for
  /// QR codes too, to keep them small enough to scan.
  String write(
    VaultContact contact, {
    Uint8List? photo,
    bool includeNotes = true,
  }) {
    final StringBuffer out = StringBuffer();
    void line(String text) => out.write('${_fold(text)}\r\n');

    line('BEGIN:VCARD');
    line('VERSION:3.0');
    line('FN:${_escape(contact.displayName)}');
    line('N:${_escape(contact.lastName)};${_escape(contact.firstName)};;;');
    if (contact.company.trim().isNotEmpty) {
      line('ORG:${_escape(contact.company.trim())}');
    }
    for (final String phone in contact.phones) {
      line('TEL;TYPE=CELL:${_escape(phone)}');
    }
    for (final String email in contact.emails) {
      line('EMAIL;TYPE=INTERNET:${_escape(email)}');
    }
    for (final String address in contact.addresses) {
      // The whole address in the street part: the vault keeps it as one line.
      line('ADR;TYPE=HOME:;;${_escape(address)};;;;');
    }
    if (contact.birthdays.isNotEmpty) {
      line('BDAY:${_escape(contact.birthdays.first)}');
    }
    if (contact.labels.isNotEmpty) {
      line('CATEGORIES:${contact.labels.map(_escape).join(',')}');
    }
    for (final String item in contact.other) {
      if (item.startsWith('Nickname: ')) {
        line('NICKNAME:${_escape(item.substring(10))}');
      } else if (RegExp(r'^https?://').hasMatch(item)) {
        line('URL:${_escape(item)}');
      }
    }
    if (includeNotes && contact.notes.trim().isNotEmpty) {
      line('NOTE:${_escape(contact.notes.trim())}');
    }
    if (photo != null && photo.isNotEmpty) {
      line('PHOTO;ENCODING=b;TYPE=JPEG:${base64Encode(photo)}');
    }
    line('END:VCARD');
    return out.toString();
  }

  String writeAll(Iterable<VaultContact> contacts) =>
      contacts.map((VaultContact c) => write(c)).join();

  /// A file name for sharing [contact], e.g. `Ada Lovelace.vcf`.
  static String fileNameFor(VaultContact contact) {
    final String safe = contact.displayName
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '')
        .trim();
    return '${safe.isEmpty ? 'contact' : safe}.vcf';
  }

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  /// Folds lines longer than 75 characters (RFC 6350 / 2426): the rest
  /// continues on lines that start with a space.
  static String _fold(String text) {
    if (text.length <= 75) return text;
    final StringBuffer out = StringBuffer(text.substring(0, 75));
    for (int i = 75; i < text.length; i += 74) {
      final int end = i + 74 < text.length ? i + 74 : text.length;
      out.write('\r\n ${text.substring(i, end)}');
    }
    return out.toString();
  }
}
