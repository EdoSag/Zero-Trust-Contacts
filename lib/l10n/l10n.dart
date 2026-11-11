import 'package:flutter/widgets.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'generated/app_l10n.dart';

export 'generated/app_l10n.dart';

/// ZT Contacts's own strings, in English and Hebrew (`app_en.arb`,
/// `app_he.arb`). The language is the one picked under Settings →
/// Appearance → Language (`ztLanguageProvider` in the core).
extension AppL10nContext on BuildContext {
  AppL10n get l10n => AppL10n.of(this);
}

/// The strings for the app's current language, for code without a
/// [BuildContext] (notifications, the home screen widget, exports).
AppL10n get currentL10n {
  final code = ZtL10n.current.localeName.split('_').first;
  return lookupAppL10n(
    AppL10n.supportedLocales.any((l) => l.languageCode == code)
        ? Locale(code)
        : const Locale('en'),
  );
}

/// Keeps [text] left-to-right inside Hebrew (numbers with units, emails).
String ltr(String text) => text.isEmpty ? text : '\u2066$text\u2069';


/// A phone, email or address type ('mobile', 'work', ...) in the app's
/// language. Contacts store the English word; only the display changes.
String fieldTypeLabel(String type) {
  final l = currentL10n;
  return switch (type.toLowerCase()) {
    'mobile' => l.typeMobile,
    'home' => l.typeHome,
    'work' => l.typeWork,
    'main' => l.typeMain,
    'other' => l.typeOther,
    '' => type,
    _ => '${type[0].toUpperCase()}${type.substring(1)}',
  };
}

/// A restore point's reason, saved in English when it was made.
String restorePointLabel(String reason) {
  final l = currentL10n;
  const importPrefix = 'Before import from ';
  if (reason.startsWith(importPrefix)) {
    return l.rpBeforeImport(reason.substring(importPrefix.length));
  }
  return switch (reason) {
    'Before merging duplicates' => l.rpBeforeMerging,
    'Automatic daily restore point' => l.rpDaily,
    'Automatic weekly restore point' => l.rpWeekly,
    'Before restoring a restore point' => l.rpBeforeRestoring,
    'Before replacing local contacts' => l.rpBeforeReplacing,
    'Manual restore point' => l.rpManual,
    _ => reason,
  };
}

/// Why contacts were grouped as possible duplicates.
String duplicateReasonLabel(String reason) {
  final l = currentL10n;
  return switch (reason) {
    'Similar contacts' => l.dupSimilar,
    'Same phone number' => l.dupPhone,
    'Same email' => l.dupEmail,
    'Same display name' => l.dupName,
    _ => reason,
  };
}
