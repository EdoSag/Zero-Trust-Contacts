import 'dart:async';

import 'package:zerotrust_contacts/birthdays/birthday_reminders.dart';

/// Records the reminders the app sets, instead of asking the phone.
class FakeBirthdayNotifier implements BirthdayNotifier {
  FakeBirthdayNotifier({this.allowed = true});

  bool allowed;
  int permissionAsks = 0;
  List<PlannedReminder> scheduled = <PlannedReminder>[];
  final StreamController<String> tapsController =
      StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return allowed;
  }

  @override
  Future<void> sync(List<PlannedReminder> reminders) async {
    scheduled = List<PlannedReminder>.of(reminders);
  }

  @override
  Stream<String> get taps => tapsController.stream;
}
