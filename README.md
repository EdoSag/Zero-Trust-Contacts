# Zero-Trust Contacts

Zero-Trust Contacts ("ZT Contacts" on the phone) is the address book of the
Zero-Trust suite. It runs on [Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core):
one Zero-Trust account across Notes, Tasks, Fitness and Contacts, end-to-end
encrypted contacts, an encrypted on-device store, and the suite's shared
sign-in, unlock, settings and look.

## What The App Offers

### Vault and security (from the core)
- Zero-Trust account shared with the other apps: recovery key, password reset,
  biometric unlock, auto-lock, sign out of other devices, account deletion.
- Each contact is its own end-to-end encrypted item (`vault_items`), so edits
  on two devices merge per contact instead of overwriting a whole vault.
- Encrypted on-device store (SQLite3 Multiple Ciphers); photos are encrypted
  attachments.
- Security activity log (sync, imports, exports, restores).

### Contact management
- Create rich vault contacts with fields like:
  - first/last name, company, notes
  - multi phone, multi email, addresses, labels, birthdays, custom "other"
- Edit/delete existing vault contacts.
- Save device contacts into the vault.
- Favorite and pin contacts.
- Interaction tracking (calls/messages increment usage metrics).
- Search + source filtering + sorting (A-Z, recent, source).

### Highlights and organization
- Highlights tab for pinned, favorites, and frequent contacts.
- Organize tab with:
  - label counts
  - smart groups (upcoming birthdays, stale contacts, missing phone)
  - duplicate detection and one-tap merge

### Sync, merge, and recovery
- Live sync through the core: on start, on resume, on every change, and
  through Supabase realtime.
- When the same contact is edited on two devices the newer edit wins, and the
  other shows up under Settings → Sync conflicts (keep, use mine, or combine).
- Restore points: taken before bulk changes (imports, merges, restores) plus
  daily and weekly, and restorable from Settings.

### Import, export, and sharing
- Import from Google in a few taps (Settings, or the banner on an empty vault):
  - Android: pick a Google account already on the phone; every contact is read
    on-device from Android's contacts database with all fields (names, phones,
    emails, addresses, company/title, notes, birthdays, labels, websites, starred).
  - Any platform: open the `.vcf` file from contacts.google.com → Export →
    "vCard (for iOS Contacts)".
  - No Google sign-in or Google API, nothing leaves the device unencrypted.
  - Shows new/updated/already-here counts before writing; matches on phone,
    email (or name when neither has any) and merges new details instead of
    duplicating, so re-importing is safe. A restore point is taken first.
- Encrypted JSON export/import (passphrase-protected).
- vCard export/import.
- Secure one-contact share package generation (encrypted payload + passphrase + expiry).
- Current UI uses clipboard for export/share flows.

### Android integrations
- Reads Android device contacts via platform channel.
- Classifies contact source (`Account`, `SIM card`, `Phone`).
- Launches dialer and SMS intents from contact details.
- Includes configurable home-screen quick widget:
  - call selected contact
  - or open contact details

## Contacts from before the core

Versions up to 1.0 kept one encrypted blob per account in
`encrypted_contacts`, a local SQLite database (`vault_contacts.db`) and plain
photos in the `contactsProfilePictures` bucket. Their key was PBKDF2 of
`password:<app pepper>`, so it differs from the core's legacy key.
`lib/legacy/` brings that data over once per account:

- A phone that ran the old version imports with the key it already holds; a
  new phone asks once for the password from before.
- The cloud copy and any unsynced local contacts are merged; a contact another
  device already imported is never overwritten.
- After import the old local database and keys are removed from the phone.
  Old cloud rows and bucket photos are left in place, so older builds of the
  other apps keep working.

## Platform Notes

- Flutter targets multiple platforms, but full native contact capabilities (device contacts, widget, call flows) are Android-centric.
- On non-Android platforms, device-contact features are limited.

## Configuration

Create a `.env` file (not committed) with:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

The APK workflow writes it from the `ENV_FILE` secret, or from the suite's
public client values.

## Run Locally

```bash
flutter pub get
flutter run
flutter test
```

The launcher icon is drawn from the suite's brand mark by
`flutter test tool/launcher_icon_test.dart`.

## Key Files

- App bootstrap and gate: `lib/main.dart`, `lib/app/app_gate.dart`
- Providers and the contacts collection: `lib/app/`
- Contacts logic (merge, snapshots, activity, import/export): `lib/services/vault_repository.dart`
- Pre-core import: `lib/legacy/`
- Main screens: `lib/pages/home_page.dart`, `contact_detail_page.dart`,
  `create_contact_page.dart`, `settings_page.dart`, `google_import_page.dart`,
  `merge_conflicts_page.dart`, `vault_history_page.dart`

## License

Copyright (C) 2026 EdoSag (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
