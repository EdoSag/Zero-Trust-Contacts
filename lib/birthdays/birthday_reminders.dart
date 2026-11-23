import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/birthdays/occasions.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

/// What the user picked for birthday and anniversary reminders (C6). Kept
/// on this phone only, like every notification setting.
@immutable
class BirthdayReminderSettings {
  const BirthdayReminderSettings({
    this.enabled = false,
    this.onTheDay = true,
    this.dayBefore = false,
    this.weekBefore = false,
    this.hour = 9,
    this.minute = 0,
    this.anniversaries = true,
    this.showNames = true,
    this.widgetShowsNames = false,
  });

  final bool enabled;
  final bool onTheDay;
  final bool dayBefore;
  final bool weekBefore;

  /// The time of day the reminder comes, in local time.
  final int hour;
  final int minute;

  /// Wedding anniversaries remind too.
  final bool anniversaries;

  /// The contact's name is in the reminder. Off: "A birthday today", and
  /// the name is only seen after unlocking.
  final bool showNames;

  /// The birthdays widget shows names (W3: details on the home screen are
  /// off until the user turns them on). Off: it shows only when.
  final bool widgetShowsNames;

  /// Days before the day that get a reminder.
  List<int> get leadDays => <int>[
        if (onTheDay) 0,
        if (dayBefore) 1,
        if (weekBefore) 7,
      ];

  BirthdayReminderSettings copyWith({
    bool? enabled,
    bool? onTheDay,
    bool? dayBefore,
    bool? weekBefore,
    int? hour,
    int? minute,
    bool? anniversaries,
    bool? showNames,
    bool? widgetShowsNames,
  }) =>
      BirthdayReminderSettings(
        enabled: enabled ?? this.enabled,
        onTheDay: onTheDay ?? this.onTheDay,
        dayBefore: dayBefore ?? this.dayBefore,
        weekBefore: weekBefore ?? this.weekBefore,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        anniversaries: anniversaries ?? this.anniversaries,
        showNames: showNames ?? this.showNames,
        widgetShowsNames: widgetShowsNames ?? this.widgetShowsNames,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'onTheDay': onTheDay,
        'dayBefore': dayBefore,
        'weekBefore': weekBefore,
        'hour': hour,
        'minute': minute,
        'anniversaries': anniversaries,
        'showNames': showNames,
        'widgetShowsNames': widgetShowsNames,
      };

  static BirthdayReminderSettings fromJson(Object? raw) {
    if (raw is! Map) return const BirthdayReminderSettings();
    bool flag(String key, bool fallback) =>
        raw[key] is bool ? raw[key] as bool : fallback;
    int number(String key, int fallback, int max) {
      final Object? v = raw[key];
      return v is int && v >= 0 && v <= max ? v : fallback;
    }

    const BirthdayReminderSettings d = BirthdayReminderSettings();
    return BirthdayReminderSettings(
      enabled: flag('enabled', d.enabled),
      onTheDay: flag('onTheDay', d.onTheDay),
      dayBefore: flag('dayBefore', d.dayBefore),
      weekBefore: flag('weekBefore', d.weekBefore),
      hour: number('hour', d.hour, 23),
      minute: number('minute', d.minute, 59),
      anniversaries: flag('anniversaries', d.anniversaries),
      showNames: flag('showNames', d.showNames),
      widgetShowsNames: flag('widgetShowsNames', d.widgetShowsNames),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BirthdayReminderSettings &&
      jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// One reminder the phone should show.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.contactId,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Opened when the reminder is tapped (after unlocking).
  final String contactId;

  /// The time is in it too, so a reminder whose time changed (a new
  /// reminder time in settings) differs from the one already set, and
  /// [BirthdayNotifier.sync] sets it again.
  String get payload => jsonEncode(<String, String>{
        'c': contactId,
        't': '${at.millisecondsSinceEpoch}',
      });

  static String? contactIdOf(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object? json = jsonDecode(payload);
      return json is Map && json['c'] is String ? json['c'] as String : null;
    } on FormatException {
      return null;
    }
  }

  /// FNV-1a, so the same reminder gets the same id on every run.
  static int idFor(String key) {
    int hash = 0x811c9dc5;
    for (final int unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.contactId == contactId;

  @override
  int get hashCode => Object.hash(id, at, title, body, contactId);
}

/// The reminders for the coming year, soonest first. Android keeps a few
/// hundred alarms per app at most, so only the first [limit] are set; the
/// rest are set the next time the app is opened.
List<PlannedReminder> planBirthdayReminders({
  required List<Occasion> occasions,
  required BirthdayReminderSettings settings,
  required DateTime now,
  AppL10n? l10n,
  int limit = 100,
}) {
  if (!settings.enabled || settings.leadDays.isEmpty) {
    return const <PlannedReminder>[];
  }
  final AppL10n l = l10n ?? currentL10n;
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<PlannedReminder> out = <PlannedReminder>[];
  for (final Occasion o in occasions) {
    if (o.kind == OccasionKind.anniversary && !settings.anniversaries) {
      continue;
    }
    for (final int lead in settings.leadDays) {
      // The next day whose reminder is still ahead: this year's, or next
      // year's when this year's time has passed.
      for (final DateTime from in <DateTime>[
        today,
        o.nextOn(today).add(const Duration(days: 1)),
      ]) {
        final DateTime day = o.nextOn(from);
        final DateTime at = DateTime(
            day.year, day.month, day.day - lead, settings.hour, settings.minute);
        if (!at.isAfter(now)) continue;
        out.add(PlannedReminder(
          id: PlannedReminder.idFor(
              '${o.contactId}|${o.kind.name}|${day.year}-${day.month}-${day.day}|$lead'),
          at: at,
          title: _title(l, o, lead, settings.showNames, day),
          body: settings.showNames ? l.birthdayReminderBody : l.birthdayReminderHiddenBody,
          contactId: o.contactId,
        ));
        break;
      }
    }
  }
  out.sort((PlannedReminder a, PlannedReminder b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

String _title(AppL10n l, Occasion o, int lead, bool names, DateTime day) {
  final bool birthday = o.kind == OccasionKind.birthday;
  if (!names) {
    return switch (lead) {
      0 => birthday ? l.reminderHiddenBirthdayToday : l.reminderHiddenAnniversaryToday,
      1 => birthday ? l.reminderHiddenBirthdayTomorrow : l.reminderHiddenAnniversaryTomorrow,
      _ => birthday ? l.reminderHiddenBirthdayInDays(lead) : l.reminderHiddenAnniversaryInDays(lead),
    };
  }
  final int? years = o.year == null ? null : day.year - o.year!;
  final bool showYears = years != null && years > 0 && years < 150;
  if (birthday) {
    return switch (lead) {
      0 => showYears ? l.reminderBirthdayTodayTurns(o.name, years) : l.reminderBirthdayToday(o.name),
      1 => showYears ? l.reminderBirthdayTomorrowTurns(o.name, years) : l.reminderBirthdayTomorrow(o.name),
      _ => l.reminderBirthdayInDays(o.name, lead),
    };
  }
  return switch (lead) {
    0 => l.reminderAnniversaryToday(o.name),
    1 => l.reminderAnniversaryTomorrow(o.name),
    _ => l.reminderAnniversaryInDays(o.name, lead),
  };
}

/// Shows the reminders. Replaced in tests.
abstract class BirthdayNotifier {
  /// Asks to show notifications; true when allowed.
  Future<bool> requestPermission();

  /// Makes the scheduled reminders exactly [reminders].
  Future<void> sync(List<PlannedReminder> reminders);

  /// Contact ids of reminders the user tapped, the one that opened the
  /// app first.
  Stream<String> get taps;
}

class _NoBirthdayNotifier implements BirthdayNotifier {
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> sync(List<PlannedReminder> reminders) async {}
  @override
  Stream<String> get taps => const Stream<String>.empty();
}

class LocalBirthdayNotifier implements BirthdayNotifier {
  LocalBirthdayNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _taps = StreamController<String>.broadcast();
  String? _launch;
  Future<void>? _ready;

  /// Only reminders this app sets carry this in their payload, so other
  /// notifications are never touched by [sync].
  static const String _channelId = 'birthday_reminders';

  Future<void> _init() => _ready ??= () async {
        tzdata.initializeTimeZones();
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestSoundPermission: false,
              requestBadgePermission: false,
            ),
          ),
          onDidReceiveNotificationResponse: (NotificationResponse r) {
            final String? id = PlannedReminder.contactIdOf(r.payload);
            if (id != null) _taps.add(id);
          },
        );
        final NotificationAppLaunchDetails? launch =
            await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp ?? false) {
          _launch = PlannedReminder.contactIdOf(
              launch?.notificationResponse?.payload);
        }
      }();

  @override
  Stream<String> get taps async* {
    try {
      await _init();
    } on Object {
      return;
    }
    final String? launched = _launch;
    _launch = null;
    if (launched != null) yield launched;
    yield* _taps.stream;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final IOSFlutterLocalNotificationsPlugin? ios =
        _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return false;
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          currentL10n.birthdayRemindersChannel,
          channelDescription: currentL10n.birthdayRemindersChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
          // The lock screen shows "ZT Contacts", not the name.
          visibility: NotificationVisibility.private,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  @override
  Future<void> sync(List<PlannedReminder> reminders) async {
    await _init();
    final Map<int, PlannedReminder> wanted = <int, PlannedReminder>{
      for (final PlannedReminder r in reminders) r.id: r,
    };
    for (final PendingNotificationRequest p
        in await _plugin.pendingNotificationRequests()) {
      final PlannedReminder? want = wanted[p.id];
      if (want == null) {
        await _plugin.cancel(id: p.id);
      } else if (p.title == want.title &&
          p.body == want.body &&
          p.payload == want.payload) {
        wanted.remove(p.id);
      }
    }
    for (final PlannedReminder r in wanted.values) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        payload: r.payload,
        // An absolute instant, worked out in the phone's own time zone.
        scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        // A birthday doesn't need the exact minute, and inexact alarms
        // need no special permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

final birthdayNotifierProvider = Provider<BirthdayNotifier>((Ref ref) {
  if (kIsWeb ||
      !(defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return _NoBirthdayNotifier();
  }
  return LocalBirthdayNotifier();
});

/// The reminder settings, read from this phone's preferences.
class BirthdayReminderSettingsController
    extends AsyncNotifier<BirthdayReminderSettings> {
  static const String key = 'birthday_reminders';

  @override
  Future<BirthdayReminderSettings> build() async {
    try {
      final String? raw = await ref.read(ztPreferencesStoreProvider).read(key);
      return raw == null
          ? const BirthdayReminderSettings()
          : BirthdayReminderSettings.fromJson(jsonDecode(raw));
    } on Object {
      return const BirthdayReminderSettings();
    }
  }

  Future<void> save(BirthdayReminderSettings settings) async {
    state = AsyncData<BirthdayReminderSettings>(settings);
    try {
      await ref
          .read(ztPreferencesStoreProvider)
          .write(key, jsonEncode(settings.toJson()));
    } on Object {
      // Kept for this run; saved again with the next change.
    }
  }
}

final birthdayReminderSettingsProvider = AsyncNotifierProvider<
    BirthdayReminderSettingsController,
    BirthdayReminderSettings>(BirthdayReminderSettingsController.new);
