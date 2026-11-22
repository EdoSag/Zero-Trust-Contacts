import 'package:flutter/foundation.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/timeline/person_timeline.dart';

/// "Keep in touch" (C-3): how often the user wants to talk to a contact.
/// Its own synced item (`keep_in_touch`, id `kit_<contactId>`), so app
/// versions from before it simply don't see it and can't drop it when they
/// edit the contact.
@immutable
class KeepInTouch {
  const KeepInTouch({required this.contactId, required this.everyDays});

  final String contactId;
  final int everyDays;

  static String itemIdFor(String contactId) => 'kit_$contactId';

  /// What the picker offers, in days.
  static const List<int> choices = <int>[7, 14, 30, 90, 180];
}

final ZtCollection<KeepInTouch> keepInTouchCollection = ZtCollection<KeepInTouch>(
  kind: 'keep_in_touch',
  version: 1,
  fromJson: (String id, Map<String, Object?> json, DateTime _) => KeepInTouch(
    contactId: '${json['contactId'] ?? ''}',
    everyDays: (json['everyDays'] as num?)?.toInt() ?? 30,
  ),
  toJson: (KeepInTouch k) => <String, Object?>{
    'contactId': k.contactId,
    'everyDays': k.everyDays,
  },
  idOf: (KeepInTouch k) => KeepInTouch.itemIdFor(k.contactId),
);

/// Where a contact with a keep-in-touch goal stands.
@immutable
class TouchStatus {
  const TouchStatus({
    required this.contact,
    required this.everyDays,
    required this.lastTalked,
    required this.dueOn,
  });

  final VaultContact contact;
  final int everyDays;

  /// Null when they never talked (as far as the apps know).
  final DateTime? lastTalked;

  /// The day the next talk is due (today or earlier: due now).
  final DateTime dueOn;

  bool isDue(DateTime now) =>
      !dueOn.isAfter(DateTime(now.year, now.month, now.day));

  int daysSince(DateTime now) => lastTalked == null
      ? 0
      : DateTime(now.year, now.month, now.day)
          .difference(DateTime(
              lastTalked!.year, lastTalked!.month, lastTalked!.day))
          .inDays;
}

/// The status of each goal in [goals] whose contact still exists, the most
/// overdue first.
List<TouchStatus> touchStatuses({
  required Iterable<KeepInTouch> goals,
  required Iterable<VaultContact> contacts,
  required Iterable<Map<String, Object?>> phoneItems,
  required DateTime now,
}) {
  final Map<String, VaultContact> byId = <String, VaultContact>{
    for (final VaultContact c in contacts) c.id: c,
  };
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<TouchStatus> out = <TouchStatus>[];
  for (final KeepInTouch goal in goals) {
    final VaultContact? contact = byId[goal.contactId];
    if (contact == null || goal.everyDays <= 0) continue;
    final DateTime? last = lastTalked(contact, phoneItems);
    final DateTime dueOn = last == null
        ? today
        : DateTime(last.year, last.month, last.day + goal.everyDays);
    out.add(TouchStatus(
      contact: contact,
      everyDays: goal.everyDays,
      lastTalked: last,
      dueOn: dueOn,
    ));
  }
  out.sort((TouchStatus a, TouchStatus b) => a.dueOn.compareTo(b.dueOn));
  return out;
}

/// A reminder on the day each goal comes due, at the birthday reminder
/// time (or the next day when that time has passed). Uses the same
/// "Show names in reminders" switch.
List<PlannedReminder> planKeepInTouchReminders({
  required List<TouchStatus> statuses,
  required BirthdayReminderSettings settings,
  required DateTime now,
  AppL10n? l10n,
}) {
  final AppL10n l = l10n ?? currentL10n;
  final List<PlannedReminder> out = <PlannedReminder>[];
  for (final TouchStatus s in statuses) {
    DateTime at = DateTime(s.dueOn.year, s.dueOn.month, s.dueOn.day,
        settings.hour, settings.minute);
    if (!at.isAfter(now)) {
      at = DateTime(now.year, now.month, now.day + 1, settings.hour,
          settings.minute);
    }
    out.add(PlannedReminder(
      id: PlannedReminder.idFor(
          'kit|${s.contact.id}|${s.dueOn.year}-${s.dueOn.month}-${s.dueOn.day}'),
      at: at,
      title: settings.showNames
          ? l.keepInTouchReminder(s.contact.displayName)
          : l.keepInTouchReminderHidden,
      body: settings.showNames
          ? l.keepInTouchReminderBody
          : l.birthdayReminderHiddenBody,
      contactId: s.contact.id,
    ));
  }
  return out;
}
