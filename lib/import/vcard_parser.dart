import 'dart:convert';
import 'dart:typed_data';

import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Parses vCard 2.1 / 3.0 / 4.0 text into [VaultContact]s.
///
/// Written for the files Google Contacts produces (contacts.google.com →
/// Export → vCard), but it also handles iCloud, Outlook and Android exports:
/// folded lines, `item1.` group prefixes, parameters, quoted-printable and
/// the escaped `N`, `ORG` and `ADR` components.
///
/// Pure Dart, runs entirely on the device: nothing is sent anywhere.
class VCardParser {
  const VCardParser({this.source = 'Saved'});

  /// The `source` written on each parsed contact.
  final String source;

  /// Google adds these system groups to CATEGORIES; they are not real labels.
  static const Set<String> _systemCategories = <String>{
    'mycontacts',
    'my contacts',
    'starred',
    'starred in android',
    'imported on',
  };

  List<VaultContact> parse(String raw) => parseWithPhotos(raw).contacts;

  /// Like [parse], plus each card's photo: embedded image bytes, or a link
  /// (Google's exports link to the photo instead of embedding it).
  VCardImport parseWithPhotos(String raw) {
    final List<VaultContact> contacts = <VaultContact>[];
    final Map<String, VCardPhoto> photos = <String, VCardPhoto>{};
    _CardBuilder? card;
    for (final _VCardLine line in _logicalLines(raw)) {
      final String name = line.name;
      if (name == 'BEGIN' && line.value.toUpperCase() == 'VCARD') {
        card = _CardBuilder();
        continue;
      }
      if (name == 'END' && line.value.toUpperCase() == 'VCARD') {
        final VaultContact? contact = card?.build(source);
        if (contact != null) {
          contacts.add(contact);
          final VCardPhoto? photo = card?.photo;
          if (photo != null) {
            photos[contact.id] = photo;
          }
        }
        card = null;
        continue;
      }
      if (card == null) {
        continue;
      }
      _apply(card, line);
    }
    return VCardImport(contacts: contacts, photos: photos);
  }

  void _apply(_CardBuilder card, _VCardLine line) {
    switch (line.name) {
      case 'FN':
        card.displayName = _unescape(line.value);
        break;
      case 'N':
        final List<String> parts = _splitComponents(line.value);
        card.lastName = parts.isNotEmpty ? parts[0] : '';
        final List<String> given = <String>[
          if (parts.length > 1) parts[1],
          if (parts.length > 2) parts[2],
        ].where((String e) => e.isNotEmpty).toList();
        card.firstName = given.join(' ');
        break;
      case 'TEL':
        final String phone = _unescape(
          line.value,
        ).replaceFirst(RegExp(r'^tel:'), '');
        card.phones.add(phone);
        card.setType('phone', phone, line.types, VaultContact.phoneTypes);
        break;
      case 'EMAIL':
        final String email = _unescape(line.value);
        card.emails.add(email);
        card.setType('email', email, line.types, VaultContact.emailTypes);
        break;
      case 'ORG':
        card.company = _splitComponents(
          line.value,
        ).where((String e) => e.isNotEmpty).join(', ');
        break;
      case 'TITLE':
        card.title = _unescape(line.value);
        break;
      case 'NOTE':
        card.notes.add(_unescape(line.value));
        break;
      case 'BDAY':
        final String? birthday = normalizeBirthday(_unescape(line.value));
        if (birthday != null) {
          card.birthdays.add(birthday);
        }
        break;
      case 'ADR':
        final String address = _splitComponents(line.value)
            .map((String e) => e.trim())
            .where((String e) => e.isNotEmpty)
            .join(', ');
        if (address.isNotEmpty) {
          card.addresses.add(address);
          card.setType(
            'address',
            address,
            line.types,
            VaultContact.addressTypes,
          );
        }
        break;
      case 'CATEGORIES':
        for (final String category in _splitList(line.value)) {
          final String lower = category.toLowerCase();
          if (lower == 'starred' || lower == 'starred in android') {
            card.isFavorite = true;
          } else if (!_systemCategories.contains(lower) &&
              !lower.startsWith('imported on')) {
            card.labels.add(category);
          }
        }
        break;
      case 'URL':
        card.other.add(_unescape(line.value));
        break;
      case 'PHOTO':
        card.photo ??= VCardPhoto.tryParse(line.value, line.params);
        break;
      case 'NICKNAME':
        final String nickname = _unescape(line.value);
        if (nickname.isNotEmpty) {
          card.other.add('Nickname: $nickname');
        }
        break;
      case 'X-ANNIVERSARY':
      case 'ANNIVERSARY':
        card.other.add('Anniversary: ${_unescape(line.value)}');
        break;
      default:
        break;
    }
  }

  /// Turns a vCard/Android birthday into `YYYY-MM-DD`, or `--MM-DD` when the
  /// year is unknown. Returns null for values that are not a date.
  static String? normalizeBirthday(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final RegExpMatch? noYear = RegExp(
      r'^--(\d{2})-?(\d{2})$',
    ).firstMatch(value);
    if (noYear != null) {
      return '--${noYear.group(1)}-${noYear.group(2)}';
    }
    final RegExpMatch? full = RegExp(
      r'^(\d{4})-?(\d{2})-?(\d{2})',
    ).firstMatch(value);
    if (full != null) {
      // iCloud and Outlook write 1604 / 4501 when the year is unknown.
      if (full.group(1) == '1604' || full.group(1) == '4501') {
        return '--${full.group(2)}-${full.group(3)}';
      }
      return '${full.group(1)}-${full.group(2)}-${full.group(3)}';
    }
    return null;
  }

  /// Unfolds continuation lines and splits each into name, params and value.
  Iterable<_VCardLine> _logicalLines(String raw) sync* {
    final List<String> physical = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final List<String> logical = <String>[];
    for (final String line in physical) {
      if (logical.isNotEmpty &&
          logical.last.endsWith('=') &&
          _isQuotedPrintable(logical.last)) {
        // vCard 2.1 quoted-printable soft line break: the continuation is
        // taken as-is, leading whitespace included. Checked before folding.
        logical[logical.length - 1] =
            logical.last.substring(0, logical.last.length - 1) + line;
      } else if (logical.isNotEmpty &&
          (line.startsWith(' ') || line.startsWith('\t'))) {
        // RFC 6350 folding: drop the single leading whitespace.
        logical[logical.length - 1] += line.substring(1);
      } else {
        logical.add(line);
      }
    }
    for (final String line in logical) {
      final _VCardLine? parsed = _VCardLine.tryParse(line);
      if (parsed != null) {
        yield parsed;
      }
    }
  }

  static bool _isQuotedPrintable(String line) {
    final int colon = line.indexOf(':');
    if (colon == -1) {
      return false;
    }
    return line.substring(0, colon).toUpperCase().contains('QUOTED-PRINTABLE');
  }

  /// Splits on unescaped `;` (structured values such as N, ADR, ORG).
  static List<String> _splitComponents(String value) {
    return _splitUnescaped(value, ';').map(_unescape).toList();
  }

  /// Splits on unescaped `,` (list values such as CATEGORIES).
  static List<String> _splitList(String value) {
    return _splitUnescaped(value, ',')
        .map(_unescape)
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  static List<String> _splitUnescaped(String value, String separator) {
    final List<String> parts = <String>[];
    final StringBuffer current = StringBuffer();
    for (int i = 0; i < value.length; i += 1) {
      final String char = value[i];
      if (char == r'\' && i + 1 < value.length) {
        current
          ..write(char)
          ..write(value[i + 1]);
        i += 1;
      } else if (char == separator) {
        parts.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    parts.add(current.toString());
    return parts;
  }

  static String _unescape(String value) {
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < value.length; i += 1) {
      final String char = value[i];
      if (char == r'\' && i + 1 < value.length) {
        final String next = value[i + 1];
        out.write(next == 'n' || next == 'N' ? '\n' : next);
        i += 1;
      } else {
        out.write(char);
      }
    }
    return out.toString().trim();
  }
}

/// Contacts read from a vCard file, with the photos found in it.
class VCardImport {
  VCardImport({required this.contacts, required this.photos});

  final List<VaultContact> contacts;

  /// Photos by contact id.
  final Map<String, VCardPhoto> photos;

  int get embeddedPhotoCount =>
      photos.values.where((VCardPhoto p) => p.bytes != null).length;
  int get linkedPhotoCount =>
      photos.values.where((VCardPhoto p) => p.url != null).length;
}

/// A card's PHOTO: either the image itself or an https link to it.
class VCardPhoto {
  VCardPhoto.bytes(Uint8List this.bytes) : url = null;
  VCardPhoto.link(Uri this.url) : bytes = null;

  final Uint8List? bytes;
  final Uri? url;

  /// Reads `PHOTO;ENCODING=b:...`, `PHOTO;BASE64:...` (2.1),
  /// `PHOTO:data:image/jpeg;base64,...` (4.0) and `PHOTO:https://...`.
  static VCardPhoto? tryParse(String value, Map<String, String> params) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final String encoding = (params['ENCODING'] ?? '').toUpperCase();
    String? base64Text;
    if (encoding == 'B' || encoding == 'BASE64') {
      base64Text = trimmed;
    } else if (trimmed.startsWith('data:')) {
      final int comma = trimmed.indexOf(',');
      if (comma == -1 || !trimmed.substring(0, comma).contains('base64')) {
        return null;
      }
      base64Text = trimmed.substring(comma + 1);
    }
    if (base64Text != null) {
      try {
        final Uint8List bytes = base64Decode(
          base64.normalize(base64Text.replaceAll(RegExp(r'\s'), '')),
        );
        return bytes.isEmpty ? null : VCardPhoto.bytes(bytes);
      } on FormatException {
        return null;
      }
    }
    final Uri? url = Uri.tryParse(trimmed);
    return url != null && url.scheme == 'https' && url.host.isNotEmpty
        ? VCardPhoto.link(url)
        : null;
  }
}

class _VCardLine {
  _VCardLine(this.name, this.params, this.value);

  /// Upper-case property name without any `item1.` group prefix.
  final String name;
  final Map<String, String> params;
  final String value;

  /// Every TYPE value, lower case (`TYPE=CELL,VOICE`, `;TYPE=WORK;TYPE=pref`
  /// and vCard 2.1's bare `;CELL` all end up here).
  final Set<String> types = <String>{};

  static _VCardLine? tryParse(String line) {
    if (line.trim().isEmpty) {
      return null;
    }
    // The first ':' outside double quotes ends the name+params part.
    int colon = -1;
    bool quoted = false;
    for (int i = 0; i < line.length; i += 1) {
      if (line[i] == '"') {
        quoted = !quoted;
      } else if (line[i] == ':' && !quoted) {
        colon = i;
        break;
      }
    }
    if (colon == -1) {
      return null;
    }
    final List<String> head = line.substring(0, colon).split(';');
    String name = head.first.trim().toUpperCase();
    final int dot = name.lastIndexOf('.');
    if (dot != -1) {
      name = name.substring(dot + 1);
    }
    final Map<String, String> params = <String, String>{};
    final Set<String> allTypes = <String>{};
    for (final String param in head.skip(1)) {
      final int eq = param.indexOf('=');
      if (eq == -1) {
        // vCard 2.1 bare parameter, e.g. TEL;CELL or ;QUOTED-PRINTABLE
        final String upper = param.trim().toUpperCase();
        if (upper == 'QUOTED-PRINTABLE' || upper == 'BASE64') {
          params['ENCODING'] = upper;
        } else {
          params['TYPE'] = upper;
          allTypes.add(upper.toLowerCase());
        }
      } else {
        final String key = param.substring(0, eq).trim().toUpperCase();
        final String paramValue = param
            .substring(eq + 1)
            .trim()
            .replaceAll('"', '');
        params[key] = paramValue;
        if (key == 'TYPE') {
          allTypes.addAll(
            paramValue
                .split(',')
                .map((String t) => t.trim().toLowerCase())
                .where((String t) => t.isNotEmpty),
          );
        }
      }
    }
    String value = line.substring(colon + 1);
    if ((params['ENCODING'] ?? '').toUpperCase() == 'QUOTED-PRINTABLE') {
      value = _decodeQuotedPrintable(value, params['CHARSET']);
    }
    return _VCardLine(name, params, value)..types.addAll(allTypes);
  }

  static String _decodeQuotedPrintable(String value, String? charset) {
    final List<int> bytes = <int>[];
    for (int i = 0; i < value.length; i += 1) {
      final String char = value[i];
      if (char == '=' && i + 2 < value.length) {
        final int? byte = int.tryParse(
          value.substring(i + 1, i + 3),
          radix: 16,
        );
        if (byte != null) {
          bytes.add(byte);
          i += 2;
          continue;
        }
      }
      bytes.addAll(utf8.encode(char));
    }
    final String normalizedCharset = (charset ?? 'UTF-8').toUpperCase();
    if (normalizedCharset == 'ISO-8859-1' || normalizedCharset == 'LATIN1') {
      return latin1.decode(bytes, allowInvalid: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

class _CardBuilder {
  String displayName = '';
  String firstName = '';
  String lastName = '';
  String company = '';
  String title = '';
  bool isFavorite = false;
  VCardPhoto? photo;
  final Map<String, String> valueTypes = <String, String>{};

  /// Remembers the kind of [value] from a line's TYPE values, when one of
  /// them is a kind the vault knows ([allowed]).
  void setType(
    String field,
    String value,
    Set<String> types,
    List<String> allowed,
  ) {
    const Map<String, String> aliases = <String, String>{
      'cell': 'mobile',
      'iphone': 'mobile',
    };
    for (final String raw in types) {
      final String type = aliases[raw] ?? raw;
      if (allowed.contains(type)) {
        valueTypes.putIfAbsent(VaultContact.typeKey(field, value), () => type);
        return;
      }
    }
  }

  final List<String> notes = <String>[];
  final List<String> phones = <String>[];
  final List<String> emails = <String>[];
  final List<String> addresses = <String>[];
  final List<String> labels = <String>[];
  final List<String> birthdays = <String>[];
  final List<String> other = <String>[];

  VaultContact? build(String source) {
    final List<String> cleanPhones = _unique(
      phones,
      VaultContact.normalizedPhone,
    );
    final List<String> cleanEmails = _unique(
      emails,
      VaultContact.normalizedEmail,
    );
    final String fullCompany = <String>[
      if (title.isNotEmpty) title,
      if (company.isNotEmpty) company,
    ].join(company.isNotEmpty && title.isNotEmpty ? ', ' : '');
    final bool hasAnything =
        displayName.isNotEmpty ||
        firstName.isNotEmpty ||
        lastName.isNotEmpty ||
        fullCompany.isNotEmpty ||
        cleanPhones.isNotEmpty ||
        cleanEmails.isNotEmpty;
    if (!hasAnything) {
      return null;
    }
    return VaultContact.fromLegacyPayload(<String, dynamic>{
      'id': VaultContact.generateId(),
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'company': fullCompany,
      'notes': notes.where((String e) => e.isNotEmpty).join('\n\n'),
      'phones': cleanPhones,
      'emails': cleanEmails,
      'addresses': _unique(addresses, (String e) => e.toLowerCase()),
      'labels': _unique(labels, (String e) => e.toLowerCase()),
      'birthdays': _unique(birthdays, (String e) => e),
      'other': _unique(other, (String e) => e.toLowerCase()),
      'isFavorite': isFavorite,
      'source': source,
      'valueTypes': valueTypes,
    });
  }

  static List<String> _unique(
    List<String> values,
    String Function(String) normalize,
  ) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final String raw in values) {
      final String value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      if (seen.add(normalize(value))) {
        out.add(value);
      }
    }
    return out;
  }
}
