# Zero-Trust Contacts

The address book of the Zero-Trust suite: end-to-end encrypted contacts,
shared address books and birthdays. On the phone it is called **ZT
Contacts**; in stores and on release pages, **Zero-Trust Contacts**. Same
account, settings and look as the other Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core). Part of the
[Zero-Trust suite](https://zerotrust.bz).

## What it does

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

### Birthdays
- Birthdays page (Organize → Birthdays soon, or the widget): every birthday
  and anniversary, soonest first, with the age they turn.
- Reminders on this phone: on the day, the day before and/or a week before,
  at a chosen time; anniversaries too. Set each time the app is unlocked for
  the coming year. "Show names in reminders" off keeps the name out of the
  notification ("A birthday today").
- Upcoming birthdays home screen widget. The vault can't be read while
  locked, so the app leaves the widget a snapshot of the dates; names only
  when "Show names in the birthdays widget" is on (off by default).

### Activity and keeping in touch
- Each contact's page shows what you did together in the other Zero-Trust
  apps: calls from ZT Phone (when its call history backup is on, or private
  calls), events from ZT Calendar (linked to the contact or inviting one of
  their emails) and tasks from ZT Tasks linked to them. "See all" lists it
  by month. Read only: Contacts never changes the other apps' data.
- Keep in touch: pick "every week" up to "every 6 months" on a contact. A
  reminder comes on the day the next talk is due, at the birthday reminder
  time; an answered call in ZT Phone or a call or message started from
  Contacts moves it on. Organize → Keep in touch lists who is due. Goals are
  their own synced items, so older app versions can't drop them.

### Shared address books
- Organize → Shared address books: keep contacts together with family or a
  team (the babysitter, the plumber, the kids' friends' parents). Make one,
  copy some of your own contacts in, and invite people by link or QR code;
  they join from the link (https://zerotrust.bz/join/contacts#…) after
  comparing a short code with you. Everyone in it adds and edits contacts;
  only owners rename it.
- Built on the shared spaces of the core (Z24): end-to-end encrypted with a
  key only the members' phones hold. The server sees member ids and
  encrypted blobs, never names or numbers. Photos, favourites and pins stay
  personal and aren't shared.
- Shared contacts stay out of your own address book; "Save to my contacts"
  makes your own copy.

### Shortcuts and big screens
- Long-press the app icon: New contact, Search, Scan card, Birthdays. Each
  opens once the vault is unlocked.
- From 600dp wide the tabs move to a side rail; from 840dp (tablets,
  unfolded foldables) a contact opens beside the list.

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

### Desktop contacts apps

- Settings, Desktop contacts apps: the phone itself serves the address book, read-only, to a computer's contacts app over CardDAV (Thunderbird, Apple Contacts, GNOME Evolution, DAVx5). No server is involved.
- HTTPS with the phone's own self-signed certificate (its SHA-256 fingerprint is shown to check), a random password, five tries per address, and only local-network addresses (home or office Wi-Fi) are answered. Port 8444, so ZT Calendar's bridge (8443) can run beside it.
- Runs only while the app is unlocked and stops on lock. The switch belongs to the account that turned it on. Blocked contacts, the trash and shared address books are left out, and every write is refused.

### Android integrations
- Reads Android device contacts via platform channel.
- Classifies contact source (`Account`, `SIM card`, `Phone`).
- Launches dialer and SMS intents from contact details.
- Includes configurable home-screen quick widget:
  - call selected contact
  - or open contact details

## Privacy

Like every Zero-Trust app, it is zero-knowledge: your data is encrypted on
your device, with keys made from your password, before anything is sent.
The server stores only ciphertext and your password itself is never
sent, so neither we nor anyone who breaks into the server can read your
data. The recovery key shown at sign-up is the only way back in if you
forget the password. How the keys work:
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core#key-hierarchy) and
[zerotrust.bz/security](https://zerotrust.bz/security/).

- Each contact is its own encrypted item in the shared `vault_items` table;
  photos are encrypted attachments. On the phone they sit in the core's
  encrypted store.
- Importing from Google reads the phone's own contacts database or a
  `.vcf` file: no Google sign-in, no Google API.
- A shared address book has a key only its members' phones hold. The
  server sees member ids and encrypted blobs, never names or numbers.
- Birthday reminders and the birthdays widget keep names out unless you
  turn them on.
- The desktop bridge answers only on the local network, read-only, and
  only while the app is unlocked.
- vCard exports are plain files.

## One account, one core

One Zero-Trust account opens every app in the suite. Sign-in, unlock
(fingerprint or face, auto-lock), the recovery key, settings, the look,
sync and languages come from
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), so they work
the same in every app. Accounts made before the core still sign in and
see their data.

## Install

Android: get the latest signed APK from this repository's
[Releases](https://github.com/EdoSag/Zero-Trust-Contacts/releases/latest),
or from [zerotrust.bz/install](https://zerotrust.bz/install/#contacts),
which also shows each file's SHA-256, the signing fingerprint and an
Obtainium link. GitHub Releases are the main way the apps are published.

Builds from GitHub check for a newer release themselves (Settings > About,
one anonymous request a day, can be turned off). Every Zero-Trust app is signed
with the same key, and Android only installs an update signed with it.

## Languages

English and Hebrew, with right-to-left layout. Choose under
Settings > Appearance > Language.

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

## Platform notes

- Flutter targets multiple platforms, but full native contact capabilities (device contacts, widget, call flows) are Android-centric.
- On non-Android platforms, device-contact features are limited.

## How it is built

- App bootstrap and gate: `lib/main.dart`, `lib/app/app_gate.dart`
- Providers and the contacts collection: `lib/app/`
- Contacts logic (merge, snapshots, activity, import/export): `lib/services/vault_repository.dart`
- Pre-core import: `lib/legacy/`
- Main screens: `lib/pages/home_page.dart`, `contact_detail_page.dart`,
  `create_contact_page.dart`, `settings_page.dart`, `google_import_page.dart`,
  `merge_conflicts_page.dart`, `vault_history_page.dart`

## Build from source

Flutter 3.47.9, the version CI pins (3.50 deprecates `material.dart` and
fails analyze).

```bash
# .env (not committed; CI writes its own). Public client values only:
# never a service-role key, because .env is bundled into the APK.
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>

flutter pub get
dart run zt_release_checks --app contacts   # shared release checks
flutter analyze && flutter test
flutter run
```

Never add `cryptography_flutter`: it breaks the core's key derivation and
sign-in fails.

Launcher icons are drawn from the suite's brand mark:
`flutter test tool/launcher_icon_test.dart`.

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`, and get a
test build. A release is one `Dev` → `main` pull request. Every push to
`main` runs the suite's release checks, builds a signed APK and a Google Play bundle
and publishes them as a GitHub Release named "Zero-Trust Contacts"
(`.github/workflows/android-apk.yml`). The workflow needs the repository
secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD`, the
keystore shared by all Zero-Trust apps.

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

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
