import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/linked/linked_apps.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/timeline/keep_in_touch.dart';
import 'package:zerotrust_contacts/timeline/person_timeline.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';

/// A sibling app's items, or none while they can't be read (locked, never
/// used, offline on first run).
List<Map<String, Object?>> linkedItems(WidgetRef ref, LinkedApp app) =>
    ref.watch(linkedItemsProvider(app)).value ??
    const <Map<String, Object?>>[];

/// Every "keep in touch" goal of the unlocked account.
final keepInTouchGoalsProvider = StreamProvider<List<KeepInTouch>>((Ref ref) async* {
  final VaultRepository repo = await ref.watch(vaultRepositoryProvider.future);
  yield await repo.loadKeepInTouch();
  await for (final Set<String> ids in repo.changes) {
    if (ids.any((String id) => id.startsWith('kit_'))) {
      yield await repo.loadKeepInTouch();
    }
  }
});

/// "Every 2 weeks", "Every month"...
String everyLabel(AppL10n l, int days) => switch (days) {
      7 => l.everyWeek,
      14 => l.everyTwoWeeks,
      30 => l.everyMonth,
      90 => l.everyThreeMonths,
      180 => l.everySixMonths,
      _ => l.everyNDays(days),
    };

String _when(BuildContext context, DateTime at, {bool allDay = false}) {
  final String locale = context.l10n.localeName;
  final DateTime now = DateTime.now();
  final DateFormat day = at.year == now.year
      ? DateFormat.MMMd(locale)
      : DateFormat.yMMMd(locale);
  return allDay ? day.format(at) : '${day.format(at)}, ${DateFormat.Hm(locale).format(at)}';
}

String _minutes(AppL10n l, Duration d) =>
    d.inMinutes >= 1 ? l.callMinutes(d.inMinutes) : l.callSeconds(d.inSeconds);

/// One row of a person's timeline.
class TimelineTile extends StatelessWidget {
  const TimelineTile({super.key, required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final (IconData icon, String title, String app) = switch (entry.kind) {
      TimelineKind.call => (
          switch (entry.direction) {
            CallDirection.incoming => Icons.call_received,
            CallDirection.outgoing => Icons.call_made,
            CallDirection.missed => Icons.call_missed,
            _ => Icons.call_outlined,
          },
          switch (entry.direction) {
            CallDirection.incoming => l.incomingCall,
            CallDirection.outgoing => l.outgoingCall,
            CallDirection.missed => l.missedCall,
            _ => l.call,
          },
          'ZT Phone',
        ),
      TimelineKind.event => (
          entry.repeats ? Icons.event_repeat_outlined : Icons.event_outlined,
          entry.title.isEmpty ? l.event : entry.title,
          'ZT Calendar',
        ),
      TimelineKind.task => (
          entry.done ? Icons.task_alt : Icons.radio_button_unchecked,
          entry.title.isEmpty ? l.task : entry.title,
          'ZT Tasks',
        ),
    };
    final Duration? length = entry.duration;
    final String detail = <String>[
      _when(context, entry.at, allDay: entry.allDay),
      if (entry.kind == TimelineKind.call && length != null && length > Duration.zero)
        _minutes(l, length),
      app,
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon,
          color: entry.direction == CallDirection.missed ? colors.error : null),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: entry.done
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(detail),
    );
  }
}

/// On a contact's page: how often to keep in touch, and what the contact
/// was part of in ZT Phone, ZT Calendar and ZT Tasks (C-1, C-3).
class PersonActivitySection extends ConsumerWidget {
  const PersonActivitySection({
    super.key,
    required this.contact,
    required this.saved,
  });

  final VaultContact contact;

  /// Only vault contacts can have a keep-in-touch goal.
  final bool saved;

  static const int _shown = 5;

  Future<void> _pickGoal(
      BuildContext context, WidgetRef ref, int? current) async {
    final AppL10n l = context.l10n;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(
        title: Text(l.keepInTouchWith(contact.displayName)),
        children: <Widget>[
          for (final int days in <int>[0, ...KeepInTouch.choices])
            ListTile(
              leading: Icon(days == (current ?? 0)
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(days == 0 ? l.keepInTouchOff : everyLabel(l, days)),
              onTap: () => Navigator.of(ctx).pop(days),
            ),
        ],
      ),
    );
    if (picked == null || picked == (current ?? 0)) return;
    if (picked > 0 && (current ?? 0) == 0) {
      // A reminder comes when it's time: ask once to show notifications.
      try {
        await ref
            .read(vaultControllerProvider.notifier)
            .whileShowingSystemUi(ref.read(birthdayNotifierProvider).requestPermission);
      } on Object {
        // The list still shows who is due.
      }
    }
    final VaultRepository repo = await ref.read(vaultRepositoryProvider.future);
    await repo.setKeepInTouch(contact.id, picked == 0 ? null : picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<Map<String, Object?>> phone = linkedItems(ref, LinkedApp.phone);
    final List<TimelineEntry> timeline = timelineFor(
      contact,
      phone: phone,
      calendar: linkedItems(ref, LinkedApp.calendar),
      tasks: linkedItems(ref, LinkedApp.tasks),
    );
    final int? goal = saved
        ? (ref.watch(keepInTouchGoalsProvider).value ?? const <KeepInTouch>[])
            .where((KeepInTouch k) => k.contactId == contact.id)
            .map((KeepInTouch k) => k.everyDays)
            .firstOrNull
        : null;
    final DateTime? last = lastTalked(contact, phone);
    final DateTime now = DateTime.now();
    final int? since = last == null
        ? null
        : DateTime(now.year, now.month, now.day)
            .difference(DateTime(last.year, last.month, last.day))
            .inDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (saved)
          ListTile(
            key: const Key('keep_in_touch_tile'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.favorite_border),
            title: Text(goal == null ? l.keepInTouch : everyLabel(l, goal)),
            subtitle: Text(<String>[
              if (goal == null) l.keepInTouchHint,
              if (since != null) l.lastTalkedDaysAgo(since)
              else if (goal != null) l.noTalksYet,
            ].join(' · ')),
            trailing: goal != null && (since == null || since >= goal)
                ? Chip(label: Text(l.dueNow))
                : const Icon(Icons.chevron_right),
            onTap: () => _pickGoal(context, ref, goal),
          ),
        const SizedBox(height: 8),
        Text(l.activity, style: Theme.of(context).textTheme.titleSmall),
        if (timeline.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l.activityEmpty(contact.displayName),
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          )
        else ...<Widget>[
          for (final TimelineEntry e in timeline.take(_shown))
            TimelineTile(entry: e),
          if (timeline.length > _shown)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PersonTimelinePage(contact: contact),
                  ),
                ),
                child: Text(l.seeAllActivity(timeline.length)),
              ),
            ),
        ],
      ],
    );
  }
}

/// A contact's whole timeline, newest first, by month.
class PersonTimelinePage extends ConsumerWidget {
  const PersonTimelinePage({super.key, required this.contact});

  final VaultContact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<TimelineEntry> timeline = timelineFor(
      contact,
      phone: linkedItems(ref, LinkedApp.phone),
      calendar: linkedItems(ref, LinkedApp.calendar),
      tasks: linkedItems(ref, LinkedApp.tasks),
    );
    final DateFormat month = DateFormat.yMMMM(context.l10n.localeName);
    final List<Widget> rows = <Widget>[];
    String? header;
    for (final TimelineEntry e in timeline) {
      final String h = month.format(e.at);
      if (h != header) {
        header = h;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(h,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ));
      }
      rows.add(TimelineTile(entry: e));
    }
    return Scaffold(
      appBar: AppBar(title: Text(contact.displayName)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: rows,
      ),
    );
  }
}

/// Everyone with a keep-in-touch goal, the most overdue first (C-3).
class KeepInTouchPage extends ConsumerWidget {
  const KeepInTouchPage({super.key, required this.contacts});

  final List<VaultContact> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppL10n l = context.l10n;
    final DateTime now = DateTime.now();
    final List<TouchStatus> statuses = touchStatuses(
      goals: ref.watch(keepInTouchGoalsProvider).value ?? const <KeepInTouch>[],
      contacts: contacts,
      phoneItems: linkedItems(ref, LinkedApp.phone),
      now: now,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.keepInTouch)),
      body: statuses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.keepInTouchEmpty, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: <Widget>[
                for (final TouchStatus s in statuses)
                  ListTile(
                    leading: ContactAvatar(contact: s.contact),
                    title: Text(s.contact.displayName),
                    subtitle: Text(<String>[
                      everyLabel(l, s.everyDays),
                      if (s.lastTalked == null)
                        l.noTalksYet
                      else
                        l.lastTalkedDaysAgo(s.daysSince(now)),
                    ].join(' · ')),
                    trailing: s.isDue(now)
                        ? Chip(label: Text(l.dueNow))
                        : Text(l.inDays(s.dueOn
                            .difference(DateTime(now.year, now.month, now.day))
                            .inDays)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContactDetailPage(contact: s.contact),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
