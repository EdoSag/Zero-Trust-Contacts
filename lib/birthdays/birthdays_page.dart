import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';
import 'package:zerotrust_contacts/birthdays/birthdays_widget_bridge.dart';
import 'package:zerotrust_contacts/birthdays/occasions.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/linked/linked_apps.dart';
import 'package:zerotrust_contacts/pages/contact_detail_page.dart';
import 'package:zerotrust_contacts/timeline/keep_in_touch.dart';
import 'package:zerotrust_contacts/timeline/person_activity.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';
import 'package:zerotrust_contacts/widgets/contact_avatar.dart';

/// Sets this phone's reminders and the home screen widget from [contacts]:
/// birthdays and anniversaries (C6, W8) and keep-in-touch goals (C-3).
/// Called whenever the address book, the goals or the settings change while
/// the app is unlocked; nothing about a contact reaches the phone at any
/// other time. One call sets every reminder the app has, so none is lost.
Future<void> syncBirthdays(
  WidgetRef ref,
  List<VaultContact> contacts, {
  DateTime? now,
}) async {
  final DateTime at = now ?? DateTime.now();
  final BirthdayReminderSettings settings =
      await ref.read(birthdayReminderSettingsProvider.future);
  final List<Occasion> occasions = occasionsOf(contacts);
  // Goals as last loaded; HomePage syncs again whenever they change. Only
  // once unlocked: before that nothing can be read.
  final bool unlocked = ref.read(linkedKeysProvider).containsKey(LinkedApp.phone);
  final List<PlannedReminder> touch = !unlocked
      ? const <PlannedReminder>[]
      : planKeepInTouchReminders(
          statuses: touchStatuses(
            goals: ref.read(keepInTouchGoalsProvider).value ??
                const <KeepInTouch>[],
            contacts: contacts,
            phoneItems: ref.read(linkedItemsProvider(LinkedApp.phone)).value ??
                const <Map<String, Object?>>[],
            now: at,
          ),
          settings: settings,
          now: at,
        );
  try {
    await ref.read(birthdayNotifierProvider).sync(<PlannedReminder>[
      ...planBirthdayReminders(
        occasions: occasions,
        settings: settings,
        now: at,
      ),
      ...touch,
    ]);
  } on Object {
    // Notifications not allowed or unavailable; the list still works.
  }
  await const BirthdaysWidgetBridge()
      .update(occasions, showNames: settings.widgetShowsNames);
}

/// "When" of an occasion: Today, Tomorrow, In 3 days.
String occasionWhen(AppL10n l, int days) => switch (days) {
      0 => l.today,
      1 => l.tomorrow,
      _ => l.inDays(days),
    };

/// Upcoming birthdays and anniversaries of the address book, and this
/// phone's reminder settings.
class BirthdaysPage extends ConsumerStatefulWidget {
  const BirthdaysPage({super.key, required this.contacts, this.today});

  /// What the birthdays widget asks to open.
  static const String openTarget = 'birthdays';

  final List<VaultContact> contacts;

  /// For tests: the day the list counts from.
  final DateTime? today;

  @override
  ConsumerState<BirthdaysPage> createState() => _BirthdaysPageState();
}

class _BirthdaysPageState extends ConsumerState<BirthdaysPage> {
  DateTime get _today => widget.today ?? DateTime.now();

  /// The contacts as they are now: a contact opened from here may get a new
  /// birthday, be blocked or be deleted, and the reminders and widget must
  /// follow that, not the list the page was opened with.
  late List<VaultContact> _contacts = widget.contacts;
  StreamSubscription<Set<String>>? _changes;

  @override
  void initState() {
    super.initState();
    ref.read(vaultRepositoryProvider.future).then((VaultRepository repo) {
      if (!mounted) return;
      _changes = repo.changes.listen((_) => _reload(repo));
    }).catchError((Object _) {});
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _reload(VaultRepository repo) async {
    try {
      final List<VaultContact> now = await repo.loadSavedContacts();
      if (mounted) setState(() => _contacts = now);
    } on Object {
      // Keeps the last list.
    }
  }

  Future<void> _save(BirthdayReminderSettings next) async {
    final BirthdayReminderSettings current =
        await ref.read(birthdayReminderSettingsProvider.future);
    if (next.enabled && !current.enabled) {
      final bool allowed = await ref
          .read(vaultControllerProvider.notifier)
          .whileShowingSystemUi(
              ref.read(birthdayNotifierProvider).requestPermission);
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(context.l10n.notificationsAreOffForZt),
          ));
        }
        return;
      }
    }
    await ref.read(birthdayReminderSettingsProvider.notifier).save(next);
    await syncBirthdays(ref, _contacts);
  }

  Future<void> _pickTime(BirthdayReminderSettings s) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
    );
    if (picked != null) {
      await _save(s.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  Map<String, VaultContact> get _byId => <String, VaultContact>{
        for (final VaultContact c in _contacts) c.id: c,
      };

  Widget _settingsCard(BirthdayReminderSettings s) {
    final AppL10n l = context.l10n;
    final String time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay(hour: s.hour, minute: s.minute));
    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            key: const Key('birthday_reminders_switch'),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l.birthdayReminders),
            subtitle: Text(l.birthdayRemindersSubtitle),
            value: s.enabled,
            onChanged: (bool on) => _save(s.copyWith(enabled: on)),
          ),
          if (s.enabled) ...<Widget>[
            const Divider(height: 1),
            CheckboxListTile(
              title: Text(l.remindOnTheDay),
              value: s.onTheDay,
              onChanged: (bool? v) => _save(s.copyWith(onTheDay: v ?? false)),
            ),
            CheckboxListTile(
              title: Text(l.remindTheDayBefore),
              value: s.dayBefore,
              onChanged: (bool? v) => _save(s.copyWith(dayBefore: v ?? false)),
            ),
            CheckboxListTile(
              title: Text(l.remindAWeekBefore),
              value: s.weekBefore,
              onChanged: (bool? v) =>
                  _save(s.copyWith(weekBefore: v ?? false)),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(l.reminderTime),
              trailing: Text(time),
              onTap: () => _pickTime(s),
            ),
            SwitchListTile(
              title: Text(l.remindAnniversariesToo),
              value: s.anniversaries,
              onChanged: (bool on) => _save(s.copyWith(anniversaries: on)),
            ),
            SwitchListTile(
              title: Text(l.showNamesInReminders),
              subtitle: Text(l.showNamesInRemindersSubtitle),
              value: s.showNames,
              onChanged: (bool on) => _save(s.copyWith(showNames: on)),
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.widgets_outlined),
            title: Text(l.showNamesOnHomeScreen),
            subtitle: Text(l.showNamesOnHomeScreenSubtitle),
            value: s.widgetShowsNames,
            onChanged: (bool on) => _save(s.copyWith(widgetShowsNames: on)),
          ),
        ],
      ),
    );
  }

  Widget _tile(Occasion o) {
    final AppL10n l = context.l10n;
    final VaultContact? contact = _byId[o.contactId];
    final int days = o.daysUntil(_today);
    final int? years = o.yearsOn(_today);
    final String date =
        DateFormat.MMMMEEEEd(l.localeName).format(o.nextOn(_today));
    final String what = o.kind == OccasionKind.birthday
        ? (years == null ? l.birthday : l.turnsYears(years))
        : (years == null ? l.anniversary : l.anniversaryYears(years));
    return ListTile(
      leading: contact == null
          ? const CircleAvatar(child: Icon(Icons.cake_outlined))
          : ContactAvatar(contact: contact),
      title: Text(o.name),
      subtitle: Text('$what · $date'),
      trailing: Text(
        occasionWhen(l, days),
        style: days <= 1
            ? TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              )
            : null,
      ),
      onTap: contact == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ContactDetailPage(contact: contact))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppL10n l = context.l10n;
    final BirthdayReminderSettings settings =
        ref.watch(birthdayReminderSettingsProvider).value ??
            const BirthdayReminderSettings();
    final List<Occasion> list =
        upcomingOccasions(occasionsOf(_contacts), _today);
    final List<Occasion> soon =
        list.where((Occasion o) => o.daysUntil(_today) <= 30).toList();
    final List<Occasion> later =
        list.where((Occasion o) => o.daysUntil(_today) > 30).toList();
    return Scaffold(
      appBar: AppBar(title: Text(l.birthdaysAndAnniversaries)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _settingsCard(settings),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l.noBirthdaysYet, textAlign: TextAlign.center),
            ),
          if (soon.isNotEmpty) _header(l.nextThirtyDays),
          for (final Occasion o in soon) _tile(o),
          if (later.isNotEmpty) _header(l.laterThisYear),
          for (final Occasion o in later) _tile(o),
        ],
      ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
