/// Turns what a contact QR code holds into vCard text the importer reads:
/// a vCard as is, or a MECARD (the short form many QR generators use)
/// converted. Null when the code is not a contact.
String? vCardFromQr(String raw) {
  final String text = raw.trim();
  if (text.toUpperCase().contains('BEGIN:VCARD')) {
    return text;
  }
  if (!text.toUpperCase().startsWith('MECARD:')) {
    return null;
  }
  // Split on ';' that isn't escaped with a backslash.
  final List<String> fields = <String>[];
  final StringBuffer current = StringBuffer();
  final String body = text.substring('MECARD:'.length);
  for (int i = 0; i < body.length; i += 1) {
    final String char = body[i];
    if (char == r'\' && i + 1 < body.length) {
      current.write(body[i + 1]);
      i += 1;
    } else if (char == ';') {
      fields.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) {
    fields.add(current.toString());
  }

  String esc(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');

  final List<String> lines = <String>['BEGIN:VCARD', 'VERSION:3.0'];
  for (final String field in fields) {
    final int colon = field.indexOf(':');
    if (colon <= 0) {
      continue;
    }
    final String key = field.substring(0, colon).trim().toUpperCase();
    final String value = field.substring(colon + 1).trim();
    if (value.isEmpty) {
      continue;
    }
    switch (key) {
      case 'N':
        // MECARD names are "Last,First".
        final List<String> parts = value.split(',');
        final String last = parts.first.trim();
        final String first = parts.skip(1).join(' ').trim();
        lines
          ..add('N:${esc(last)};${esc(first)};;;')
          ..add('FN:${esc('$first $last'.trim())}');
      case 'TEL':
        lines.add('TEL:${esc(value)}');
      case 'EMAIL':
        lines.add('EMAIL:${esc(value)}');
      case 'ADR':
        lines.add('ADR:;;${esc(value)};;;;');
      case 'ORG':
        lines.add('ORG:${esc(value)}');
      case 'NOTE':
        lines.add('NOTE:${esc(value)}');
      case 'URL':
        lines.add('URL:${esc(value)}');
      case 'BDAY':
        lines.add('BDAY:${esc(value)}');
    }
  }
  if (lines.length == 2) {
    return null;
  }
  lines.add('END:VCARD');
  return lines.join('\r\n');
}
