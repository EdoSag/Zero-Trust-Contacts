import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/linked/linked_apps.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';
import 'package:zerotrust_contacts/timeline/keep_in_touch.dart';
import 'package:zerotrust_contacts/timeline/person_activity.dart';
import 'package:zerotrust_contacts/timeline/person_timeline.dart';

VaultContact person(
  String id,
  String name, {
  List<String> phones = const <String>[],
  List<String> emails = const <String>[],
  String? lastContactedAt,
}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'phones': phones,
      'emails': emails,
      'lastContactedAt': ?lastContactedAt,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

Map<String, Object?> call(String id, String number, DateTime at,
        {int type = 2, int duration = 60, String kind = 'call_history'}) =>
    <String, Object?>{
      '_id': id,
      'kind': kind,
      'number': number,
      'type': type,
      'date': at.millisecondsSinceEpoch,
      'duration': duration,
    };

final AppL10n en = lookupAppL10n(const Locale('en'));

void main() {
  final VaultContact mom = person('mom', 'Mom',
      phones: <String>['+972 54-123-4567'], emails: <String>['Mom@Example.com']);

  test('numbers match with or without the country code', () {
    expect(phoneLookupKey('+972 54-123-4567'), phoneLookupKey('054-1234567'));
    expect(phoneLookupKey('054-1234567;ext=2'), '541234567');
  });

  test('calls with the contact, once each, and who answered', () {
    final DateTime t = DateTime(2026, 11, 1, 10);
    final List<TimelineEntry> calls = callsWith(mom, <Map<String, Object?>>[
      call('a', '054-1234567', t),
      // The same call also kept as a private call.
      call('b', '0541234567', t, kind: 'private_call'),
      call('c', '054-1234567', t.add(const Duration(days: 1)), type: 3, duration: 0),
      call('d', '050-9999999', t),
      <String, Object?>{'kind': 'blocked_number', 'number': '054-1234567'},
    ]);
    expect(calls, hasLength(2));
    final TimelineEntry missed =
        calls.firstWhere((TimelineEntry e) => e.direction == CallDirection.missed);
    expect(missed.talked, isFalse);
    expect(
        calls.firstWhere((TimelineEntry e) => e.direction == CallDirection.outgoing).talked,
        isTrue);
  });

  test('events by contact link or guest email, tasks by link, newest first', () {
    final List<TimelineEntry> all = timelineFor(
      mom,
      phone: <Map<String, Object?>>[call('c1', '0541234567', DateTime(2026, 10, 5))],
      calendar: <Map<String, Object?>>[
        <String, Object?>{
          '_id': 'e1', 'kind': 'event', 'title': 'Dinner',
          'start': '2026-10-20T17:00:00Z', 'contactIds': <String>['mom'],
        },
        <String, Object?>{
          '_id': 'e2', 'kind': 'event', 'title': 'Birthday party',
          'start': '2026-11-02', 'allDay': true,
          'guestEmails': <String>['mom@example.com'],
        },
        <String, Object?>{
          '_id': 'e3', 'kind': 'event', 'title': 'Not hers',
          'start': '2026-11-03', 'contactIds': <String>['dad'],
        },
      ],
      tasks: <Map<String, Object?>>[
        <String, Object?>{
          '_id': 't1', 'title': 'Buy a gift', 'dueDate': '2026-10-30T09:00:00Z',
          'contactIds': <String>['mom'], 'isCompleted': true,
        },
        <String, Object?>{
          '_id': 't2', 'title': 'Deleted', 'dueDate': '2026-10-31T09:00:00Z',
          'contactIds': <String>['mom'], 'deletedAt': '2026-10-31T10:00:00Z',
        },
        <String, Object?>{
          '_id': 'l1', 'kind': 'list', 'contactIds': <String>['mom'],
        },
      ],
    );
    expect(all.map((TimelineEntry e) => e.itemId), <String>['e2', 't1', 'e1', 'c1']);
    expect(all.first.allDay, isTrue);
    expect(all[1].done, isTrue);
  });

  test('last talked: the latest answered call or a call from Contacts', () {
    final DateTime answered = DateTime(2026, 11, 10, 12);
    final List<Map<String, Object?>> phone = <Map<String, Object?>>[
      call('a', '054-1234567', answered, type: 1, duration: 120),
      call('b', '054-1234567', DateTime(2026, 11, 12), type: 1, duration: 0),
      call('c', '054-1234567', DateTime(2026, 11, 13), type: 3, duration: 0),
    ];
    expect(lastTalked(mom, phone), answered);
    final VaultContact called = person('mom', 'Mom',
        phones: mom.phones, lastContactedAt: '2026-11-15T08:00:00Z');
    expect(lastTalked(called, phone), DateTime.utc(2026, 11, 15, 8).toLocal());
  });

  group('keep in touch', () {
    final VaultContact dan = person('dan', 'Dan', phones: <String>['050-7654321']);
    final DateTime now = DateTime(2026, 11, 22, 15);

    test('due dates, the most overdue first, gone contacts skipped', () {
      final List<TouchStatus> statuses = touchStatuses(
        goals: const <KeepInTouch>[
          KeepInTouch(contactId: 'mom', everyDays: 14),
          KeepInTouch(contactId: 'dan', everyDays: 30),
          KeepInTouch(contactId: 'gone', everyDays: 7),
        ],
        contacts: <VaultContact>[mom, dan],
        phoneItems: <Map<String, Object?>>[
          call('a', '054-1234567', DateTime(2026, 11, 1, 18)),
        ],
        now: now,
      );
      expect(statuses.map((TouchStatus s) => s.contact.id), <String>['mom', 'dan']);
      final TouchStatus m = statuses.first;
      expect(m.dueOn, DateTime(2026, 11, 15));
      expect(m.isDue(now), isTrue);
      expect(m.daysSince(now), 21);
      // Never talked: due today.
      expect(statuses.last.lastTalked, isNull);
      expect(statuses.last.dueOn, DateTime(2026, 11, 22));
      expect(statuses.last.isDue(now), isTrue);
    });

    test('a call moves the goal on', () {
      final List<TouchStatus> statuses = touchStatuses(
        goals: const <KeepInTouch>[KeepInTouch(contactId: 'mom', everyDays: 14)],
        contacts: <VaultContact>[mom],
        phoneItems: <Map<String, Object?>>[
          call('a', '054-1234567', DateTime(2026, 11, 20, 9)),
        ],
        now: now,
      );
      expect(statuses.single.dueOn, DateTime(2026, 12, 4));
      expect(statuses.single.isDue(now), isFalse);
    });

    test('reminders on the due day, or tomorrow when it has passed', () {
      const BirthdayReminderSettings settings = BirthdayReminderSettings();
      final List<TouchStatus> statuses = <TouchStatus>[
        TouchStatus(contact: mom, everyDays: 14, lastTalked: DateTime(2026, 11, 1),
            dueOn: DateTime(2026, 11, 15)),
        TouchStatus(contact: dan, everyDays: 30, lastTalked: DateTime(2026, 11, 20),
            dueOn: DateTime(2026, 12, 20)),
      ];
      final List<PlannedReminder> reminders = planKeepInTouchReminders(
          statuses: statuses, settings: settings, now: now, l10n: en);
      expect(reminders.first.at, DateTime(2026, 11, 23, 9));
      expect(reminders.first.title, contains('Mom'));
      expect(reminders.first.contactId, 'mom');
      expect(reminders.last.at, DateTime(2026, 12, 20, 9));
      expect(reminders.first.id, isNot(reminders.last.id));

      final List<PlannedReminder> hidden = planKeepInTouchReminders(
          statuses: statuses,
          settings: settings.copyWith(showNames: false),
          now: now,
          l10n: en);
      expect(hidden.first.title, isNot(contains('Mom')));
      expect(hidden.first.body, isNot(contains('Mom')));
    });

    test('goals round-trip as their own items', () {
      const KeepInTouch goal = KeepInTouch(contactId: 'mom', everyDays: 14);
      final Map<String, Object?> json = keepInTouchCollection.toJson(goal);
      final KeepInTouch back =
          keepInTouchCollection.fromJson('kit_mom', json, DateTime(2026));
      expect(back.contactId, 'mom');
      expect(back.everyDays, 14);
      expect(keepInTouchCollection.idOf(goal), 'kit_mom');
    });
  });

  testWidgets('a contact page shows the goal, then calls and events by date',
      (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final DateTime called = DateTime(now.year, now.month, now.day - 3, 10);
    final DateTime met = DateTime(now.year, now.month, now.day - 1, 18);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        keepInTouchGoalsProvider.overrideWith((Ref ref) => Stream.value(
            const <KeepInTouch>[KeepInTouch(contactId: 'mom', everyDays: 14)])),
        linkedItemsProvider.overrideWith((Ref ref, LinkedApp app) => Stream.value(
              switch (app) {
                LinkedApp.phone => <Map<String, Object?>>[
                    call('c1', '054-1234567', called, duration: 300),
                  ],
                LinkedApp.calendar => <Map<String, Object?>>[
                    <String, Object?>{
                      '_id': 'e1', 'kind': 'event', 'title': 'Dinner with Mom',
                      'start': met.toUtc().toIso8601String(),
                      'contactIds': <String>['mom'],
                    },
                  ],
                LinkedApp.tasks => const <Map<String, Object?>>[],
              },
            )),
      ],
      child: MaterialApp(
        theme: ZtTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          AppL10n.delegate,
          ...ZtLanguages.delegates,
        ],
        supportedLocales: ZtLanguages.supported,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[PersonActivitySection(contact: mom, saved: true)],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final double height = tester.getSize(find.byType(Scaffold)).height;
    final Finder goal = find.text('Every 2 weeks');
    final Finder dinner = find.text('Dinner with Mom');
    final Finder outgoing = find.text('Outgoing call');
    expect(goal, findsOneWidget);
    expect(find.text('Last talked 3 days ago'), findsOneWidget);
    // Goal first, then the newest activity first, all on screen.
    expect(tester.getTopLeft(dinner).dy, greaterThan(tester.getTopLeft(goal).dy));
    expect(tester.getTopLeft(outgoing).dy, greaterThan(tester.getTopLeft(dinner).dy));
    expect(tester.getBottomLeft(outgoing).dy, lessThan(height));
    expect(find.textContaining('5 min'), findsOneWidget);
  });
}
