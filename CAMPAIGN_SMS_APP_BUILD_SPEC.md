# Campaign SMS App — Build Specification

**For:** Abraham Seifu / Loom Solutions
**Target:** Android only (Flutter + Kotlin). iOS cannot send SMS programmatically — do not attempt it.
**How to use this file:** hand it to Claude Code (or open it in Android Studio and build section by section). It is written to be built end-to-end. Set Claude Code's effort to `high`.

---

## 0. One-paragraph summary of what we're building

A standalone Android SMS app, completely separate from the phone's stock Messages app, used to run outreach campaigns to a large imported contact list (~6,783 car-buyer/seller contacts). The user opens the app, taps the next pre-made batch of 100 contacts, and sends. Each contact receives a **plain individual SMS from the user's own SIM and message allowance** — no group thread, no paid gateway. A contact that has been sent to, or that has replied, is permanently excluded from all future batches. Replies land inside this app's own inbox, not the personal Messages app. The app must look and feel as clean and polished as Google Messages / Samsung Messages, with all the normal SMS features, plus the batch engine underneath.

---

## 1. Instructions for the build agent (read first)

When you have enough information to act, act. Do not re-derive decisions already made in this spec or re-litigate them; if you are weighing an implementation choice, pick one and note why in a comment.

Don't add features, refactor, or introduce abstractions beyond what this spec requires. Do the simplest thing that works well. Only validate at real boundaries (CSV import, incoming SMS, SIM state). Trust the Android framework guarantees.

Build in the order the sections are numbered. After each major module (import, batch engine, sender, inbox), write a small manual-test checklist and confirm it against the acceptance criteria in §12 before moving on.

Do not build a release APK or sign anything until the user explicitly asks. Debug builds for local testing on the user's own device are fine.

---

## 2. Hard technical constraints (the things that *will* bite)

These are the real-world failure modes. The design in this spec exists to defeat them. Do not "simplify" them away.

1. **Programmatic send is real, but Android throttles it.** `SmsManager.sendTextMessage()` sends from the SIM with no per-message tap. But Android shows a system confirmation dialog after roughly **30 messages in 30 minutes** from a non-default SMS app. Two defenses, both required:
   - The app becomes the **default SMS handler** while a campaign runs (a default app is not subject to that dialog for its own sends).
   - A configurable **inter-message delay** (default 5s, user-adjustable 3–10s) paces sends so they look human and stay under carrier heuristics.

2. **Carrier-side spam control (Ethio Telecom / Safaricom Ethiopia) is outside our control.** No app setting defeats it. Mitigate only: pace sends, cap daily volume (user-set, default 100/day), vary nothing about the send mechanism. Make the daily cap a visible, enforced setting — not a suggestion.

3. **Default-handler responsibility.** To read incoming replies, the app **must** be registered as the default SMS app (Android only delivers `SMS_DELIVER` to the default app). While it is default it receives **all** SMS, including personal texts and bank OTPs. The design keeps the user in control: they switch this app to default around a campaign, then switch back. The app must (a) make switching one tap, (b) clearly show current default status, and (c) remind the user to switch back when a campaign ends. See §9.

4. **Amharic = UCS-2 = 70 chars/segment.** A message with any non-GSM-7 character bills at 70 chars per segment instead of 160. A live segment counter must warn before sending and show cost impact. Use `divideMessage()` + `sendMultipartTextMessage()` for multipart.

5. **Process death mid-batch.** Android can kill the app, or the phone reboots. The send engine must run in a **foreground service with a wake lock**, and every send must be journaled to the database *before* it fires and updated on the delivery receipt — so on restart it resumes at the exact next unsent contact and never resends.

6. **Silent send failure.** A message can fail without throwing. Never mark a contact "sent" optimistically. Mark "sent" only on the `PendingIntent` sent-result `Activity.RESULT_OK`, and "delivered" only on the delivery-report intent. Failures go to a **retry queue**, not to "sent".

7. **Data loss on reinstall.** All campaign state lives in a local DB. Auto-export the DB (and a CSV of contact statuses) to a user-visible folder after every campaign and on demand, so progress survives reinstall/device loss.

---

## 3. Tech stack

- **Flutter** for UI (Material 3 / Material You, dynamic color).
- **Kotlin platform channel** for all SMS operations (sending, receiving, default-handler role, multi-SIM). Do **not** rely on a third-party Flutter SMS plugin for sending — write the native channel; it's the reliable path and gives full control over sent/delivered `PendingIntent`s.
- **SQLite** via `drift` (Flutter) or `sqflite`. Prefer `drift` for typed queries and migrations.
- **State management:** Riverpod (or Bloc). Keep it light.
- **Min SDK:** API 23 (Android 6). Target the latest stable API.
- Required native pieces (Kotlin):
  - A `SmsManager` sender with per-message `sentIntent` + `deliveryIntent`.
  - A `BroadcastReceiver` for `SMS_DELIVER` (incoming) — required to be the default app.
  - The default-SMS-app role components Android demands (see §9.1): an SMS receiver, an MMS receiver, a "quick response" service, and a launcher Activity. Without all four the app can't be offered as default.
  - `SubscriptionManager` for dual-SIM selection.

---

## 4. Data model

Tables (drift/sqflite). Use these names/fields.

**contact**
- `id` INTEGER PK
- `phone_e164` TEXT UNIQUE NOT NULL  — normalized `+2519…`/`+2517…`
- `phone_local` TEXT  — `09…` display form
- `name` TEXT NULL
- `source` TEXT  — original account(s): Gari / Jiji / mekina.net / facebook
- `status` TEXT NOT NULL DEFAULT 'not_sent'  — enum: `not_sent | queued | sent | delivered | failed | replied | do_not_contact`
- `batch_id` INTEGER NULL  — FK to batch
- `last_sent_at` INTEGER NULL
- `last_error` TEXT NULL
- `attempts` INTEGER NOT NULL DEFAULT 0

**batch**
- `id` INTEGER PK
- `name` TEXT  — "Batch 1", "Batch 2", …
- `size` INTEGER  — normally 100
- `status` TEXT  — `pending | in_progress | completed | partial`
- `created_at` INTEGER
- `completed_at` INTEGER NULL

**campaign** (a send run of one batch with one message)
- `id` INTEGER PK
- `batch_id` INTEGER FK
- `message_template` TEXT  — may contain `{name}`
- `sim_subscription_id` INTEGER NULL
- `delay_seconds` INTEGER
- `started_at` INTEGER
- `finished_at` INTEGER NULL
- `sent_count`, `delivered_count`, `failed_count` INTEGER

**message** (one row per individual SMS attempt — the audit trail)
- `id` INTEGER PK
- `contact_id` INTEGER FK
- `campaign_id` INTEGER FK NULL  — null for one-off/personal messages
- `direction` TEXT  — `outbound | inbound`
- `body` TEXT
- `segments` INTEGER
- `status` TEXT  — `pending | sent | delivered | failed`
- `error` TEXT NULL
- `created_at` INTEGER
- `sent_at` INTEGER NULL
- `delivered_at` INTEGER NULL

**thread** (a conversation with one contact — for the inbox)
- `id` INTEGER PK
- `contact_id` INTEGER FK UNIQUE
- `last_message_at` INTEGER
- `unread_count` INTEGER
- `snippet` TEXT

**settings** (single row / key-value)
- daily_cap (default 100), default_delay_seconds (default 5), current_sim_subscription_id, last_default_handler_prompt_at, campaign_active (bool)

**Status transition rules (enforce in one place — a repository method, never scattered):**
- `not_sent → queued` when a batch send starts.
- `queued → sent` only on `RESULT_OK` from the sent `PendingIntent`.
- `sent → delivered` on delivery report.
- `queued/sent → failed` on any error; increment `attempts`.
- **any → replied** the instant an inbound SMS arrives from that number. This is terminal for campaigns.
- **any → do_not_contact** if the inbound body matches STOP / አቁም / stop-keywords, or the user manually blocks. Terminal.
- A contact whose status is `sent | delivered | replied | do_not_contact | queued` is **never** eligible for a new batch. Only `not_sent` (and optionally `failed`, if the user chooses "retry failed") can be batched.

---

## 5. Batch pre-generation (the "already-made groups of 100")

On first import, and again whenever new `not_sent` contacts exist without a batch:
- Take all `not_sent` contacts with `batch_id IS NULL`, order by id, and assign them into batches of `settings.batch_size` (default 100).
- Name them sequentially continuing from the last batch number.
- The user never manually multi-selects to build a batch. They just pick the next `pending` batch.
- Batches that are `completed` render greyed-out with a checkmark and their sent/replied stats.
- Re-generation must be **idempotent**: never move a contact already assigned, never put a non-`not_sent` contact into a batch.

Provide a manual action "Rebuild remaining batches" that only touches `not_sent`, `batch_id IS NULL` contacts — used after adding a new import or after moving contacts to do_not_contact.

---

## 6. CSV import

- Import from the deduplicated spreadsheet. Accept CSV with columns: name, phone (both `+2519…` and `09…`), source. Be liberal in parsing headers.
- Normalize every phone to E.164 (`+251` + 9-digit core, first digit 9 or 7). Reuse the same normalization logic already applied to the source sheet: strip non-digits, drop leading `0`/`251`/`00251`, validate 9 digits starting 9 or 7.
- **Deduplicate on import** against existing `phone_e164` — never insert a duplicate; if a name arrives for an existing nameless contact, fill it in.
- Rows that don't normalize go to an **"Needs review"** screen (not silently dropped), matching the review sheet already produced.
- Show an import summary: imported, duplicates skipped, needs-review count.

---

## 7. The send engine (native Kotlin, driven from Flutter)

Runs inside a **foreground service** with a persistent notification ("Sending Batch 3 — 34/100") and a wake lock.

Pseudo-flow for a campaign:
```
for each contact in batch where status == not_sent (snapshot at start, re-check per item):
    if daily_sent_today >= daily_cap: stop, mark batch 'partial', notify user
    re-check contact.status == not_sent  # skip if it flipped to replied/dnc meanwhile
    render body = template with {name} filled (fallback to generic if name null)
    write message row status='pending', set contact.status='queued'   # journal BEFORE send
    segments = SmsManager.divideMessage(body)
    send via sendMultipartTextMessage(dest, sim, parts, [sentIntents], [deliveryIntents])
    await sentIntent result:
        RESULT_OK        -> message.status='sent',    contact.status='sent',    daily_sent_today++
        any error        -> message.status='failed',  contact.status='failed',  contact.last_error=...
    later, deliveryIntent -> message.status='delivered', contact.status='delivered'
    sleep(delay_seconds)  # configurable, jitter ±1s
```
- **Per-SIM sending:** use `SmsManager.getSmsManagerForSubscriptionId(subId)` when the user has picked a SIM.
- **Pause/Resume/Stop** controls. Stop marks the batch `partial`; unsent contacts stay `not_sent` and roll into the next run.
- **Resume after crash/reboot:** on service start, find any `in_progress` campaign and continue from the first `not_sent`/`queued` contact. Because journaling happens before the send, a contact stuck in `queued` on restart is re-checked and re-sent only if no `message.status='sent'` exists for it — otherwise it's reconciled to `sent`. Guarantee: **never send twice.**
- **Retry queue:** `failed` contacts can be retried in a separate action (max attempts configurable, default 2). Retries respect the daily cap.

---

## 8. Incoming replies & the walled-off inbox

- The default-app `SMS_DELIVER` receiver catches every inbound SMS while the app is default.
- On inbound: match sender to a `contact` by `phone_e164`.
  - If it matches a campaign contact: set `contact.status='replied'` (terminal — pulled from all future batches), append an inbound `message`, update/creating its `thread`, bump `unread_count`. **This reply stays in this app** — that's the whole point.
  - If STOP-keyword: also set `do_not_contact`.
  - If it does **not** match any contact (i.e. a personal text that arrived because the app is currently default): store it, but visually separate it — see below — so the user can read it, and it can be exported/forwarded. Do not let personal texts pollute campaign threads.
- **Inbox UI:** two clearly separated sections/tabs:
  - **Campaign replies** — threads with contacts from the list.
  - **Other** — everything else received while default (personal/OTP). Clearly labeled "Received while this app was your default SMS app."
- Full threaded conversation view per contact: history, compose, send a normal reply (uses the same native sender, one-off, `campaign_id = null`).

---

## 9. Default-SMS-app handling (do this carefully)

### 9.1 Manifest components required to be eligible as default
Android will only offer the app as default if it declares all of:
- `BroadcastReceiver` with action `android.provider.Telephony.SMS_DELIVER` (`RECEIVE_SMS`-guarded).
- `BroadcastReceiver` with action `android.provider.Telephony.WAP_PUSH_DELIVER` for MMS (mime `application/vnd.wap.mms-message`).
- A `Service` for `android.intent.action.RESPOND_VIA_MESSAGE` (quick-response, `SEND_RESPOND_VIA_MESSAGE`-guarded).
- A launchable `Activity` that can `SENDTO`/`sms:` `mmsto:`.
Permissions: `SEND_SMS`, `RECEIVE_SMS`, `READ_SMS`, `WRITE_SMS`, `READ_PHONE_STATE`, `READ_PHONE_NUMBERS`, foreground-service perms, `POST_NOTIFICATIONS`.

### 9.2 Requesting the role
- Use `RoleManager.createRequestRoleIntent(RoleManager.ROLE_SMS)` on API 29+, and the legacy `Telephony.Sms.Intents` default-app change intent below that.
- **UX flow around a campaign:**
  1. User taps "Start Campaign".
  2. If not currently default: show a clear explainer ("To send and receive campaign replies, this app needs to be your default SMS app during the campaign. Your personal messages will arrive here until you switch back. We'll remind you.") → one-tap request.
  3. Run campaign.
  4. On finish (or Stop): show a prominent, unmissable reminder + one-tap action to **switch default back** to their previous app (record which app was default before, so the button restores it). Also fire a notification.
- Persist `campaign_active`; if the app is default and no campaign is active for >X minutes, nudge the user to switch back.

---

## 10. Screens (match Google/Samsung Messages polish)

Material 3, dynamic color, clean, no clutter. Screens:

1. **Home / Batches** — list of batches: pending (tappable), in-progress (live progress), completed (greyed, with stats). Top bar: total contacts, remaining not_sent, daily cap used today (e.g. "40 / 100 sent today"). FAB or clear primary button: "Send next batch".
2. **Compose campaign** — pick batch (defaults to next pending), message editor with `{name}` chip insertion, **live segment + cost counter** (shows GSM-7 vs UCS-2, segment count, total messages = segments × recipients, warning if Amharic), SIM picker (if dual), delay slider, "Preview first 3 rendered messages", Send.
3. **Sending (live)** — progress bar N/100, current contact, sent/failed tallies, Pause/Stop. Backed by the foreground service.
4. **Inbox** — two tabs: Campaign replies / Other. Thread list like a normal SMS app (avatar, name or number, snippet, time, unread dot).
5. **Thread view** — normal conversation UI, compose + send a one-off reply.
6. **Contacts** — searchable list, status filter chips (not_sent / sent / delivered / replied / failed / do_not_contact), per-contact detail with history and manual "Add to do-not-contact".
7. **Needs review** — un-normalizable imports, editable, re-validate to move into the pool.
8. **Import** — pick CSV, show summary.
9. **Settings** — daily cap, default delay, default-SIM, default-handler status + switch buttons, export/backup now, STOP-keyword list, about.
10. **Stats** (can live on Home) — totals: sent, delivered, replied, remaining; simple bar of progress through the whole list.

Empty states, loading states, and errors everywhere. No dead ends.

---

## 11. Backup / export (data-loss defense)

- After each campaign finishes and on a Settings button: export
  - the full SQLite DB file, and
  - a CSV of every contact with current status,
  to a user-visible folder (e.g. `Documents/CampaignSMS/backups/…` via Storage Access Framework or `MediaStore`).
- Import-from-backup path to restore state on a fresh install.

---

## 12. Acceptance criteria (test these)

1. Import the deduplicated CSV → contacts land as `not_sent`, duplicates skipped, un-normalizable rows in Needs review.
2. Batches auto-generate in 100s, named sequentially, none overlapping.
3. Send a batch of 5 to test SIMs → each gets an **individual** SMS (no group thread), statuses move not_sent→sent→delivered on receipts.
4. Kill the app / reboot mid-batch → on relaunch it resumes at the exact next contact, **zero** resends (verify via `message` table: no contact has two `sent` outbound rows for one campaign).
5. Reply from a test number → that contact flips to `replied`, appears in Campaign-replies inbox, and is **excluded** from the next batch.
6. Text "STOP" from a test number → contact flips to `do_not_contact`, excluded permanently.
7. Personal SMS received while default → shows under "Other", not in campaign threads.
8. Daily cap reached → batch marks `partial`, engine stops, remaining stay `not_sent`.
9. Amharic message → segment counter shows 70-char segments and warns; message still sends and reassembles correctly on the recipient.
10. Finish a campaign → app reminds to switch default back and one-tap restores previous default app.
11. Export → DB + CSV appear in the user-visible folder; fresh install can restore.

---

## 13. What NOT to build

- No paid SMS gateway integration — this uses the SIM only.
- No cloud sync, no server, no accounts. Fully local.
- No auto-forwarding of personal OTPs anywhere.
- No attempt to bypass carrier throttling beyond pacing + daily cap.
- No iOS.
- No release/signed APK until the user asks.

---

## 14. Suggested build order for Claude Code

1. Project scaffold, Material 3 theme, navigation, DB schema + migrations.
2. CSV import + normalization + Needs-review.
3. Batch generation + Home/Batches screen.
4. Native Kotlin sender channel (sent/delivered PendingIntents) — test with a couple of real numbers.
5. Foreground-service send engine + journaling + resume + Pause/Stop.
6. Default-handler role components + request/restore UX.
7. Incoming receiver + inbox (two tabs) + thread view + one-off reply.
8. Contacts screen, status filters, do-not-contact, STOP handling.
9. Segment/cost counter, dual-SIM picker, settings.
10. Backup/export + restore.
11. Run the §12 acceptance tests; fix; polish UI to Google/Samsung-Messages level.

Build a debug APK for the user's own device only when a milestone is testable. Do not produce a signed release build without explicit approval.
