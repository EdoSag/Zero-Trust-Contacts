import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';
import 'package:zerotrust_contacts/birthdays/birthdays_page.dart';
import 'package:zerotrust_contacts/birthdays/birthdays_widget_bridge.dart';
import 'package:zerotrust_contacts/birthdays/occasions.dart';
import 'package:zerotrust_contacts/integrations/device_contacts_service.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';
import 'package:zerotrust_contacts/main.dart';
import 'package:zerotrust_contacts/models/vault_contact.dart';

import 'support/fake_birthday_notifier.dart';

VaultContact person(
  String id,
  String name, {
  List<String> birthdays = const <String>[],
  List<String> other = const <String>[],
  bool blocked = false,
}) =>
    VaultContact.fromJson(<String, dynamic>{
      'id': id,
      'displayName': name,
      'birthdays': birthdays,
      'other': other,
      'isBlocked': blocked,
      'createdAt': '2026-01-01T00:00:00Z',
      'updatedAt': '2026-01-01T00:00:00Z',
    });

final AppL10n en = lookupAppL10n(const Locale('en'));

void main() {
  group('dates', () {
    test('every stored form is read', () {
      expect(parseOccasionDate('1990-04-12'), (4, 12, 1990));
      expect(parseOccasionDate('--04-12'), (4, 12, null));
      expect(parseOccasionDate('19900412'), (4, 12, 1990));
      expect(parseOccasionDate('1604-04-12'), (4, 12, null)); // iCloud
      expect(parseOccasionDate('2000-02-30'), isNull);
      expect(parseOccasionDate('soon'), isNull);
    });

    test('birthdays and anniversaries of unblocked contacts, once each', () {
      final List<Occasion> all = occasionsOf(<VaultContact>[
        person('1', 'Noa',
            birthdays: <String>['1990-04-12', '--04-12'],
            other: <String>['Anniversary: 2015-06-01', 'https://noa.example']),
        person('2', 'Blocked', birthdays: <String>['1980-01-01'], blocked: true),
      ]);
      expect(all, hasLength(2));
      expect(all.first.kind, OccasionKind.birthday);
      expect(all.last.kind, OccasionKind.anniversary);
      expect(all.last.year, 2015);
    });

    test('next date, days and age; 29 February in other years', () {
      const Occasion leap = Occasion(
          contactId: 'x', name: 'Leap', kind: OccasionKind.birthday,
          month: 2, day: 29, year: 2000);
      final DateTime today = DateTime(2027, 2, 1);
      expect(leap.nextOn(today), DateTime(2027, 2, 28));
      expect(leap.daysUntil(today), 27);
      expect(leap.yearsOn(today), 27);
      expect(leap.nextOn(DateTime(2028, 2, 1)), DateTime(2028, 2, 29));
      // Already past this year: next year.
      expect(leap.nextOn(DateTime(2027, 3, 1)), DateTime(2028, 2, 29));
    });

    test('upcoming: soonest first, today included, within a window', () {
      final List<Occasion> all = occasionsOf(<VaultContact>[
        person('1', 'Later', birthdays: <String>['--12-01']),
        person('2', 'Today', birthdays: <String>['--06-10']),
        person('3', 'Soon', birthdays: <String>['--06-15']),
      ]);
      final DateTime today = DateTime(2027, 6, 10);
      expect(upcomingOccasions(all, today).map((Occasion o) => o.name),
          <String>['Today', 'Soon', 'Later']);
      expect(upcomingOccasions(all, today, days: 7).map((Occasion o) => o.name),
          <String>['Today', 'Soon']);
    });
  });

  group('reminders', () {
    final List<Occasion> occasions = occasionsOf(<VaultContact>[
      person('1', 'Noa',
          birthdays: <String>['1990-06-12'],
          other: <String>['Anniversary: 2015-06-20']),
    ]);
    const BirthdayReminderSettings on = BirthdayReminderSettings(enabled: true);

    test('none while off', () {
      expect(
          planBirthdayReminders(
              occasions: occasions,
              settings: const BirthdayReminderSettings(),
              now: DateTime(2027, 6, 1),
              l10n: en),
          isEmpty);
    });

    test('on the day at 9:00, with the age', () {
      final List<PlannedReminder> r = planBirthdayReminders(
          occasions: occasions, settings: on, now: DateTime(2027, 6, 1), l10n: en);
      expect(r.map((PlannedReminder x) => x.at), <DateTime>[
        DateTime(2027, 6, 12, 9),
        DateTime(2027, 6, 20, 9),
      ]);
      expect(r.first.title, 'Noa turns 37 today');
      expect(r.last.title, "Noa's anniversary is today");
      expect(r.first.contactId, '1');
      expect(PlannedReminder.contactIdOf(r.first.payload), '1');
    });

    test('past the time today: next year; day and week before', () {
      final List<PlannedReminder> r = planBirthdayReminders(
        occasions: occasions,
        settings: on.copyWith(dayBefore: true, weekBefore: true, anniversaries: false),
        now: DateTime(2027, 6, 12, 10),
        l10n: en,
      );
      expect(r.map((PlannedReminder x) => x.at), <DateTime>[
        DateTime(2028, 6, 5, 9),
        DateTime(2028, 6, 11, 9),
        DateTime(2028, 6, 12, 9),
      ]);
      expect(r[0].title, "Noa's birthday is in 7 days");
      expect(r[1].title, 'Noa turns 38 tomorrow');
    });

    test('names hidden: nothing of the contact in the text', () {
      final List<PlannedReminder> r = planBirthdayReminders(
        occasions: occasions,
        settings: on.copyWith(showNames: false),
        now: DateTime(2027, 6, 1),
        l10n: en,
      );
      expect(r.first.title, 'A birthday today');
      expect(r.first.body, isNot(contains('Noa')));
      expect(r.every((PlannedReminder x) => !x.title.contains('Noa')), isTrue);
    });

    test('same reminder, same id; capped at the limit', () {
      List<PlannedReminder> plan() => planBirthdayReminders(
          occasions: occasions, settings: on, now: DateTime(2027, 6, 1), l10n: en);
      expect(plan().first.id, plan().first.id);
      expect(
          planBirthdayReminders(
                  occasions: occasions,
                  settings: on,
                  now: DateTime(2027, 6, 1),
                  l10n: en,
                  limit: 1)
              .length,
          1);
    });

    test('settings survive a round trip and ignore junk', () {
      const BirthdayReminderSettings s = BirthdayReminderSettings(
          enabled: true, weekBefore: true, hour: 20, minute: 30,
          showNames: false, widgetShowsNames: true);
      expect(BirthdayReminderSettings.fromJson(jsonDecode(jsonEncode(s.toJson()))), s);
      expect(BirthdayReminderSettings.fromJson(<String, Object?>{'hour': 99}).hour, 9);
      expect(BirthdayReminderSettings.fromJson('x'), const BirthdayReminderSettings());
    });
  });

  test('widget snapshot keeps names out unless allowed', () {
    final List<Occasion> occasions = occasionsOf(<VaultContact>[
      person('1', 'Noa', birthdays: <String>['1990-06-12']),
    ]);
    final Map<String, Object?> hidden =
        jsonDecode(birthdaysWidgetSnapshot(occasions, showNames: false))
            as Map<String, Object?>;
    expect(jsonEncode(hidden), isNot(contains('Noa')));
    expect(jsonEncode(hidden), isNot(contains('1990')));
    expect((hidden['items'] as List<Object?>).single,
        <String, Object?>{'k': 'b', 'm': 6, 'd': 12});
    final String shown = birthdaysWidgetSnapshot(occasions, showNames: true);
    expect(shown, contains('"n":"Noa"'));
    expect(shown, contains('"y":1990'));
  });

  test('the widget asks to open the birthdays page', () {
    final IncomingRequest? r = IncomingRequest.fromMap(
        <Object?, Object?>{'kind': 'open', 'target': 'birthdays'});
    expect(r, isA<IncomingOpenPage>());
    expect((r! as IncomingOpenPage).target, BirthdaysPage.openTarget);
  });

  testWidgets('page lists what comes up and turns reminders on',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    final FakeBirthdayNotifier notifier = FakeBirthdayNotifier();
    final InMemoryPreferencesStore prefs = InMemoryPreferencesStore();
    final DateTime today = DateTime.now();
    final DateTime inTwo = today.add(const Duration(days: 2));
    String mmdd(DateTime d) =>
        '--${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final List<VaultContact> contacts = <VaultContact>[
      person('1', 'Noa Levi', birthdays: <String>[mmdd(inTwo)]),
      person('2', 'Adam Cohen', birthdays: <String>[mmdd(today)]),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ztAppConfigProvider.overrideWithValue(contactsAppConfig),
        birthdayNotifierProvider.overrideWithValue(notifier),
        ztPreferencesStoreProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        theme: ZtTheme.light(),
        localizationsDelegates: const <LocalizationsDelegate<Object?>>[
          AppL10n.delegate,
          ...ZtLanguages.delegates,
        ],
        supportedLocales: ZtLanguages.supported,
        home: BirthdaysPage(contacts: contacts, today: today),
      ),
    ));
    await tester.pumpAndSettle();

    // Today's comes first, above the one in two days.
    final double adam = tester.getTopLeft(find.text('Adam Cohen')).dy;
    final double noa = tester.getTopLeft(find.text('Noa Levi')).dy;
    expect(adam, lessThan(noa));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('In 2 days'), findsOneWidget);
    expect(find.text('On the day'), findsNothing);

    await tester.tap(find.byKey(const Key('birthday_reminders_switch')));
    await tester.pumpAndSettle();
    expect(notifier.permissionAsks, 1);
    expect(find.text('On the day'), findsOneWidget);
    expect(notifier.scheduled, isNotEmpty);
    expect(await prefs.read(BirthdayReminderSettingsController.key),
        contains('"enabled":true'));
  });
}
