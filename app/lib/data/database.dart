import 'package:sqflite/sqflite.dart';

/// Schema owner.
///
/// This is the ONLY place tables are created or migrated. The Kotlin send engine and
/// SMS receivers open the same file read/write but never create anything — see
/// `CampaignDb.kt` for why the native side talks to SQLite directly at all.
///
/// Deliberately no UPSERT (`ON CONFLICT ... DO UPDATE`) anywhere: Android 7, our
/// minSdk, ships SQLite 3.9 which predates it.
const String databaseName = 'campaign_sms.db';
const int _schemaVersion = 13;

/// [factory] and [path] exist so tests can drive this exact code path — including
/// `onCreate` — on a desktop SQLite. Production passes neither.
Future<Database> openCampaignDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final resolvedFactory = factory ?? databaseFactory;
  final resolvedPath =
      path ?? '${await resolvedFactory.getDatabasesPath()}/$databaseName';
  return resolvedFactory.openDatabase(
    resolvedPath,
    options: OpenDatabaseOptions(
      version: _schemaVersion,
      // Every PRAGMA goes through rawQuery, never execute.
      //
      // Android's SQLiteDatabase.execSQL() refuses any statement that returns
      // rows, and `PRAGMA busy_timeout = N` and `PRAGMA journal_mode = WAL` both
      // return their new value as a row. Using execute() here threw on the
      // device — and because this runs inside the open that `main()` awaits
      // before runApp, it left the app on the launcher splash with no UI to
      // report it. Desktop SQLite does not enforce this distinction, so no host
      // test will catch a regression: keep rawQuery.
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA foreign_keys = ON');
        // WAL lets the send service journal a message while the UI reads. Not
        // fatal if a device refuses it; it just serialises them instead.
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
        } catch (_) {}
        await db.rawQuery('PRAGMA busy_timeout = 8000');
      },
      // No batch and no transaction in here. sqflite already has this database
      // inside a transaction when it calls onCreate, and committing a batch opens
      // a nested one that blocks on the lock the outer transaction holds — the
      // open never returns and the app hangs on the splash screen forever.
      onCreate: (db, version) async {
        for (final stmt in _createStatements) {
          await db.execute(stmt);
        }
        await _seedSettings(db);
      },
      onUpgrade: (db, from, to) async {
        // Append only; never rewrite history. Each step has to be safe to run
        // on a database that has been in daily use, which is why nothing here
        // drops or rebuilds a table.
        if (from < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS note (
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              title       TEXT    NOT NULL DEFAULT '',
              body        TEXT    NOT NULL DEFAULT '',
              tint        INTEGER NOT NULL DEFAULT 0,
              pinned      INTEGER NOT NULL DEFAULT 0,
              created_at  INTEGER NOT NULL,
              updated_at  INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_updated ON note(updated_at)',
          );
        }
        if (from < 3) {
          // Indexes only. Adding one to a table in daily use is safe and cheap,
          // and these are what the dashboard and the usage screen read on
          // every refresh.
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_message_outbound '
            'ON message(direction, status, sent_at)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_contact_batch_status '
            'ON contact(batch_id, status)',
          );
        }
        if (from < 4) {
          // Batch order used to be the id order. Seeding position from the id
          // keeps every existing list exactly where the user left it, and from
          // then on the arrows move it.
          await db.execute(
            'ALTER TABLE batch ADD COLUMN position INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('UPDATE batch SET position = id');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_batch_position ON batch(position)',
          );
        }
        if (from < 5) {
          // Mute is its own flag rather than a reading of do_not_contact,
          // because ad-hoc inbound contacts are *created* do_not_contact (to
          // keep them unbatchable) — using status as mute would have silenced
          // every personal sender on day one.
          await db.execute(
            'ALTER TABLE contact ADD COLUMN muted INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (from < 6) {
          // Scheduled sending: a campaign row can now exist before its start
          // time, carrying when it should fire.
          await db.execute(
            'ALTER TABLE campaign ADD COLUMN scheduled_at INTEGER',
          );
        }
        if (from < 7) {
          // Conversations gained the three things every messaging app has:
          // a way to keep one at the top, a way to put one away without
          // destroying it, and a half-written reply that survives leaving.
          await db.execute(
            'ALTER TABLE thread ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE thread ADD COLUMN archived INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute('ALTER TABLE thread ADD COLUMN draft TEXT');
          await db.execute(_createScheduledMessage);
          await db.execute(_indexScheduledMessage);
          // Searching message bodies scans the table; at a few thousand
          // messages that is fine, but ordering the hits is not.
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_message_created ON message(created_at)',
          );
        }
        if (from < 8) {
          // A broker's three missing tools: the sentences they retype every
          // day, notes that belong to a person rather than to nobody, and the
          // appointments that are the actual job.
          await db.execute(_createTemplate);
          await db.execute('ALTER TABLE note ADD COLUMN contact_id INTEGER');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_contact ON note(contact_id)',
          );
          await db.execute(_createAppointment);
          await db.execute(_indexAppointment);
        }
        if (from < 9) {
          // The CRM turn: a person can carry a deal moving through stages,
          // wear tags, and remember when they were last actually talked to —
          // which is what "going cold" is measured from.
          await db.execute(_createDeal);
          await db.execute(_indexDealStage);
          await db.execute(_indexDealContact);
          await db.execute(_createTag);
          await db.execute(_createContactTag);
          await db.execute(_indexContactTagTag);
          await db.execute(
            'ALTER TABLE contact ADD COLUMN last_talked_at INTEGER',
          );
        }
        if (from < 10) {
          // Selling the app: activation codes that have been used here (so a
          // paid code cannot be pasted twice), and the seller's own book of
          // codes issued to buyers.
          await db.execute(_createRedeemedCode);
          await db.execute(_createIssuedLicense);
        }
        if (from < 11) {
          // The car shelf: listings shared in from other apps, each
          // remembering who sent it — the answer to "who sent me this car?"
          // a week after the chat scrolled away.
          await db.execute(_createListing);
        }
        if (from < 12) {
          // Messages that arrived in other messengers, read from their
          // notifications, so nothing is missed for landing in the wrong app.
          await db.execute(_createChatMessage);
          await db.execute(_indexChatAt);
          await db.execute(_createChatLink);
        }
        if (from < 13) {
          // The shelf holds whatever is being brokered — a car today, a house
          // tomorrow — so the table stops being named for one of them. A
          // rename rather than a new table and a copy: the rows, the ids and
          // therefore every #LF code already printed into a channel post
          // survive untouched.
          //
          // Guarded on the table actually being there. A database old enough
          // to predate the shelf runs step 11 above on the way here, which
          // creates it under its new name — so there is nothing to rename, and
          // an unguarded ALTER would fail the whole open. Only a database that
          // has really been carrying `car` gets renamed.
          final hasCar = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'car'",
          );
          if (hasCar.isNotEmpty) {
            await db.execute('ALTER TABLE car RENAME TO listing');
          }
        }
      },
    ),
  );
}

/// One personal message waiting on the clock.
///
/// Deliberately not a one-row campaign: a campaign owns a batch, counts
/// against campaign statistics and drives the foreground send service. A
/// birthday message at midnight is one row, one alarm, one send.
const String _createScheduledMessage = '''
  CREATE TABLE scheduled_message (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id  INTEGER NOT NULL,
    body        TEXT    NOT NULL,
    send_at     INTEGER NOT NULL,
    created_at  INTEGER NOT NULL
  )
''';

const String _indexScheduledMessage =
    'CREATE INDEX IF NOT EXISTS idx_scheduled_message_at '
    'ON scheduled_message(send_at)';

/// A sentence typed often enough to be worth keeping. Ordered by hand rather
/// than by use: the one you reach for most is not always the one you used last.
const String _createTemplate = '''
  CREATE TABLE template (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    label       TEXT    NOT NULL DEFAULT '',
    body        TEXT    NOT NULL,
    position    INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
  )
''';

/// A viewing, a meeting, a call-back.
///
/// `at` is when the thing happens and `remind_at` is when to say so — usually
/// earlier, because a reminder that arrives as the viewing starts is a
/// reminder that arrives too late. Both are stored: the alarm can be moved
/// without losing when the appointment actually is.
const String _createAppointment = '''
  CREATE TABLE appointment (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id  INTEGER,
    title       TEXT    NOT NULL,
    place       TEXT,
    at          INTEGER NOT NULL,
    remind_at   INTEGER NOT NULL,
    done        INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
  )
''';

const String _indexAppointment =
    'CREATE INDEX IF NOT EXISTS idx_appointment_at ON appointment(at)';

/// One thing being sold to (or bought for) one person, moving through stages:
/// new → contacted → viewing → negotiating → won / lost.
///
/// `title` is the thing itself — "Bole apartment, 3BR", "2018 Corolla".
/// `stage_changed_at` is what "stuck in negotiating for three weeks" is
/// measured from; `closed_at` is only set by won/lost, so reopened deals lose
/// it again. `price` is optional and in birr — a broker quotes it or doesn't.
const String _createDeal = '''
  CREATE TABLE deal (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id        INTEGER NOT NULL,
    title             TEXT    NOT NULL DEFAULT '',
    stage             TEXT    NOT NULL DEFAULT 'new',
    price             INTEGER,
    stage_changed_at  INTEGER NOT NULL,
    closed_at         INTEGER,
    created_at        INTEGER NOT NULL,
    updated_at        INTEGER NOT NULL
  )
''';

const String _indexDealStage =
    'CREATE INDEX IF NOT EXISTS idx_deal_stage ON deal(stage)';
const String _indexDealContact =
    'CREATE INDEX IF NOT EXISTS idx_deal_contact ON deal(contact_id)';

/// Labels a person wears: "buyer", "car", "hot". NOCASE so "Buyer" and
/// "buyer" cannot both exist and quietly split one audience in two.
const String _createTag = '''
  CREATE TABLE tag (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL COLLATE NOCASE UNIQUE,
    created_at  INTEGER NOT NULL
  )
''';

const String _createContactTag = '''
  CREATE TABLE contact_tag (
    contact_id  INTEGER NOT NULL,
    tag_id      INTEGER NOT NULL,
    PRIMARY KEY (contact_id, tag_id)
  )
''';

/// The primary key already serves lookups by contact; this serves the other
/// direction — "everyone tagged car-buyer" for a campaign audience.
const String _indexContactTagTag =
    'CREATE INDEX IF NOT EXISTS idx_contact_tag_tag ON contact_tag(tag_id)';

/// Activation codes already spent on this phone. The nonce is enough: a code
/// only verifies on this installation, so replay is the one abuse left.
const String _createRedeemedCode = '''
  CREATE TABLE redeemed_code (
    nonce        TEXT PRIMARY KEY,
    days         INTEGER NOT NULL,
    redeemed_at  INTEGER NOT NULL
  )
''';

/// The seller's book: who was issued what, so renewals are foreseeable. Only
/// ever written on the phone that opens the seller screen.
const String _createIssuedLicense = '''
  CREATE TABLE issued_license (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    install_code  TEXT    NOT NULL,
    days          INTEGER NOT NULL,
    note          TEXT,
    issued_at     INTEGER NOT NULL
  )
''';

/// One car (or anything else) shared into the app, with its provenance.
///
/// The row id doubles as the public code (#LF047) printed into the channel
/// post caption, which is what makes a buyer's "the one you posted" a
/// two-second lookup instead of a memory test. `source_contact_id` is who
/// sent it when they are a contact; `source_text` holds a Telegram handle or
/// plain words when they are not. `photos` is a JSON list of file paths in
/// the app's own storage — copied in at share time, because content URIs
/// from other apps expire.
const String _createListing = '''
  CREATE TABLE listing (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    title              TEXT    NOT NULL DEFAULT '',
    body               TEXT    NOT NULL DEFAULT '',
    source_contact_id  INTEGER,
    source_text        TEXT,
    photos             TEXT    NOT NULL DEFAULT '[]',
    sold               INTEGER NOT NULL DEFAULT 0,
    created_at         INTEGER NOT NULL,
    sold_at            INTEGER
  )
''';

/// One message seen arriving in another messenger.
///
/// Written by the native notification listener, never by anything else, and
/// only for the apps the user has ticked. `room` is the group's name when the
/// message came from one; `contact_id` is filled when the sender could be
/// matched to somebody the app already knows.
const String _createChatMessage = '''
  CREATE TABLE chat_message (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    app         TEXT    NOT NULL,
    sender      TEXT    NOT NULL,
    room        TEXT,
    body        TEXT    NOT NULL,
    at          INTEGER NOT NULL,
    contact_id  INTEGER,
    seen        INTEGER NOT NULL DEFAULT 0
  )
''';

const String _indexChatAt =
    'CREATE INDEX IF NOT EXISTS idx_chat_at ON chat_message(at)';

/// "This WhatsApp name is that person" — taught once by hand, then applied to
/// every message that follows. A notification carries no phone number, so
/// this is the only way the link can ever be certain.
const String _createChatLink = '''
  CREATE TABLE chat_link (
    app         TEXT    NOT NULL,
    sender      TEXT    NOT NULL,
    contact_id  INTEGER NOT NULL,
    PRIMARY KEY (app, sender)
  )
''';

const List<String> _createStatements = [
  '''
  CREATE TABLE contact (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    phone_e164    TEXT    NOT NULL UNIQUE,
    phone_local   TEXT,
    name          TEXT,
    source        TEXT,
    status        TEXT    NOT NULL DEFAULT 'not_sent',
    batch_id      INTEGER,
    last_sent_at  INTEGER,
    last_error    TEXT,
    attempts      INTEGER NOT NULL DEFAULT 0,
    is_campaign   INTEGER NOT NULL DEFAULT 1,
    muted         INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL DEFAULT 0,
    last_talked_at INTEGER
  )
  ''',
  'CREATE INDEX idx_contact_status ON contact(status)',
  'CREATE INDEX idx_contact_batch ON contact(batch_id)',
  // The batch list groups every contact by batch and counts by status; the
  // pair together is what that aggregate actually walks.
  'CREATE INDEX idx_contact_batch_status ON contact(batch_id, status)',
  'CREATE INDEX idx_contact_campaign ON contact(is_campaign)',
  '''
  CREATE TABLE batch (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT    NOT NULL,
    size          INTEGER NOT NULL,
    status        TEXT    NOT NULL DEFAULT 'pending',
    position      INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL,
    completed_at  INTEGER
  )
  ''',
  // The order batches are offered in is the user's to set, so it is stored
  // rather than inferred from the id.
  'CREATE INDEX idx_batch_position ON batch(position)',
  '''
  CREATE TABLE campaign (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id            INTEGER NOT NULL,
    message_template    TEXT    NOT NULL,
    sim_subscription_id INTEGER,
    delay_seconds       INTEGER NOT NULL DEFAULT 5,
    status              TEXT    NOT NULL DEFAULT 'in_progress',
    started_at          INTEGER NOT NULL,
    finished_at         INTEGER,
    sent_count          INTEGER NOT NULL DEFAULT 0,
    delivered_count     INTEGER NOT NULL DEFAULT 0,
    failed_count        INTEGER NOT NULL DEFAULT 0,
    scheduled_at        INTEGER
  )
  ''',
  'CREATE INDEX idx_campaign_status ON campaign(status)',
  '''
  CREATE TABLE message (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id    INTEGER NOT NULL,
    campaign_id   INTEGER,
    direction     TEXT    NOT NULL,
    body          TEXT    NOT NULL,
    segments      INTEGER NOT NULL DEFAULT 1,
    status        TEXT    NOT NULL DEFAULT 'pending',
    error         TEXT,
    created_at    INTEGER NOT NULL,
    sent_at       INTEGER,
    delivered_at  INTEGER,
    parts_total   INTEGER NOT NULL DEFAULT 1,
    parts_ok      INTEGER NOT NULL DEFAULT 0,
    parts_failed  INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX idx_message_contact ON message(contact_id)',
  'CREATE INDEX idx_message_campaign ON message(campaign_id)',
  'CREATE INDEX idx_message_sent_at ON message(sent_at)',
  // Every "what went out and when" query filters on these three together —
  // today's count, the segment count, the usage screen. Without the composite
  // each one scans the whole message table.
  'CREATE INDEX idx_message_outbound ON message(direction, status, sent_at)',
  '''
  CREATE TABLE thread (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id       INTEGER NOT NULL UNIQUE,
    kind             TEXT    NOT NULL DEFAULT 'campaign',
    last_message_at  INTEGER NOT NULL,
    unread_count     INTEGER NOT NULL DEFAULT 0,
    snippet          TEXT,
    pinned           INTEGER NOT NULL DEFAULT 0,
    archived         INTEGER NOT NULL DEFAULT 0,
    draft            TEXT
  )
  ''',
  'CREATE INDEX idx_thread_kind ON thread(kind)',
  _createScheduledMessage,
  _indexScheduledMessage,
  _createTemplate,
  _createAppointment,
  _indexAppointment,
  'CREATE INDEX idx_message_created ON message(created_at)',
  '''
  CREATE TABLE needs_review (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_name    TEXT,
    raw_phone   TEXT,
    raw_source  TEXT,
    reason      TEXT NOT NULL,
    created_at  INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE note (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT    NOT NULL DEFAULT '',
    body        TEXT    NOT NULL DEFAULT '',
    tint        INTEGER NOT NULL DEFAULT 0,
    pinned      INTEGER NOT NULL DEFAULT 0,
    contact_id  INTEGER,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  )
  ''',
  'CREATE INDEX idx_note_updated ON note(updated_at)',
  'CREATE INDEX idx_note_contact ON note(contact_id)',
  _createDeal,
  _indexDealStage,
  _indexDealContact,
  _createTag,
  _createContactTag,
  _indexContactTagTag,
  _createRedeemedCode,
  _createIssuedLicense,
  _createListing,
  _createChatMessage,
  _indexChatAt,
  _createChatLink,
  '''
  CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
];

/// Keys shared with `Const.kt`.
class SettingKeys {
  static const dailyCap = 'daily_cap';
  static const delaySeconds = 'default_delay_seconds';
  static const simSubscriptionId = 'current_sim_subscription_id';
  static const campaignActive = 'campaign_active';
  static const engineState = 'engine_state';
  static const previousSmsApp = 'previous_sms_app';
  static const stopKeywords = 'stop_keywords';
  static const maxAttempts = 'max_attempts';
  static const nameFallback = 'name_fallback';
  static const batchSize = 'batch_size';
  static const lastDefaultHandlerPromptAt = 'last_default_handler_prompt_at';

  /// Whether the daily cap counts SMS segments or whole messages.
  static const capCountsSegments = 'cap_counts_segments';
  static const quietEnabled = 'quiet_hours_enabled';
  static const quietStart = 'quiet_start_hour';
  static const quietEnd = 'quiet_end_hour';

  /// The last message that was actually sent, offered back on the next batch.
  static const lastTemplate = 'last_template';

  /// How many SMS the user's package holds. Zero means they have not said.
  static const bundleSize = 'bundle_size';

  /// The user closed the "show calls here" offer; never show it again.
  static const callLogPromptDismissed = 'call_log_prompt_dismissed';

  /// The notes card over an incoming call. On by default; it still needs the
  /// overlay permission before anything appears.
  static const callOverlayEnabled = 'call_overlay_enabled';

  // ----- selling the app (see lib/data/license.dart) -----

  /// This installation's identity, minted on first licence check.
  static const installCode = 'install_code';

  /// When this install first ran — the trial clock's zero.
  static const firstRunAt = 'first_run_at';

  /// When the paid subscription runs out. Zero/absent = never activated.
  static const licenseExpiresAt = 'license_expires_at';

  /// The latest moment this app has ever seen, so winding the phone's clock
  /// back does not resurrect an expired subscription.
  static const licenseLastSeen = 'license_last_seen';

  // ----- the user's own profile -----
  static const profileName = 'profile_name';
  static const profileBusiness = 'profile_business';
  static const profilePhone = 'profile_phone';

  /// The first-run welcome has been shown and answered (or skipped).
  static const welcomed = 'welcomed';

  /// Comma-separated packages the chat feed may read. Empty means the
  /// listener stores nothing, whatever Android has granted.
  static const chatApps = 'chat_apps';

  // ----- the lock over the app (see lib/data/applock.dart) -----

  /// Salted hash of the PIN. Absent or empty means no lock is set, which is
  /// how the app ships.
  static const lockHash = 'lock_hash';
  static const lockSalt = 'lock_salt';

  /// How many digits the code has. The keypad needs it to know when a guess is
  /// finished; the dots show it regardless.
  static const lockLength = 'lock_length';

  /// Wrong guesses in a row, and when the current cooldown ends. Stored rather
  /// than held in memory so force-quitting the app does not clear the wait.
  static const lockWrongCount = 'lock_wrong_count';
  static const lockCooldownUntil = 'lock_cooldown_until';

  /// When a backup was last written or shared. Zero means never, which is what
  /// the dashboard's reminder is really watching for.
  static const lastBackupAt = 'last_backup_at';
}

const String defaultStopKeywords =
    'STOP,STOPP,UNSUBSCRIBE,QUIT,CANCEL,END,አቁም,አቁሙ,ተው,ተዉ,በቃ,አታድርጉ,አታክሉኝ';

Future<void> _seedSettings(Database db) async {
  const defaults = <String, String>{
    SettingKeys.dailyCap: '100',
    SettingKeys.delaySeconds: '5',
    SettingKeys.batchSize: '100',
    SettingKeys.maxAttempts: '2',
    SettingKeys.campaignActive: '0',
    SettingKeys.engineState: 'idle',
    SettingKeys.stopKeywords: defaultStopKeywords,
    SettingKeys.nameFallback: 'there',
    SettingKeys.capCountsSegments: '1',
    SettingKeys.quietEnabled: '1',
    SettingKeys.quietStart: '21',
    SettingKeys.quietEnd: '8',
    SettingKeys.lastTemplate: '',
    SettingKeys.bundleSize: '0',
    SettingKeys.callOverlayEnabled: '1',
  };
  // Plain inserts for the same reason as onCreate: this runs inside sqflite's
  // own transaction, so anything that opens another one deadlocks.
  for (final entry in defaults.entries) {
    await db.insert('settings', {
      'key': entry.key,
      'value': entry.value,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
