import 'package:zerotrust_contacts/models/vault_contact.dart';

/// What was understood from the text of a business card. Nothing here is
/// saved until the user has looked it over in the contact editor.
class ScannedCard {
  ScannedCard({
    this.firstName = '',
    this.lastName = '',
    this.company = '',
    this.title = '',
    this.phones = const <String>[],
    this.phoneKinds = const <String, String>{},
    this.faxes = const <String>[],
    this.emails = const <String>[],
    this.websites = const <String>[],
    this.addresses = const <String>[],
  });

  final String firstName;
  final String lastName;
  final String company;
  final String title;
  final List<String> phones;

  /// Kind (`mobile`, `work`) by phone number, where the card said.
  final Map<String, String> phoneKinds;
  final List<String> faxes;
  final List<String> emails;
  final List<String> websites;
  final List<String> addresses;

  bool get isEmpty =>
      firstName.isEmpty &&
      lastName.isEmpty &&
      company.isEmpty &&
      phones.isEmpty &&
      emails.isEmpty &&
      websites.isEmpty &&
      addresses.isEmpty;

  /// A new, unsaved contact to open the editor with.
  VaultContact toContact() => VaultContact.fromLegacyPayload(<String, dynamic>{
    'id': VaultContact.generateId(),
    'firstName': firstName,
    'lastName': lastName,
    'company': company,
    'phones': phones,
    'emails': emails,
    'addresses': addresses,
    'other': <String>[
      if (title.isNotEmpty) 'Title: $title',
      ...websites,
      for (final String fax in faxes) 'Fax: $fax',
    ],
    'valueTypes': <String, String>{
      for (final MapEntry<String, String> e in phoneKinds.entries)
        VaultContact.typeKey('phone', e.key): e.value,
      for (final String email in emails)
        VaultContact.typeKey('email', email): 'work',
      for (final String address in addresses)
        VaultContact.typeKey('address', address): 'work',
    },
    'source': 'Saved',
  });
}

/// Works out which line of a business card is the name, the company, the
/// phone numbers and so on. Plain rules, no network and no model: the text
/// comes from on-device recognition and never leaves the phone.
///
/// Handles English and Hebrew cards, and cards that mix the two.
class BusinessCardParser {
  const BusinessCardParser();

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+',
  );
  static final RegExp _url = RegExp(
    r'(?:https?://|www\.)[^\s,;]+|\b[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*'
    r'\.(?:com|net|org|io|co|il|uk|de|fr|biz|info|app|dev|me|tech|ai|eu|us)'
    r'(?:\.[a-z]{2})?(?:/[^\s,;]*)?',
    caseSensitive: false,
  );
  static final RegExp _phone = RegExp(r'\+?[\d(][\d\s().\-–/]{5,}\d');
  static final RegExp _fax = RegExp(
    r'(?:^|[^A-Za-z])(?:fax|f)\s*[:.|]|\bfax\b|פקס',
    caseSensitive: false,
  );
  static final RegExp _mobile = RegExp(
    r'(?:^|[^A-Za-z])(?:mobile|mob|cell|cellular|m|c)\s*[:.|]'
    r'|\b(?:mobile|cell)\b|נייד|גייד|סלולרי|פלאפון',
    caseSensitive: false,
  );
  static final RegExp _office = RegExp(
    r'(?:^|[^A-Za-z])(?:tel|telephone|phone|office|direct|work|t|o|p)\s*[:.|]'
    r'|\b(?:tel|office|direct)\b|טלפון|טל|משרד',
    caseSensitive: false,
  );
  static final RegExp _companyWord = RegExp(
    r'\b(?:ltd|inc|llc|llp|gmbh|corp|corporation|company|co|group|holdings'
    r'|solutions|systems|technologies|technology|consulting|partners'
    r'|associates|studio|labs|software|industries|bank|university|law'
    r'|international|enterprises|services|agency)\b\.?'
    r'|בע"מ|בע״מ|בעמ|ושות|חברת|קבוצת|משרד עורכי',
    caseSensitive: false,
  );
  static final RegExp _titleWord = RegExp(
    r'\b(?:ceo|cto|cfo|coo|cmo|vp|president|founder|co-founder|owner|partner'
    r'|director|manager|head of|lead|engineer|developer|designer|architect'
    r'|consultant|analyst|officer|executive|specialist|coordinator'
    r'|representative|sales|marketing|attorney|lawyer|advocate|accountant'
    r'|doctor|dr|professor|agent|advisor|adviser|assistant|supervisor'
    r'|technician|editor|producer|recruiter)\b'
    r'|מנכ"ל|מנכ״ל|סמנכ"ל|סמנכ״ל|מנהל|מנהלת|מהנדס|מהנדסת|יועץ|יועצת'
    r'|עו"ד|עו״ד|עורך דין|עורכת דין|רו"ח|רו״ח|מייסד|מייסדת|שותף|שותפה'
    r'|בעלים|מפתח|מפתחת|מעצב|מעצבת|אדריכל|אדריכלית|סוכן|סוכנת|מנתח',
    caseSensitive: false,
  );
  static final RegExp _addressWord = RegExp(
    r'\b(?:street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr'
    r'|square|sq|suite|ste|floor|fl|building|bldg|p\.?o\.? ?box|way|plaza'
    r'|tower|park|strasse|straße|rue)\b\.?'
    r"|רחוב|רח'|רח׳|שדרות|שד'|שד׳|ת\.ד|ת״ד|קומה|בניין|מגדל|דרך|כיכר",
    caseSensitive: false,
  );
  static final RegExp _letters = RegExp(r'[A-Za-z֐-׿À-ɏ]');
  static final RegExp _hebrew = RegExp(r'[֐-׿]');

  /// Joins two readings of the same card: one made looking for Hebrew and
  /// one for English. Reading a card for both at once muddles the order of
  /// the words, and each reading on its own misses the other language.
  ///
  /// A card with Hebrew on it uses the Hebrew reading, plus the lines of
  /// the English one that hold an email, a web address or a number (which
  /// the Hebrew reading tends to get wrong). Any other card uses the
  /// English reading alone.
  static String mergeReadings({
    required String hebrew,
    required String english,
  }) {
    final int hebrewLetters = _hebrew.allMatches(hebrew).length;
    final int allLetters = _letters.allMatches(hebrew).length;
    if (hebrewLetters < 4 || hebrewLetters * 5 < allLetters) {
      return english;
    }
    final Iterable<String> latinFacts = english
        .split('\n')
        .where((String l) {
          final String line = l.replaceAll(RegExp(r'\s*@\s*'), '@');
          return _email.hasMatch(line) ||
              _url.hasMatch(line) ||
              _phone.hasMatch(line);
        })
        .map((String l) {
          // Keep the fact, not the misread Hebrew label in front of it.
          final String line = l.replaceAll(RegExp(r'\s*@\s*'), '@');
          return <String>[
            ..._email.allMatches(line).map((RegExpMatch m) => m.group(0)!),
            ..._url
                .allMatches(line.replaceAll(_email, ' '))
                .map((RegExpMatch m) => m.group(0)!),
            ..._phone
                .allMatches(line.replaceAll(_email, ' '))
                .map((RegExpMatch m) => m.group(0)!),
          ].join(' | ');
        });
    return <String>[hebrew, ...latinFacts].join('\n');
  }

  ScannedCard parse(String text) {
    final List<String> lines = text
        .replaceAll('\r', '\n')
        .split('\n')
        .map(_tidy)
        .where((String l) => _letterOrDigitCount(l) >= 2)
        .toList();

    final List<String> emails = <String>[];
    final List<String> websites = <String>[];
    final List<String> phones = <String>[];
    final List<String> faxes = <String>[];
    final Map<String, String> kinds = <String, String>{};
    final List<String> addresses = <String>[];
    final List<String> rest = <String>[];

    for (final String original in lines) {
      // "name @ firm . com" is how recognition often spaces an address.
      String line = original.replaceAllMapped(RegExp(r'\s*@\s*'), (_) => '@');
      bool used = false;

      for (final RegExpMatch m in _email.allMatches(line)) {
        _addUnique(emails, m.group(0)!.toLowerCase());
        used = true;
      }
      line = line.replaceAll(_email, ' ');

      for (final RegExpMatch m in _url.allMatches(line)) {
        final String url = m.group(0)!.replaceAll(RegExp(r'[.,;]+$'), '');
        _addUnique(websites, url.toLowerCase());
        used = true;
      }
      line = line.replaceAll(_url, ' ');

      // "Tel Aviv 6688102" is a town and postcode, not a phone number.
      if (!used && _isTownAndPostcode(line)) {
        addresses.add(_stripLabel(original));
        continue;
      }

      final bool looksLikeAddress = _addressWord.hasMatch(line);
      if (!looksLikeAddress || _fax.hasMatch(line) || _mobile.hasMatch(line)) {
        final List<RegExpMatch> found = _phone.allMatches(line).where((
          RegExpMatch m,
        ) {
          final int digits = m.group(0)!.replaceAll(RegExp(r'\D'), '').length;
          return digits >= 7 && digits <= 15;
        }).toList();
        for (int i = 0; i < found.length; i++) {
          final RegExpMatch m = found[i];
          final String number = _cleanPhone(m.group(0)!);
          // What the card wrote just before this number says what it is.
          final int from = i == 0 ? 0 : found[i - 1].end;
          final String before = line.substring(from, m.start);
          // The same number can turn up twice (two readings of one card,
          // or printed twice). Once it is known to be a fax it stays one.
          final String digits = _digits(number);
          final bool knownFax = faxes.any((String f) => _digits(f) == digits);
          if (_fax.hasMatch(before) || knownFax) {
            if (!knownFax) faxes.add(number);
            final List<String> same = phones
                .where((String p) => _digits(p) == digits)
                .toList();
            phones.removeWhere(same.contains);
            same.forEach(kinds.remove);
          } else if (!phones.any((String p) => _digits(p) == digits)) {
            phones.add(number);
            if (_mobile.hasMatch(before)) {
              kinds[number] = 'mobile';
            } else if (_office.hasMatch(before)) {
              kinds[number] = 'work';
            }
          }
          used = true;
        }
        if (found.isNotEmpty) {
          line = line.replaceAll(_phone, ' ');
        }
      }

      if (looksLikeAddress && !_phone.hasMatch(line) ||
          looksLikeAddress && RegExp(r'\d').hasMatch(line)) {
        final String address = _stripLabel(original);
        if (address.isNotEmpty) {
          addresses.add(address);
          continue;
        }
      }

      if (!used) {
        rest.add(original);
      } else {
        // A name or company can share a line with a number or address.
        final String left = _stripLabel(line);
        if (_wordCount(left) >= 2 &&
            !RegExp(r'\d').hasMatch(left) &&
            !_isOnlyLabels(left)) {
          rest.add(left);
        }
      }
    }

    // A postcode-and-city line right after a street line belongs to it.
    final List<String> joinedAddresses = addresses.isEmpty
        ? <String>[]
        : <String>[addresses.join(', ')];

    String company = '';
    String title = '';
    final List<String> candidates = <String>[];
    for (final String line in rest) {
      if (company.isEmpty && _companyWord.hasMatch(line)) {
        company = line;
      } else if (title.isEmpty && _titleWord.hasMatch(line)) {
        title = line;
      } else {
        candidates.add(line);
      }
    }

    final String name = _pickName(candidates, emails);
    candidates.remove(name);
    if (company.isEmpty) {
      company = _companyFromDomain(candidates, emails, websites);
    }

    final List<String> parts = name.split(RegExp(r'\s+'))
      ..removeWhere((String p) => p.isEmpty);
    return ScannedCard(
      firstName: parts.isEmpty ? '' : parts.first,
      lastName: parts.length < 2 ? '' : parts.sublist(1).join(' '),
      company: company,
      title: title,
      phones: phones,
      phoneKinds: kinds,
      faxes: faxes,
      emails: emails,
      websites: websites
          .where((String w) => !emails.any((String e) => e.endsWith('@$w')))
          .toList(),
      addresses: joinedAddresses,
    );
  }

  static final RegExp _phoneLabelWord = RegExp(
    r'^(?:tel|telephone|phone|mobile|mob|cell|fax|office|direct|work|home'
    r'|טלפון|טל|נייד|פקס|משרד|[A-Za-z])$',
    caseSensitive: false,
  );

  static bool _isTownAndPostcode(String line) {
    final RegExpMatch? m = RegExp(
      r"^([^\d+:|@]{3,}?)[\s,]+\d{4,7}$",
    ).firstMatch(line.trim());
    if (m == null) return false;
    return m
        .group(1)!
        .split(RegExp(r"[\s,.]+"))
        .any((String w) => w.length >= 3 && !_phoneLabelWord.hasMatch(w));
  }

  static String _tidy(String line) => line
      .replaceAll(RegExp(r'[\u200e\u200f\u202a-\u202e]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s|•·:\-–—_.,]+|[\s|•·:\-–—_,]+$'), '')
      .trim();

  static int _letterOrDigitCount(String s) =>
      RegExp(r'[A-Za-z0-9֐-׿À-ɏ]').allMatches(s).length;

  static int _wordCount(String s) =>
      s.split(RegExp(r'\s+')).where(_letters.hasMatch).length;

  static String _digits(String phone) => phone.replaceAll(RegExp(r'\D'), '');

  static void _addUnique(List<String> list, String value) {
    if (value.isNotEmpty && !list.contains(value)) list.add(value);
  }

  static String _cleanPhone(String raw) => raw
      .replaceAll(RegExp(r'[–/]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s.\-(]+$'), '')
      .trim();

  static final RegExp _label = RegExp(
    r'^(?:address|addr|tel|telephone|phone|mobile|mob|cell|fax|email|e-mail'
    r'|mail|web|website|office|direct|כתובת|טלפון|טל|נייד|פקס|דוא"ל|דוא״ל'
    r'|מייל|אתר|משרד|[A-Za-z])\s*[:.|]\s*',
    caseSensitive: false,
  );

  static String _stripLabel(String line) {
    String out = _tidy(line);
    for (int i = 0; i < 3; i++) {
      final String next = _tidy(out.replaceFirst(_label, ''));
      if (next == out) break;
      out = next;
    }
    return out;
  }

  static bool _isOnlyLabels(String line) => line
      .split(RegExp(r'[\s:.|,]+'))
      .where((String w) => w.isNotEmpty)
      .every((String w) => _label.hasMatch('$w:'));

  static bool _looksLikeName(String line) {
    final int words = _wordCount(line);
    if (words < 1 || words > 4 || line.length > 40) return false;
    if (RegExp(r'[\d@/\\]').hasMatch(line)) return false;
    final int letters = _letters.allMatches(line).length;
    final int others = line.replaceAll(RegExp(r'\s'), '').length - letters;
    // Initials and hyphenated names are fine; a line of symbols is noise.
    return letters >= 3 && others <= 3;
  }

  static String _pickName(List<String> candidates, List<String> emails) {
    final List<String> names = candidates.where(_looksLikeName).toList();
    if (names.isEmpty) return '';
    // "dana.levi@…" points at the line "Dana Levi".
    for (final String email in emails) {
      final List<String> bits = email
          .split('@')
          .first
          .split(RegExp(r'[._\-+0-9]+'))
          .where((String b) => b.length >= 3)
          .toList();
      for (final String line in names) {
        final String lower = line.toLowerCase();
        if (bits.any(lower.contains)) return line;
      }
    }
    // Otherwise a full name (two to three words) beats a single word, and
    // earlier lines beat later ones.
    return names.firstWhere(
      (String l) => _wordCount(l) >= 2 && _wordCount(l) <= 3,
      orElse: () => names.first,
    );
  }

  static const Set<String> _mailHosts = <String>{
    'gmail', 'googlemail', 'yahoo', 'hotmail', 'outlook', 'live', 'icloud',
    'me', 'proton', 'protonmail', 'aol', 'walla', 'msn', 'gmx', 'mail', //
  };

  static String _companyFromDomain(
    List<String> candidates,
    List<String> emails,
    List<String> websites,
  ) {
    final List<String> hosts = <String>[
      for (final String e in emails) e.split('@').last,
      for (final String w in websites)
        w.replaceFirst(RegExp(r'^https?://'), '').replaceFirst('www.', ''),
    ];
    for (final String host in hosts) {
      final String word = host.split('.').first;
      if (word.length < 3 || _mailHosts.contains(word)) continue;
      for (final String line in candidates) {
        final String squeezed = line.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (squeezed.contains(word) ||
            (squeezed.length >= 3 && word.contains(squeezed))) {
          return line;
        }
      }
    }
    // A Hebrew card often has the company as the other large line.
    final List<String> left = candidates
        .where((String l) => !RegExp(r'\d').hasMatch(l) && l.length <= 40)
        .toList();
    if (left.length == 1 &&
        (_hebrew.hasMatch(left.first) || _wordCount(left.first) <= 4)) {
      return left.first;
    }
    return '';
  }
}
