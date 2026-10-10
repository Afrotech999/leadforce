# Campaign SMS

A standalone Android SMS app for running outreach campaigns to a large imported contact
list, from the phone's own SIM and message allowance. No gateway, no server, no account.

Built to `CAMPAIGN_SMS_APP_BUILD_SPEC.md`. Flutter (Material 3) for the UI, Kotlin for
everything that touches the radio.

## Getting the APK

Builds run only when started by hand: **Actions → Build APK → Run workflow**. Each
run publishes two release APKs to the `apk-latest` release (**Releases →
LeadForce — latest APK**). Take the **arm64** one for a phone; the universal one
installs on anything.

Install over the existing app rather than uninstalling — Android keeps the
database on an in-place update, and uninstalling deletes your campaign progress.

### Signing

Every build must be signed with the same key, or Android refuses to install one
build over another. The key is kept out of git: the workflow writes it to
`app/android/ci-signing.keystore` from the `SIGNING_KEYSTORE_BASE64` repository
secret (Settings → Secrets and variables → Actions), which holds the keystore
encoded with `base64 -w0`.

It is a throwaway sideload identity using the standard public debug credentials
(`androiddebugkey` / `android`). It is not a release credential and must never
sign a Play Store upload — that needs a real key kept out of the repository.

## Layout

```
app/
  lib/
    data/         schema, repository, phone normalization, segment counting, CSV import
    native/       platform-channel client
    state/        Riverpod providers
    ui/           screens
  android/app/src/main/kotlin/com/loomsolutions/campaign_sms/
    SendService.kt          the send engine (foreground service + wake lock)
    SmsSender.kt            SmsManager + per-part sent/delivered PendingIntents
    SendResultReceiver.kt   receipt handling and status reconciliation
    SmsDeliverReceiver.kt   inbound SMS while we hold the default-SMS role
    NativeBridge.kt         the one platform channel
    CampaignDb.kt           native access to the same SQLite file
```

## How it works

**One database, two languages.** The send engine and the SMS receivers must run when no
Flutter engine is alive — mid-batch process death, or a text arriving while the app is
swiped away. So Kotlin opens the same SQLite file directly. Dart owns the schema
(`lib/data/database.dart`) and is the only side that creates or migrates tables.

**Starting a campaign is a database write.** `campaign.status = 'in_progress'` *is* the
instruction; the channel call only wakes the service. That is what makes resume after a
crash or reboot fall out for free — the service restarts, finds the row, carries on.

**Nothing is marked sent optimistically.** Every message is journalled as `pending`
before the radio is touched. A contact only becomes `sent` on `RESULT_OK` from the sent
`PendingIntent`, and `delivered` only on the delivery report. Multipart messages track
per-part counts (`parts_total/ok/failed`) in the row itself, so a receipt that lands
after the process was killed still reconciles correctly.

**The UI polls, it is not pushed to.** The service writes progress to the database and
the Sending screen re-reads it once a second. One source of truth, no event ordering to
get wrong, and closing the screen does not stop anything.

## Decisions worth knowing about

- **sqflite, not drift.** The spec preferred drift. Because the native send engine shares
  the database file, both sides must use the same SQLite build; sqflite is a thin wrapper
  over Android's framework SQLite, which is exactly what `CampaignDb.kt` opens. drift
  bundles its own SQLite, which would put two different versions on one WAL file.
- **minSdk 24, not 23.** The Flutter 3.44 engine's floor is API 24.
- **Interrupted sends go to the retry queue, not back to the pool.** If the process dies
  between the send and the receipt, we cannot know whether the SMS left the phone. The
  spec asks for zero resends (§12.4) *and* for resuming ambiguous `queued` contacts
  (§7); those conflict. This app never gambles: the contact becomes `failed` with
  "Interrupted — result unknown" and the user chooses whether to retry.
- **No UPSERT anywhere.** Android 7 ships SQLite 3.9, which predates
  `ON CONFLICT ... DO UPDATE`.
- **Non-campaign inbound SMS is mirrored into the system inbox.** While this app holds
  the default-SMS role, personal texts and OTPs would otherwise be invisible to the
  user's normal Messages app after they switch back. This is a local ContentProvider
  write — nothing is forwarded anywhere.

## Testing on a device

```
adb install app/build/app/outputs/flutter-apk/app-debug.apk
```

The manual test pass that matters is §12 of the spec. Things that cannot be verified
without real SIMs and real numbers: actual delivery receipts, carrier behaviour, the
default-SMS role dialog, and dual-SIM selection.
