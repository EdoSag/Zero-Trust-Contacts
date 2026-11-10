import 'package:zerotrust_contacts/models/vault_contact.dart';

/// How names are ordered and grouped in the list, for mixed English and
/// Hebrew (and other scripts): letters first, script by script, then
/// everything that doesn't start with a letter under "#".
class ContactSorting {
  const ContactSorting._();

  /// The text a contact is sorted by: its name as shown, or last name first
  /// when [byLastName] and the contact has one.
  static String sortName(VaultContact contact, {bool byLastName = false}) {
    if (byLastName && contact.lastName.trim().isNotEmpty) {
      return '${contact.lastName.trim()} ${contact.firstName.trim()}'.trim();
    }
    return contact.displayName.trim();
  }

  /// The section a name is listed under: "A" to "Z", a Hebrew letter, the
  /// first letter of another script, or "#".
  static String sectionOf(String name) {
    for (final int rune in name.runes) {
      if (_skippable(rune)) {
        continue;
      }
      final String letter = _fold(String.fromCharCode(rune));
      if (letter.isEmpty) {
        break;
      }
      final int code = letter.runes.first;
      if (code >= 0x41 && code <= 0x5A) {
        return letter;
      }
      if (code >= 0x05D0 && code <= 0x05EA) {
        return _hebrewBase[letter] ?? letter;
      }
      if (_isLetter(code)) {
        return letter;
      }
      break;
    }
    return '#';
  }

  static int compare(
    VaultContact a,
    VaultContact b, {
    bool byLastName = false,
  }) => compareNames(
    sortName(a, byLastName: byLastName),
    sortName(b, byLastName: byLastName),
  );

  static int compareNames(String a, String b) {
    final String sa = sectionOf(a);
    final String sb = sectionOf(b);
    if (sa != sb) {
      // "#" (numbers, symbols, no name) goes last.
      if (sa == '#') return 1;
      if (sb == '#') return -1;
      return sa.runes.first.compareTo(sb.runes.first);
    }
    final int folded = _key(a).compareTo(_key(b));
    return folded != 0 ? folded : a.compareTo(b);
  }

  static String _key(String name) => name.runes
      .where((int r) => !_skippable(r))
      .map((int r) => _fold(String.fromCharCode(r)))
      .join();

  /// Hebrew points and cantillation, combining accents, direction marks,
  /// spaces and punctuation in front of a name.
  static bool _skippable(int rune) =>
      (rune >= 0x0591 && rune <= 0x05C7) ||
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x200B && rune <= 0x200F) ||
      (rune >= 0x202A && rune <= 0x202E) ||
      (rune >= 0x2066 && rune <= 0x2069) ||
      rune == 0x20 ||
      rune == 0x22 ||
      rune == 0x27 ||
      rune == 0x28;

  static bool _isLetter(int code) =>
      (code >= 0xC0 && code <= 0x024F) ||
      (code >= 0x0370 && code <= 0x058F) ||
      (code >= 0x0600 && code <= 0x06FF) ||
      (code >= 0x0900 && code <= 0xD7FF);

  /// Upper case, with common accented Latin letters as their base letter.
  static String _fold(String char) {
    final String upper = char.toUpperCase();
    return _latinBase[upper] ?? upper;
  }

  /// Final forms sort and group with their regular letter.
  static const Map<String, String> _hebrewBase = <String, String>{
    'ך': 'כ',
    'ם': 'מ',
    'ן': 'נ',
    'ף': 'פ',
    'ץ': 'צ',
  };

  static const Map<String, String> _latinBase = <String, String>{
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A', //
    'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', //
    'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I', 'Ñ': 'N', //
    'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O', //
    'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y', //
    'Š': 'S', 'Ž': 'Z', 'Ł': 'L', 'Ń': 'N', 'Ś': 'S', 'Ć': 'C',
  };
}
