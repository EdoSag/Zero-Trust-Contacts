import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:zerotrust_contacts/birthdays/occasions.dart';

/// What the upcoming birthdays widget (W8) may show while the vault is
/// locked: each occasion's day, and the name only when "Show names on the
/// home screen" is on. Written when the app is unlocked.
String birthdaysWidgetSnapshot(
  List<Occasion> occasions, {
  required bool showNames,
  int limit = 200,
}) {
  final List<Occasion> sorted = upcomingOccasions(occasions, DateTime.now());
  return jsonEncode(<String, Object?>{
    'names': showNames,
    'items': <Map<String, Object?>>[
      for (final Occasion o in sorted.take(limit))
        <String, Object?>{
          if (showNames) 'n': o.name,
          'k': o.kind == OccasionKind.birthday ? 'b' : 'a',
          'm': o.month,
          'd': o.day,
          if (showNames && o.year != null) 'y': o.year,
        },
    ],
  });
}

/// Hands the snapshot to the Android widget. Does nothing elsewhere.
class BirthdaysWidgetBridge {
  const BirthdaysWidgetBridge();

  static const MethodChannel _channel =
      MethodChannel('zerotrust_contacts/device_contacts');

  Future<void> update(List<Occasion> occasions,
      {required bool showNames}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('updateBirthdaysWidget', <String, Object?>{
        'json': birthdaysWidgetSnapshot(occasions, showNames: showNames),
      });
    } on Object {
      // No widget support (tests, old launcher): nothing to update.
    }
  }
}
