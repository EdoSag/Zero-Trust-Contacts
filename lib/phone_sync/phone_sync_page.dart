import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_controller.dart';
import 'package:zerotrust_contacts/phone_sync/phone_sync_plan.dart';
import 'package:zerotrust_contacts/l10n/l10n.dart';

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
          title: Text(context.l10n.removeFromThePhone),
          content: Text(
            context.l10n.theCopiesInThePhones,
          ),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.remove)),
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
      appBar: AppBar(title: Text(context.l10n.phoneAndMessages)),
      body: !status.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                SwitchListTile(
                  title: Text(context.l10n.showContactsInPhoneAnd),
                  subtitle: Text(
                      context.l10n.callerIdTheDialerAnd),
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
                      context.l10n.thisPutsAnUnencryptedCopy,
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ),
                ),
                if (status.error != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: colors.error),
                    title: Text(status.error!),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(context.l10n.whatLeavesTheVault),
                ),
                CheckboxListTile(
                  title: Text(context.l10n.name),
                  subtitle: Text(context.l10n.alwaysSoCallsShowWho),
                  value: true,
                  onChanged: null,
                ),
                field(context.l10n.phoneNumbers, f.phones,
                    (bool v) => f.copyWith(phones: v),
                    subtitle: context.l10n.neededForCallerId),
                field(context.l10n.photos, f.photos, (bool v) => f.copyWith(photos: v)),
                field(context.l10n.emailAddresses, f.emails,
                    (bool v) => f.copyWith(emails: v)),
                field(context.l10n.company, f.company, (bool v) => f.copyWith(company: v)),
                field(context.l10n.addresses, f.addresses,
                    (bool v) => f.copyWith(addresses: v)),
                field(context.l10n.birthdays, f.birthdays,
                    (bool v) => f.copyWith(birthdays: v)),
                field(context.l10n.notes, f.notes, (bool v) => f.copyWith(notes: v)),
                field(context.l10n.favourites, f.favourites,
                    (bool v) => f.copyWith(favourites: v),
                    subtitle: context.l10n.starredInThePhoneToo),
                field(context.l10n.sendBlockedContactsToVoicemail,
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
                        ? context.l10n.updatingThePhonesContacts
                        : status.onPhone == null
                            ? context.l10n.waitingToUpdate
                            : context.l10n.nOnThisPhone(status.onPhone!)),
                    trailing: TextButton(
                      onPressed: status.running ? null : controller.run,
                      child: Text(context.l10n.updateNow),
                    ),
                  ),
              ],
            ),
    );
  }
}
