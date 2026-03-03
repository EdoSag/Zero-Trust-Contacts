# Zero-Trust Contacts

Zero-Trust Contacts is a Flutter contact vault that combines local encrypted storage, cloud sync, and Android contact integration.

It is built for security-first personal CRM workflows:
- sign in with Supabase auth
- keep a local encrypted contact vault
- sync encrypted vault data to cloud with merge/conflict handling
- manage, organize, and recover contacts with snapshots and activity logs

## What The App Offers

### Vault and security
- Password-based vault key derivation using PBKDF2-HMAC-SHA256 (600000 iterations, 256-bit key).
- Local SQLCipher-backed encrypted database for saved contact payloads.
- Optional biometric lock flow with dedicated unlock screen.
- Automatic lock on app pause/inactivity (idle timeout currently 3 minutes).
- Security activity log (auth, sync, lock/unlock, import/export events).

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
- Manual sync now + push local + pull cloud.
- Automatic background sync scheduler:
  - on startup
  - on app resume
  - on configurable interval (`SYNC_INTERVAL_HOURS`)
- Per-contact merge with conflict detection when local and cloud changed since last sync.
- Conflict resolution screen (keep local / keep cloud / use merged).
- Restore points (snapshots):
  - manual snapshots
  - automatic daily/weekly cadence snapshots
  - restore from snapshot

### Import, export, and sharing
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

## Security and Cloud Model (Current)

- Cloud vault blobs are stored in `encrypted_contacts.data_blob`.
- Cloud blob format is encrypted (`AES-256-GCM`) before upload.
- Legacy plaintext cloud blobs are auto-migrated to encrypted format during sync/pull.
- Supabase RLS policies limit `profiles` and `encrypted_contacts` rows to the authenticated user.
- Salt is also stored in `profiles` to support key re-derivation on sign-in.

## Platform Notes

- Flutter targets multiple platforms, but full native contact capabilities (device contacts, widget, call flows) are Android-centric.
- On non-Android platforms, device-contact features are limited.

## Configuration

Create a `.env` file with:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `APP_INTERNAL_SALT` (minimum 16 characters)
- `IS_DEBUG_MODE` (`true` or `false`)
- `SYNC_INTERVAL_HOURS` (integer > 0)

## Supabase Setup

1. Apply migration:
   - `supabase/migrations/20260303_shared_auth.sql`
2. Ensure Supabase Auth behavior matches this app flow:
   - Registration expects an immediate active session.
   - If email confirmation is enabled, first-time sign-up flow will not proceed as implemented.

## Run Locally

```bash
flutter pub get
flutter run
```

## Key Files

- App bootstrap: `lib/main.dart`
- Routing and guards: `lib/globals/router.dart`
- Auth orchestration: `lib/auth_service.dart`
- Local security/DB primitives: `lib/security_service.dart`
- Vault domain logic (sync/merge/export/snapshots/activity): `lib/services/vault_repository.dart`
- Auto sync scheduler: `lib/services/vault_sync_scheduler.dart`
- Biometric lock service: `lib/services/app_lock_service.dart`
- Main screens:
  - `lib/pages/login_screen.dart`
  - `lib/pages/unlock_screen.dart`
  - `lib/pages/home_page.dart`
  - `lib/pages/contact_detail_page.dart`
  - `lib/pages/create_contact_page.dart`
  - `lib/pages/account_page.dart`
  - `lib/pages/merge_conflicts_page.dart`
