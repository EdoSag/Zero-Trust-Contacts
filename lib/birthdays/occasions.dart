import 'package:flutter/foundation.dart';
import 'package:zerotrust_contacts/import/vcard_parser.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// A yearly day of a contact: a birthday or a wedding anniversary.
enum OccasionKind { birthday, anniversary }

/// One contact's birthday or anniversary.
@immutable
class Occasion {
  const Occasion({
    required this.contactId,
    required this.name,
    required this.kind,
    required this.month,
    required this.day,
    this.year,
  });

  final String contactId;
  final String name;
  final OccasionKind kind;
  final int month;
  final int day;

  /// Null when only the day is known (`--MM-DD`).
  final int? year;

  /// The next time it falls on or after [today] (a date at midnight).
  /// 29 February is kept on 28 February in other years.
  DateTime nextOn(DateTime today) {
    final DateTime start = DateTime(today.year, today.month, today.day);
    DateTime inYear(int y) =>
        DateTime(y, month, month == 2 && day == 29 && !_isLeap(y) ? 28 : day);
    final DateTime thisYear = inYear(start.year);
    return thisYear.isBefore(start) ? inYear(start.year + 1) : thisYear;
  }

  /// Days from [today] to [nextOn]: 0 is today.
  int daysUntil(DateTime today) {
    final DateTime start = DateTime(today.year, today.month, today.day);
    // Whole days in local time, safe across a daylight saving change.
    final DateTime next = nextOn(today);
    return DateTime.utc(next.year, next.month, next.day)
        .difference(DateTime.utc(start.year, start.month, start.day))
        .inDays;
  }

  /// The age (or years married) on the next occurrence, when the year is
  /// known and plausible.
  int? yearsOn(DateTime today) {
    final int? y = year;
    if (y == null) return null;
    final int years = nextOn(today).year - y;
    return years > 0 && years < 150 ? years : null;
  }

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  @override
  bool operator ==(Object other) =>
      other is Occasion &&
      other.contactId == contactId &&
      other.kind == kind &&
      other.month == month &&
      other.day == day &&
      other.year == year &&
      other.name == name;

  @override
  int get hashCode => Object.hash(contactId, kind, month, day, year, name);
}

/// How anniversaries are kept: an "other" line `Anniversary: 2010-06-12`
/// (written by the vCard, CSV and phone imports).
const String anniversaryPrefix = 'Anniversary:';

/// Reads a stored date: `YYYY-MM-DD`, `--MM-DD`, `YYYYMMDD` or anything
/// a vCard may hold. Returns (month, day, year or null).
(int, int, int?)? parseOccasionDate(String raw) {
  final String? normal = VCardParser.normalizeBirthday(raw);
  if (normal == null) return null;
  final RegExpMatch? noYear =
      RegExp(r'^--(\d{2})-(\d{2})$').firstMatch(normal);
  final RegExpMatch? full =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(normal);
  final int month;
  final int day;
  int? year;
  if (noYear != null) {
    month = int.parse(noYear.group(1)!);
    day = int.parse(noYear.group(2)!);
  } else if (full != null) {
    year = int.parse(full.group(1)!);
    month = int.parse(full.group(2)!);
    day = int.parse(full.group(3)!);
  } else {
    return null;
  }
  if (month < 1 || month > 12 || day < 1) return null;
  const List<int> longest = <int>[31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (day > longest[month - 1]) return null;
  return (month, day, year);
}

/// Every birthday and anniversary of [contacts] (blocked contacts left out),
/// one per contact, kind and day.
List<Occasion> occasionsOf(Iterable<VaultContact> contacts) {
  final List<Occasion> out = <Occasion>[];
  for (final VaultContact c in contacts) {
    if (c.isBlocked) continue;
    final Set<String> seen = <String>{};
    void add(OccasionKind kind, String raw) {
      final (int, int, int?)? d = parseOccasionDate(raw);
      if (d == null) return;
      final (int month, int day, int? year) = d;
      if (!seen.add('${kind.name}|$month|$day')) return;
      out.add(Occasion(
        contactId: c.id,
        name: c.displayName,
        kind: kind,
        month: month,
        day: day,
        year: year,
      ));
    }

    for (final String b in c.birthdays) {
      add(OccasionKind.birthday, b);
    }
    for (final String line in c.other) {
      if (line.toLowerCase().startsWith(anniversaryPrefix.toLowerCase())) {
        add(OccasionKind.anniversary,
            line.substring(anniversaryPrefix.length).trim());
      }
    }
  }
  return out;
}

/// [occasions] in the order they come up from [today], soonest first; only
/// those within [days] days when given.
List<Occasion> upcomingOccasions(
  Iterable<Occasion> occasions,
  DateTime today, {
  int? days,
}) {
  final List<Occasion> list = <Occasion>[
    for (final Occasion o in occasions)
      if (days == null || o.daysUntil(today) <= days) o,
  ];
  list.sort((Occasion a, Occasion b) {
    final int byDay = a.daysUntil(today).compareTo(b.daysUntil(today));
    return byDay != 0
        ? byDay
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return list;
}
