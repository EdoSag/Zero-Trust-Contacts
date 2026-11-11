import 'dart:convert';
import 'dart:typed_data';

/// Turns the bytes of an exported contacts file into text.
///
/// Exports come in several encodings: UTF-8 (Google, iCloud), UTF-8 with a
/// byte order mark (Outlook.com), UTF-16 (older Outlook and Excel "Unicode
/// text"), Windows-1255 (Hebrew Outlook and Excel on Windows) and
/// Windows-1252 (the same in Western languages). Pure Dart, so it runs on
/// the device and in tests.
String decodeContactFile(List<int> input) {
  final Uint8List bytes = input is Uint8List
      ? input
      : Uint8List.fromList(input);
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), littleEndian: false);
  }
  // UTF-16 without a byte order mark: every other byte of plain text is 0.
  if (bytes.length >= 4) {
    final int sample = bytes.length < 400 ? bytes.length : 400;
    int zeroOdd = 0;
    int zeroEven = 0;
    for (int i = 0; i < sample; i++) {
      if (bytes[i] == 0) {
        i.isOdd ? zeroOdd++ : zeroEven++;
      }
    }
    if (zeroOdd > sample / 4) {
      return _utf16(bytes, littleEndian: true);
    }
    if (zeroEven > sample / 4) {
      return _utf16(bytes, littleEndian: false);
    }
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Not valid UTF-8: a Windows "ANSI" file, Hebrew or Western. Plain
    // Latin text reads the same in both; the other letters tell them apart.
    return _looksWestern(bytes) ? _windows1252(bytes) : _windows1255(bytes);
  }
}

bool _isLatinLetter(int b) =>
    (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);

/// A Hebrew letter in Windows-1255, an accented small letter in 1252.
bool _isHighLetter(int b) => b >= 0xE0 && b <= 0xFA;

/// Whether an "ANSI" file is Windows-1252 (Western) and not Windows-1255
/// (Hebrew). The file doesn't say, so this goes by its letters: a byte
/// that means nothing in 1255, a capital like É with no Hebrew letter in
/// front of it (there the byte is a vowel point, which follows a letter),
/// or letters that sit inside Latin words (René, Müller) more often than
/// next to each other (Hebrew words).
bool _looksWestern(Uint8List bytes) {
  int inLatinWord = 0;
  int inHighWord = 0;
  for (int i = 0; i < bytes.length; i++) {
    final int b = bytes[i];
    if (b < 0x80) continue;
    if (_cp1255High[b - 0x80] == 0xFFFD) return true;
    final int before = i > 0 ? bytes[i - 1] : 0x20;
    final int after = i + 1 < bytes.length ? bytes[i + 1] : 0x20;
    if (b >= 0xC0 && b <= 0xD8) {
      if (!(before >= 0xC0 && before <= 0xFA)) return true;
    } else if (_isHighLetter(b)) {
      if (_isLatinLetter(before) || _isLatinLetter(after)) {
        inLatinWord++;
      } else {
        inHighWord++;
      }
    }
  }
  return inLatinWord > inHighWord;
}

/// Windows-1252 bytes 0x80-0x9F; the rest match Unicode. Unused positions
/// map to U+FFFD.
const List<int> _cp1252C1 = <int>[
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
];

String _windows1252(Uint8List bytes) => String.fromCharCodes(<int>[
  for (final int b in bytes)
    b >= 0x80 && b <= 0x9F ? _cp1252C1[b - 0x80] : b,
]);

String _utf16(Uint8List bytes, {required bool littleEndian}) {
  final List<int> units = <int>[];
  for (int i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

/// Windows-1255 bytes 0x80-0xFF. Unused positions map to U+FFFD.
const List<int> _cp1255High = <int>[
  // 0x80
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0xFFFD, 0x2039, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD,
  // 0x90
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0xFFFD, 0x203A, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD,
  // 0xA0
  0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x20AA, 0x00A5, 0x00A6, 0x00A7,
  0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF,
  // 0xB0
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7,
  0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF,
  // 0xC0: Hebrew points
  0x05B0, 0x05B1, 0x05B2, 0x05B3, 0x05B4, 0x05B5, 0x05B6, 0x05B7,
  0x05B8, 0x05B9, 0x05BA, 0x05BB, 0x05BC, 0x05BD, 0x05BE, 0x05BF,
  // 0xD0
  0x05C0, 0x05C1, 0x05C2, 0x05C3, 0x05F0, 0x05F1, 0x05F2, 0x05F3,
  0x05F4, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD,
  // 0xE0: Hebrew letters alef to tav
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7,
  0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF,
  // 0xF0
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7,
  0x05E8, 0x05E9, 0x05EA, 0xFFFD, 0xFFFD, 0x200E, 0x200F, 0xFFFD,
];

String _windows1255(Uint8List bytes) => String.fromCharCodes(<int>[
  for (final int b in bytes) b < 0x80 ? b : _cp1255High[b - 0x80],
]);

/// What kind of contacts file some text is, judged by its content rather
/// than its name (shared files often arrive without an extension).
enum ContactFileKind { vCard, csv, unknown }

ContactFileKind detectContactFileKind(String text) {
  final String head = text.length > 4000 ? text.substring(0, 4000) : text;
  if (head.toUpperCase().contains('BEGIN:VCARD')) {
    return ContactFileKind.vCard;
  }
  final String firstLine = head.trimLeft().split(RegExp(r'\r?\n')).first;
  if (RegExp(r'[,;\t]').hasMatch(firstLine) && text.contains('\n')) {
    return ContactFileKind.csv;
  }
  return ContactFileKind.unknown;
}
