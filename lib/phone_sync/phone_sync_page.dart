import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_controller.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';

/// Settings for "Show in Phone and Messages" (Android).
class PhoneSyncPage extends ConsumerWidget {
  const PhoneSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PhoneSyncStatus status = ref.watch(phoneSyncProvider);
    final PhoneSyncController controller = ref.read(phoneSyncProvider.notifier);
    final PhoneSyncFields f = status.fields;
    final ColorScheme colors = Theme.of(context).colorScheme;

    Future<void> toggle(bool on) async {
      if (on) {
        await controller.enable(f);
        return;
      }
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Remove from the phone?'),
          content: const Text(
            'The copies in the phone\'s contacts are removed. Your contacts '
            'stay in the vault. Calls will show numbers instead of names.',
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove')),
          ],
        ),
      );
      if (ok == true) await controller.disable();
    }

    Widget field(String title, bool value, PhoneSyncFields Function(bool) set,
            {String? subtitle}) =>
        CheckboxListTile(
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          value: value,
          onChanged: status.running
              ? null
              : (bool? v) => controller.setFields(set(v ?? false)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Phone and Messages')),
      body: !status.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                SwitchListTile(
                  title: const Text('Show contacts in Phone and Messages'),
                  subtitle: const Text(
                      'Caller ID, the dialer and messaging apps see names'),
                  value: status.enabled,
                  onChanged: status.running ? null : toggle,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'This puts an unencrypted copy of the details you pick '
                      'below in the phone\'s own contacts, under a "ZT '
                      'Contacts" account. Any app you allow to read contacts '
                      'can see that copy. Your vault stays encrypted and is '
                      'still where you edit contacts; the copy updates while '
                      'the app is unlocked and is removed when you turn this '
                      'off or sign out.',
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                ),
                if (status.error != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: colors.error),
                    title: Text(status.error!),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('What leaves the vault'),
                ),
                const CheckboxListTile(
                  title: Text('Name'),
                  subtitle: Text('Always, so calls show who it is'),
                  value: true,
                  onChanged: null,
                ),
                field('Phone numbers', f.phones,
                    (bool v) => f.copyWith(phones: v),
                    subtitle: 'Needed for caller ID'),
                field('Photos', f.photos, (bool v) => f.copyWith(photos: v)),
                field('Email addresses', f.emails,
                    (bool v) => f.copyWith(emails: v)),
                field('Company', f.company, (bool v) => f.copyWith(company: v)),
                field('Addresses', f.addresses,
                    (bool v) => f.copyWith(addresses: v)),
                field('Birthdays', f.birthdays,
                    (bool v) => f.copyWith(birthdays: v)),
                field('Notes', f.notes, (bool v) => f.copyWith(notes: v)),
                field('Favourites', f.favourites,
                    (bool v) => f.copyWith(favourites: v),
                    subtitle: 'Starred in the phone too'),
                field('Send blocked contacts to voicemail',
                    f.blockedToVoicemail,
                    (bool v) => f.copyWith(blockedToVoicemail: v)),
                if (status.enabled)
                  ListTile(
                    leading: status.running
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    title: Text(status.running
                        ? 'Updating the phone\'s contacts…'
                        : status.onPhone == null
                            ? 'Waiting to update'
                            : '${status.onPhone} contacts on this phone'),
                    trailing: TextButton(
                      onPressed: status.running ? null : controller.run,
                      child: const Text('Update now'),
                    ),
                  ),
              ],
            ),
    );
  }
}
