import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

void main() {
  tearDown(() => ZtL10n.current = lookupZtLocalizations(const Locale('en')));

  test('every English string has a Hebrew translation with the same '
      'placeholders', () {
    Map<String, dynamic> read(String lang) =>
        jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = read('en');
    final he = read('he');
    // A placeholder's brace follows a non-word character; a plural case's
    // brace follows its name (`=1{...}`).
    final placeholder = RegExp(r'(?<!\w)\{(\w+)[,}]');
    Set<String?> names(String text) =>
        placeholder.allMatches(text).map((m) => m[1]).toSet();
    for (final key in en.keys.where((k) => !k.startsWith('@'))) {
      expect(he[key], isA<String>(), reason: 'app_he.arb is missing "$key"');
      expect(names(he[key] as String), names(en[key] as String),
          reason: 'placeholders differ in "$key"');
    }
  });

  test('Hebrew plurals read naturally', () {
    final he = lookupAppL10n(const Locale('he'));
    expect(he.nContacts(1), 'איש קשר אחד');
    expect(he.nContacts(4), '4 אנשי קשר');
    expect(he.daysLeft(2), 'נשארו יומיים');
    expect(lookupAppL10n(const Locale('en')).daysLeft(1), '1 day left');
  });

  test('saved English words show in the app language', () {
    ZtL10n.current = lookupZtLocalizations(const Locale('he'));
    expect(fieldTypeLabel('mobile'), 'נייד');
    expect(fieldTypeLabel('custom'), 'Custom');
    expect(restorePointLabel('Automatic daily restore point'),
        'נקודת שחזור יומית אוטומטית');
    expect(restorePointLabel('Before import from Google'), 'לפני ייבוא מ-Google');
    expect(duplicateReasonLabel('Same email'), 'אותו אימייל');

    ZtL10n.current = lookupZtLocalizations(const Locale('en'));
    expect(fieldTypeLabel('mobile'), 'Mobile');
    expect(restorePointLabel('Manual restore point'), 'Manual restore point');
  });
}
