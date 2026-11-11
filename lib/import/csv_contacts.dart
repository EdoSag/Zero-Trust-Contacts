import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// Which program a contacts spreadsheet came from, judged by its columns.
enum CsvContactFormat { google, outlook, generic }

/// Contacts read from a spreadsheet, and the program it looks like it came
/// from (shown in the preview and the activity log).
class CsvContactsImport {
  CsvContactsImport({required this.contacts, required this.format});

  final List<VaultContact> contacts;
  final CsvContactFormat format;
}

/// Reads contacts from CSV files: Google Contacts' "Google CSV", Outlook
/// (desktop, Outlook.com and new Outlook, in English or Hebrew), and plain
/// spreadsheets with columns such as Name, Phone and Email.
///
/// Columns are recognised by name, so the order doesn't matter and columns
/// it doesn't know are skipped. Pure Dart: runs on the device, nothing is
/// sent anywhere.
class CsvContactsParser {
  const CsvContactsParser({this.source = 'Saved'});

  final String source;

  CsvContactsImport parse(String text) {
    final List<List<String>> rows = parseCsvRows(text);
    if (rows.isEmpty) {
      return CsvContactsImport(
        contacts: <VaultContact>[],
        format: CsvContactFormat.generic,
      );
    }
    final List<_Column> columns = <_Column>[
      for (int i = 0; i < rows.first.length; i++) _Column.of(i, rows.first[i]),
    ];
    final CsvContactFormat format = _formatOf(rows.first);
    final List<List<String>> body = rows.skip(1).toList();
    final _DateOrder dates = _DateOrder.guess(<String>[
      for (final List<String> row in body)
        for (final _Column c in columns)
          if (c.role == _Role.birthday && c.index < row.length) row[c.index],
    ]);
    final List<VaultContact> contacts = <VaultContact>[
      for (final List<String> row in body)
        if (_contactOf(columns, row, dates) case final VaultContact contact)
          contact,
    ];
    return CsvContactsImport(contacts: contacts, format: format);
  }

  static CsvContactFormat _formatOf(List<String> header) {
    final Set<String> names = header.map(_key).toSet();
    if (names.contains('phone 1 - value') ||
        names.contains('e-mail 1 - value') ||
        names.contains('given name')) {
      return CsvContactFormat.google;
    }
    if (names.contains('e-mail address') ||
        names.contains('mobile phone') ||
        names.contains('business phone') ||
        names.contains('טלפון נייד') ||
        names.contains('כתובת דואר אלקטרוני')) {
      return CsvContactFormat.outlook;
    }
    return CsvContactFormat.generic;
  }

  VaultContact? _contactOf(
    List<_Column> columns,
    List<String> row,
    _DateOrder dates,
  ) {
    String cell(_Column c) => c.index < row.length ? row[c.index].trim() : '';

    // Google writes the kind of value n in a "… n - Label" column.
    final Map<String, String> kinds = <String, String>{
      for (final _Column c in columns)
        if (c.role == _Role.kind) c.group!: cell(c),
    };

    String firstName = '';
    String middleName = '';
    String lastName = '';
    String fullName = '';
    String company = '';
    String title = '';
    String department = '';
    final List<String> notes = <String>[];
    final List<String> phones = <String>[];
    final List<String> emails = <String>[];
    final List<String> addresses = <String>[];
    final List<String> labels = <String>[];
    final List<String> birthdays = <String>[];
    final List<String> other = <String>[];
    final Map<String, String> types = <String, String>{};
    // Address parts by group ("business", "home", "address 1"…).
    final Map<String, Map<_AddressPart, String>> addressParts =
        <String, Map<_AddressPart, String>>{};
    final Map<String, String> addressTypes = <String, String>{};
    bool isFavorite = false;

    void addTyped(List<String> list, String field, String value, String? type) {
      final String v = value.trim();
      if (v.isEmpty || list.contains(v)) {
        return;
      }
      list.add(v);
      if (type != null && type.isNotEmpty) {
        types[VaultContact.typeKey(field, v)] = type;
      }
    }

    for (final _Column c in columns) {
      final String value = cell(c);
      if (value.isEmpty) {
        continue;
      }
      final String? kind = c.group == null ? null : kinds[c.group!];
      switch (c.role) {
        case _Role.firstName:
          firstName = value;
        case _Role.middleName:
          middleName = value;
        case _Role.lastName:
          lastName = value;
        case _Role.fullName:
          fullName = value;
        case _Role.company:
          company = value;
        case _Role.jobTitle:
          title = value;
        case _Role.department:
          department = value;
        case _Role.notes:
          notes.add(value);
        case _Role.phone:
          for (final String v in _multi(value)) {
            addTyped(phones, 'phone', v, c.type ?? _phoneKind(kind));
          }
        case _Role.email:
          for (final String v in _multi(value)) {
            // Exchange exports internal addresses ("/o=ExchangeLabs/…").
            if (v.contains('@')) {
              addTyped(emails, 'email', v, c.type ?? _placeKind(kind));
            }
          }
        case _Role.address:
          for (final String v in _multi(value)) {
            addTyped(
              addresses,
              'address',
              v.replaceAll(RegExp(r'\s*\n\s*'), ', '),
              c.type ?? _placeKind(kind),
            );
          }
        case _Role.addressPart:
          (addressParts[c.group!] ??= <_AddressPart, String>{})[c.part!] =
              value;
          if (c.type != null) addressTypes[c.group!] = c.type!;
          if (kind != null) addressTypes[c.group!] = _placeKind(kind) ?? '';
        case _Role.birthday:
          final String? birthday = dates.normalize(value);
          if (birthday != null && !birthdays.contains(birthday)) {
            birthdays.add(birthday);
          }
        case _Role.anniversary:
          final String? date = dates.normalize(value);
          if (date != null) other.add('Anniversary: $date');
        case _Role.website:
          for (final String v in _multi(value)) {
            if (!other.contains(v)) other.add(v);
          }
        case _Role.nickname:
          other.add('Nickname: $value');
        case _Role.labels:
          for (final String label in value.split(RegExp(r'\s*(:::|;)\s*'))) {
            final String l = label.trim();
            final String lower = l.toLowerCase();
            if (l.isEmpty) continue;
            if (lower == '* starred' || lower == 'starred') {
              isFavorite = true;
            } else if (!l.startsWith('*') && !labels.contains(l)) {
              labels.add(l);
            }
          }
        case _Role.kind:
        case _Role.ignored:
          break;
      }
    }

    // Outlook and Google also give addresses as separate parts.
    for (final MapEntry<String, Map<_AddressPart, String>> e
        in addressParts.entries) {
      final Map<_AddressPart, String> p = e.value;
      final String cityLine = <String>[
        p[_AddressPart.city] ?? '',
        p[_AddressPart.region] ?? '',
        p[_AddressPart.postalCode] ?? '',
      ].where((String s) => s.isNotEmpty).join(' ');
      final String address =
          <String>[
                p[_AddressPart.street] ?? '',
                p[_AddressPart.street2] ?? '',
                p[_AddressPart.street3] ?? '',
                cityLine,
                p[_AddressPart.country] ?? '',
              ]
              .map((String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ', '))
              .where((String s) => s.isNotEmpty)
              .join(', ');
      // Google gives both the formatted address and its parts.
      final String folded = address.toLowerCase().replaceAll(
        _notLetterOrDigit,
        '',
      );
      final bool known = addresses.any(
        (String a) =>
            a.toLowerCase().replaceAll(_notLetterOrDigit, '') == folded,
      );
      if (address.isNotEmpty && !known) {
        addTyped(addresses, 'address', address, addressTypes[e.key]);
      }
    }

    if (firstName.isEmpty && lastName.isEmpty && fullName.isNotEmpty) {
      final List<String> words = fullName.split(RegExp(r'\s+'));
      firstName = words.length == 1
          ? fullName
          : words.take(words.length - 1).join(' ');
      lastName = words.length == 1 ? '' : words.last;
    }
    final String given = <String>[
      firstName,
      middleName,
    ].where((String s) => s.isNotEmpty).join(' ');
    final String companyLine = <String>[
      title,
      <String>[
        company,
        department,
      ].where((String s) => s.isNotEmpty).join(' - '),
    ].where((String s) => s.isNotEmpty).join(', ');
    final String displayName = fullName.isNotEmpty
        ? fullName
        : <String>[given, lastName].where((String s) => s.isNotEmpty).join(' ');

    if (displayName.isEmpty &&
        companyLine.isEmpty &&
        phones.isEmpty &&
        emails.isEmpty) {
      return null;
    }
    final DateTime now = DateTime.now().toUtc();
    return VaultContact.fromLegacyPayload(<String, dynamic>{
      'id': VaultContact.generateId(),
      'displayName': displayName,
      'firstName': given,
      'lastName': lastName,
      'company': companyLine,
      'notes': notes.join('\n'),
      'phones': phones,
      'emails': emails,
      'addresses': addresses,
      'labels': labels,
      'birthdays': birthdays,
      'other': other,
      'isFavorite': isFavorite,
      'valueTypes': types,
      'source': source,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
  }

  /// Google joins several values in one cell with " ::: ".
  static List<String> _multi(String value) => value
      .split(':::')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  static String? _phoneKind(String? kind) {
    final String k = (kind ?? '').toLowerCase();
    if (k.isEmpty) return null;
    if (k.contains('mobile') || k.contains('cell')) return 'mobile';
    if (k.contains('work')) return 'work';
    if (k.contains('home')) return 'home';
    if (k.contains('main')) return 'main';
    return 'other';
  }

  static String? _placeKind(String? kind) {
    final String k = (kind ?? '').toLowerCase();
    if (k.isEmpty) return null;
    if (k.contains('work')) return 'work';
    if (k.contains('home')) return 'home';
    return 'other';
  }
}

/// Everything but letters and digits in any script (`\W` would also drop
/// Hebrew letters).
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

String _key(String header) => header
    .replaceAll('﻿', '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

enum _Role {
  firstName,
  middleName,
  lastName,
  fullName,
  company,
  jobTitle,
  department,
  notes,
  phone,
  email,
  address,
  addressPart,
  birthday,
  anniversary,
  website,
  nickname,
  labels,

  /// Google's "Phone 1 - Label": the kind of another column's value.
  kind,
  ignored,
}

enum _AddressPart {
  street,
  street2,
  street3,
  city,
  region,
  postalCode,
  country,
}

class _Column {
  _Column(this.index, this.role, {this.type, this.group, this.part});

  final int index;
  final _Role role;

  /// The kind of value the column holds (mobile, work…), when the column
  /// name says so.
  final String? type;

  /// Ties a value column to its kind column ("phone 1"), or address parts
  /// to one address ("business").
  final String? group;
  final _AddressPart? part;

  static final RegExp _googleNumbered = RegExp(
    r'^(e-mail|phone|address|website|organization|relation|event|im|custom field|external id)\s*(\d+)\s*-\s*(.+)$',
  );

  factory _Column.of(int index, String header) {
    final String k = _key(header);
    _Column c(_Role role, {String? type, String? group, _AddressPart? part}) =>
        _Column(index, role, type: type, group: group, part: part);

    // Google CSV: "Phone 1 - Value", "E-mail 2 - Label", "Address 1 - City"…
    final RegExpMatch? g = _googleNumbered.firstMatch(k);
    if (g != null) {
      final String what = g.group(1)!;
      final String group = '$what ${g.group(2)}';
      final String field = g.group(3)!.trim();
      if (field == 'label' || field == 'type') {
        return c(_Role.kind, group: group);
      }
      switch (what) {
        case 'phone' when field == 'value':
          return c(_Role.phone, group: group);
        case 'e-mail' when field == 'value':
          return c(_Role.email, group: group);
        case 'website' when field == 'value':
          return c(_Role.website, group: group);
        case 'organization':
          if (field == 'name') return c(_Role.company);
          if (field == 'title') return c(_Role.jobTitle);
          if (field == 'department') return c(_Role.department);
        case 'address':
          if (field == 'formatted') return c(_Role.address, group: group);
          final _AddressPart? part = switch (field) {
            'street' => _AddressPart.street,
            'extended address' => _AddressPart.street2,
            'po box' => _AddressPart.street3,
            'city' => _AddressPart.city,
            'region' => _AddressPart.region,
            'postal code' => _AddressPart.postalCode,
            'country' => _AddressPart.country,
            _ => null,
          };
          if (part != null) {
            return c(_Role.addressPart, group: group, part: part);
          }
        case 'event':
          break;
      }
      return c(_Role.ignored);
    }

    switch (k) {
      case 'first name' ||
          'given name' ||
          'firstname' ||
          'first' ||
          'שם פרטי' ||
          'prénom' ||
          'vorname':
        return c(_Role.firstName);
      case 'middle name' || 'additional name' || 'שם אמצעי':
        return c(_Role.middleName);
      case 'last name' ||
          'family name' ||
          'surname' ||
          'lastname' ||
          'last' ||
          'שם משפחה' ||
          'nom' ||
          'nachname':
        return c(_Role.lastName);
      case 'name' ||
          'full name' ||
          'display name' ||
          'contact name' ||
          'contact' ||
          'שם' ||
          'שם מלא' ||
          'איש קשר' ||
          'שם תצוגה':
        return c(_Role.fullName);
      case 'company' ||
          'organization' ||
          'organisation' ||
          'organization name' ||
          'חברה' ||
          'ארגון' ||
          'שם החברה':
        return c(_Role.company);
      case 'job title' ||
          'title' ||
          'organization title' ||
          'position' ||
          'תפקיד' ||
          'תואר תפקיד':
        // Outlook's "Title" is Mr/Ms; "Job Title" is the job.
        return k == 'title' ? c(_Role.ignored) : c(_Role.jobTitle);
      case 'department' || 'organization department' || 'מחלקה':
        return c(_Role.department);
      case 'notes' || 'note' || 'comments' || 'הערות' || 'הערה':
        return c(_Role.notes);
      case 'birthday' ||
          'birth date' ||
          'date of birth' ||
          'יום הולדת' ||
          'תאריך לידה':
        return c(_Role.birthday);
      case 'anniversary' || 'יום נישואין':
        return c(_Role.anniversary);
      case 'web page' ||
          'website' ||
          'web site' ||
          'url' ||
          'personal web page' ||
          'דף אינטרנט' ||
          'אתר' ||
          'אתר אינטרנט':
        return c(_Role.website);
      case 'nickname' || 'כינוי':
        return c(_Role.nickname);
      case 'labels' ||
          'group membership' ||
          'categories' ||
          'groups' ||
          'group' ||
          'קטגוריות' ||
          'קבוצות' ||
          'תוויות':
        return c(_Role.labels);
    }

    // Outlook address parts: "Business Street", "Home City", "רחוב בבית"…
    final (String, String?)? place = _placeOf(k);
    if (place != null) {
      final String rest = place.$1;
      final _AddressPart? part = switch (rest) {
        'street' || 'רחוב' => _AddressPart.street,
        'street 2' || 'רחוב 2' => _AddressPart.street2,
        'street 3' || 'רחוב 3' => _AddressPart.street3,
        'city' || 'עיר' => _AddressPart.city,
        'state' || 'region' || 'מחוז' || 'מדינה/מחוז' => _AddressPart.region,
        'postal code' ||
        'zip' ||
        'zip code' ||
        'מיקוד' => _AddressPart.postalCode,
        'country' ||
        'country/region' ||
        'ארץ' ||
        'מדינה' ||
        'ארץ/אזור' => _AddressPart.country,
        'address' || 'כתובת' => null,
        _ => null,
      };
      if (part != null) {
        return c(
          _Role.addressPart,
          type: place.$2,
          group: 'place ${place.$2}',
          part: part,
        );
      }
      if (rest == 'address' || rest == 'כתובת') {
        return c(_Role.address, type: place.$2);
      }
    }

    if (_isEmail(k)) {
      return c(_Role.email, type: _typeFromWords(k, phone: false));
    }
    if (_isPhone(k)) {
      return c(_Role.phone, type: _typeFromWords(k, phone: true));
    }
    if (k == 'address' || k == 'כתובת' || k == 'street address') {
      return c(_Role.address);
    }
    return c(_Role.ignored);
  }

  /// "business city" -> ("city", "work"); "עיר בבית" -> ("עיר", "home").
  static (String, String?)? _placeOf(String k) {
    const Map<String, String> prefixes = <String, String>{
      'business ': 'work',
      'work ': 'work',
      'home ': 'home',
      'other ': 'other',
    };
    for (final MapEntry<String, String> e in prefixes.entries) {
      if (k.startsWith(e.key)) {
        return (k.substring(e.key.length), e.value);
      }
    }
    const Map<String, String> hebrewSuffixes = <String, String>{
      ' בעבודה': 'work',
      ' בבית': 'home',
      ' אחר': 'other',
      ' אחרת': 'other',
    };
    for (final MapEntry<String, String> e in hebrewSuffixes.entries) {
      if (k.endsWith(e.key)) {
        return (k.substring(0, k.length - e.key.length), e.value);
      }
    }
    return null;
  }

  static bool _isEmail(String k) {
    if (k.contains('type') ||
        k.contains('display name') ||
        k.contains('סוג') ||
        k.contains('שם תצוגה')) {
      return false;
    }
    return RegExp(r'e-?mail').hasMatch(k) ||
        k.contains('דואר אלקטרוני') ||
        k.contains('דוא"ל') ||
        k.contains('דוא״ל') ||
        k.contains('אימייל') ||
        k.contains('מייל');
  }

  static bool _isPhone(String k) {
    // Faxes, pagers and someone else's number (an assistant's) aren't
    // ways to reach this contact.
    const List<String> skip = <String>[
      'fax', 'pager', 'telex', 'tty', 'isdn', 'radio', 'callback',
      'assistant', 'פקס', 'זימונית', 'עוזר', //
    ];
    if (skip.any(k.contains)) return false;
    return k.contains('phone') ||
        k.contains('mobile') ||
        k.contains('cell') ||
        k.contains('tel') ||
        k.contains('טלפון') ||
        k.contains('נייד') ||
        k.contains('פלאפון') ||
        k.contains('סלולרי');
  }

  static String? _typeFromWords(String k, {required bool phone}) {
    if (phone &&
        (k.contains('mobile') ||
            k.contains('cell') ||
            k.contains('נייד') ||
            k.contains('פלאפון') ||
            k.contains('סלולרי'))) {
      return 'mobile';
    }
    if (k.contains('business') || k.contains('work') || k.contains('עבודה')) {
      return 'work';
    }
    if (k.contains('home') || k.contains('בית')) return 'home';
    if (phone &&
        (k.contains('main') || k.contains('primary') || k.contains('ראשי'))) {
      return 'main';
    }
    if (k.contains('other') ||
        k.contains('אחר') ||
        k.contains('car') ||
        k.contains('רכב')) {
      return 'other';
    }
    return null;
  }
}

/// Birthdays in spreadsheets follow the exporting computer's locale:
/// "5/14/1980" in the US, "14/5/1980" in Israel and Europe. One file uses
/// one order, so a day above 12 anywhere in the file settles it.
class _DateOrder {
  _DateOrder(this.dayFirst);

  final bool dayFirst;

  static final RegExp _numeric = RegExp(
    r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$',
  );

  factory _DateOrder.guess(Iterable<String> values) {
    bool dayFirst = false;
    for (final String raw in values) {
      final String v = raw.trim();
      final RegExpMatch? m = _numeric.firstMatch(v);
      if (m == null) continue;
      final int a = int.parse(m.group(1)!);
      final int b = int.parse(m.group(2)!);
      if (a > 12 && b <= 12) return _DateOrder(true);
      if (b > 12 && a <= 12) return _DateOrder(false);
      // Dots are the European/Israeli style.
      if (v.contains('.')) dayFirst = true;
    }
    return _DateOrder(dayFirst);
  }

  String? normalize(String raw) {
    final String v = raw.trim();
    if (v.isEmpty) return null;
    final String? iso = VCardParser.normalizeBirthday(v);
    if (iso != null) return iso;
    final RegExpMatch? m = _numeric.firstMatch(v);
    if (m == null) return null;
    int day = int.parse(m.group(dayFirst ? 1 : 2)!);
    int month = int.parse(m.group(dayFirst ? 2 : 1)!);
    if (month > 12 && day <= 12) {
      final int t = day;
      day = month;
      month = t;
    }
    final int yearRaw = int.parse(m.group(3)!);
    // Outlook writes "0/0/00" for "no birthday".
    if (day == 0 || month == 0 || day > 31 || month > 12) return null;
    final String mm = month.toString().padLeft(2, '0');
    final String dd = day.toString().padLeft(2, '0');
    if (yearRaw == 0) return '--$mm-$dd';
    final int year = m.group(3)!.length == 2
        ? (yearRaw > (DateTime.now().year % 100)
              ? 1900 + yearRaw
              : 2000 + yearRaw)
        : yearRaw;
    // Apple and Outlook use these years for "year unknown".
    if (year == 1604 || year == 4501 || year < 1800) return '--$mm-$dd';
    return '${year.toString().padLeft(4, '0')}-$mm-$dd';
  }
}

/// Splits CSV text into rows of cells (RFC 4180: quoted cells may hold the
/// separator, line breaks and doubled quotes). The separator is a comma,
/// semicolon (Excel in many European locales) or tab, whichever the header
/// row uses most.
List<List<String>> parseCsvRows(String input) {
  String text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (text.startsWith('﻿')) text = text.substring(1);
  // Excel's "sep=;" hint line.
  String? sep;
  final RegExpMatch? hint = RegExp(r'^sep=(.)\n').firstMatch(text);
  if (hint != null) {
    sep = hint.group(1);
    text = text.substring(hint.end);
  }
  sep ??= _guessSeparator(text);

  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer cell = StringBuffer();
  bool quoted = false;
  bool cellStarted = false;
  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
      continue;
    }
    if (ch == '"' && (!cellStarted || cell.toString().trim().isEmpty)) {
      cell.clear();
      quoted = true;
      cellStarted = true;
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
      cellStarted = false;
    } else if (ch == '\n') {
      row.add(cell.toString());
      cell.clear();
      cellStarted = false;
      if (row.any((String c) => c.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
      cellStarted = true;
    }
  }
  if (cellStarted || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((String c) => c.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

String _guessSeparator(String text) {
  int comma = 0;
  int semicolon = 0;
  int tab = 0;
  bool quoted = false;
  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    if (ch == '"') quoted = !quoted;
    if (quoted) continue;
    if (ch == '\n') break;
    if (ch == ',') comma++;
    if (ch == ';') semicolon++;
    if (ch == '\t') tab++;
  }
  if (tab > comma && tab > semicolon) return '\t';
  if (semicolon > comma) return ';';
  return ',';
}
