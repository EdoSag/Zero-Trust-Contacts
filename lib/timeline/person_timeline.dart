import 'package:flutter/foundation.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

/// What a timeline entry is about.
enum TimelineKind { call, event, task }

/// How a call went (Android's `CallLog.Calls.TYPE`).
enum CallDirection { incoming, outgoing, missed, other }

/// One thing a contact was part of, from another Zero-Trust app (C-1).
@immutable
class TimelineEntry {
  const TimelineEntry({
    required this.kind,
    required this.at,
    required this.itemId,
    this.title = '',
    this.direction,
    this.duration,
    this.allDay = false,
    this.repeats = false,
    this.done = false,
  });

  final TimelineKind kind;

  /// The call's time, the event's start, or the task's due date (or when it
  /// was made, when it has none).
  final DateTime at;
  final String itemId;

  /// The event's or task's title; empty for calls.
  final String title;

  final CallDirection? direction;
  final Duration? duration;
  final bool allDay;

  /// A repeating event: [at] is its first time.
  final bool repeats;

  /// A ticked-off task.
  final bool done;

  /// A call that reached the person: not missed, and with a length when
  /// it is incoming.
  bool get talked =>
      kind == TimelineKind.call &&
      direction != CallDirection.missed &&
      (direction == CallDirection.outgoing || (duration ?? Duration.zero) > Duration.zero);

  @override
  bool operator ==(Object other) =>
      other is TimelineEntry && other.kind == kind && other.itemId == itemId;

  @override
  int get hashCode => Object.hash(kind, itemId);
}

/// The last 9 digits of a number, as ZT Phone matches numbers: the same
/// person with or without the country code.
String phoneLookupKey(String number) {
  final int post = number.indexOf(RegExp('[,;]'));
  final String digits = (post < 0 ? number : number.substring(0, post))
      .replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
}

CallDirection _direction(int type) => switch (type) {
      1 => CallDirection.incoming,
      2 => CallDirection.outgoing,
      3 || 5 || 6 => CallDirection.missed, // missed, rejected, blocked
      _ => CallDirection.other,
    };

DateTime? _date(Object? raw) {
  if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
  if (raw is! String) return null;
  final RegExpMatch? day =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (day != null) {
    return DateTime(int.parse(day.group(1)!), int.parse(day.group(2)!),
        int.parse(day.group(3)!));
  }
  return DateTime.tryParse(raw)?.toLocal();
}

List<String> _strings(Object? v) => <String>[
      if (v is List)
        for (final Object? e in v)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];

/// Calls with [contact]'s numbers, from ZT Phone's items (`call_history`
/// and `private_call`), one per call even when both hold it.
List<TimelineEntry> callsWith(
    VaultContact contact, Iterable<Map<String, Object?>> phoneItems) {
  final Set<String> keys = <String>{
    for (final String p in contact.phones)
      if (phoneLookupKey(p).length >= 5) phoneLookupKey(p),
  };
  if (keys.isEmpty) return const <TimelineEntry>[];
  final Map<String, TimelineEntry> calls = <String, TimelineEntry>{};
  for (final Map<String, Object?> item in phoneItems) {
    final Object? kind = item['kind'];
    if (kind != 'call_history' && kind != 'private_call') continue;
    final String number = item['number'] is String ? item['number']! as String : '';
    if (!keys.contains(phoneLookupKey(number))) continue;
    final DateTime? at = _date(item['date']);
    if (at == null) continue;
    final int type = (item['type'] as num?)?.toInt() ?? 1;
    // The same call kept in both collections has the same time and type.
    calls['${at.millisecondsSinceEpoch ~/ 1000}|$type'] = TimelineEntry(
      kind: TimelineKind.call,
      at: at,
      itemId: '${item['_id'] ?? ''}',
      direction: _direction(type),
      duration: Duration(seconds: (item['duration'] as num?)?.toInt() ?? 0),
    );
  }
  return calls.values.toList();
}

/// ZT Calendar events with [contact] as a guest: linked by id, or invited
/// by one of the contact's emails.
List<TimelineEntry> eventsWith(
    VaultContact contact, Iterable<Map<String, Object?>> calendarItems) {
  final Set<String> emails = <String>{
    for (final String e in contact.emails) e.trim().toLowerCase(),
  };
  final List<TimelineEntry> out = <TimelineEntry>[];
  for (final Map<String, Object?> item in calendarItems) {
    if (item['kind'] != 'event') continue;
    final bool linked = _strings(item['contactIds']).contains(contact.id) ||
        _strings(item['guestEmails'])
            .any((String e) => emails.contains(e.toLowerCase()));
    if (!linked) continue;
    final DateTime? at = _date(item['start']);
    if (at == null) continue;
    final String title = item['title'] is String ? (item['title']! as String).trim() : '';
    out.add(TimelineEntry(
      kind: TimelineKind.event,
      at: at,
      itemId: '${item['_id'] ?? ''}',
      title: title,
      allDay: item['allDay'] == true,
      repeats: item['rrule'] is String && (item['rrule']! as String).isNotEmpty,
    ));
  }
  return out;
}

/// ZT Tasks tasks linked to [contact].
List<TimelineEntry> tasksWith(
    VaultContact contact, Iterable<Map<String, Object?>> taskItems) {
  final List<TimelineEntry> out = <TimelineEntry>[];
  for (final Map<String, Object?> item in taskItems) {
    // Tasks are the items with no kind; lists and templates have one.
    if (item['kind'] != null || item['deletedAt'] != null) continue;
    if (!_strings(item['contactIds']).contains(contact.id)) continue;
    final DateTime? at = _date(item['dueDate']) ?? _date(item['createdAt']);
    if (at == null) continue;
    final String title = item['title'] is String ? (item['title']! as String).trim() : '';
    out.add(TimelineEntry(
      kind: TimelineKind.task,
      at: at,
      itemId: '${item['_id'] ?? ''}',
      title: title,
      done: item['isCompleted'] == true,
    ));
  }
  return out;
}

/// Everything [contact] was part of, newest first.
List<TimelineEntry> timelineFor(
  VaultContact contact, {
  Iterable<Map<String, Object?>> phone = const <Map<String, Object?>>[],
  Iterable<Map<String, Object?>> calendar = const <Map<String, Object?>>[],
  Iterable<Map<String, Object?>> tasks = const <Map<String, Object?>>[],
}) {
  final List<TimelineEntry> all = <TimelineEntry>[
    ...callsWith(contact, phone),
    ...eventsWith(contact, calendar),
    ...tasksWith(contact, tasks),
  ];
  all.sort((TimelineEntry a, TimelineEntry b) => b.at.compareTo(a.at));
  return all;
}

/// When [contact] and the user last talked: the latest call that reached
/// them in ZT Phone, or a call or message started from ZT Contacts.
DateTime? lastTalked(
    VaultContact contact, Iterable<Map<String, Object?>> phoneItems) {
  DateTime? last = contact.lastContactedAt?.toLocal();
  for (final TimelineEntry call in callsWith(contact, phoneItems)) {
    if (call.talked && (last == null || call.at.isAfter(last))) last = call.at;
  }
  return last;
}
