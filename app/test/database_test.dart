import 'dart:io';

import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/license.dart';
import 'package:campaign_sms/data/models.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Startup regression guard.
///
/// The first shipped build hung forever on the splash screen because `onCreate`
/// committed a batch, which opens a transaction nested inside the one sqflite
/// already holds while creating the schema. `openDatabase` never completed, so
/// `runApp` was never reached and the app showed nothing but the launcher icon.
///
/// These tests drive the real `openCampaignDatabase` on a desktop SQLite. A
/// deadlock here fails the suite by timeout instead of reaching a phone.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> open() => openCampaignDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
  );

  test(
    'opens and creates the schema without deadlocking',
    () async {
      final db = await open();
      addTearDown(db.close);

      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name'] as String).toSet();

      expect(
        tables,
        containsAll(<String>[
          'contact',
          'batch',
          'campaign',
          'message',
          'thread',
          'needs_review',
          'settings',
        ]),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('seeds the default settings', () async {
    final db = await open();
    addTearDown(db.close);
    final repo = Repo(db);

    expect(await repo.getSettingInt(SettingKeys.dailyCap, -1), 100);
    expect(await repo.getSettingInt(SettingKeys.delaySeconds, -1), 5);
    expect(await repo.getSettingInt(SettingKeys.batchSize, -1), 100);
    expect(await repo.getSetting(SettingKeys.engineState, ''), 'idle');
    expect(await repo.getSetting(SettingKeys.nameFallback, ''), 'there');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'import, batching and status rules work end to end',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '2');

      for (final phone in ['0911111111', '0922222222', '0933333333']) {
        await repo.upsertContact(
          e164: '+251${phone.substring(1)}',
          source: 'Gari',
        );
      }
      // A duplicate must not create a second row.
      await repo.upsertContact(e164: '+251911111111', name: 'Abebe');

      final created = await repo.generateBatches();
      expect(created, 2, reason: '3 contacts at 2 per batch');

      final batches = await repo.batches();
      expect(batches.map((b) => b.total), [2, 1]);

      // Re-running must not move anyone or invent batches.
      expect(await repo.generateBatches(), 0);

      final stats = await repo.stats();
      expect(stats.totalContacts, 3);
      expect(stats.notSent, 3);

      // A replied contact is terminal and drops out of the pool.
      final contact = await repo.contactByPhone('+251911111111');
      expect(contact!.name, 'Abebe', reason: 'name filled in on re-import');
      await repo.setContactStatus(contact.id, ContactStatus.replied);
      await repo.setContactStatus(contact.id, ContactStatus.notSent);
      final after = await repo.contactById(contact.id);
      expect(
        after!.status,
        ContactStatus.replied,
        reason: 'nothing may drag a contact out of a terminal status',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the daily cap can count SMS segments rather than messages',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      final contact = await repo.contactByPhone('+251911111111');
      final now = DateTime.now().millisecondsSinceEpoch;

      // One message, three segments — an Amharic template over two lines.
      await db.insert('message', {
        'contact_id': contact!.id,
        'direction': 'outbound',
        'body': 'ሰላም',
        'segments': 3,
        'status': 'sent',
        'created_at': now,
        'sent_at': now,
        'parts_total': 3,
        'parts_ok': 3,
        'parts_failed': 0,
      });

      expect(await repo.sentToday(), 1);
      expect(
        await repo.segmentsSentToday(),
        3,
        reason: 'the operator charged three, not one',
      );

      final counted = await repo.stats();
      expect(counted.capCountsSegments, isTrue, reason: 'segments by default');
      expect(counted.usedToday, 3);
      expect(counted.capUnit, 'SMS');

      await repo.setSetting(SettingKeys.capCountsSegments, '0');
      final byMessage = await repo.stats();
      expect(byMessage.usedToday, 1);
      expect(byMessage.capUnit, 'messages');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a send whose receipt never arrives stops stranding its contact',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      final contact = await repo.contactByPhone('+251911111111');
      await repo.setContactStatus(contact!.id, ContactStatus.queued);

      final old = DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      await db.insert('message', {
        'contact_id': contact.id,
        'direction': 'outbound',
        'body': 'hello',
        'segments': 1,
        'status': 'pending',
        'created_at': old,
        'parts_total': 1,
        'parts_ok': 0,
        'parts_failed': 0,
      });

      expect(await repo.sweepStalePending(), 1);

      final after = await repo.contactById(contact.id);
      expect(
        after!.status,
        ContactStatus.failed,
        reason: 'failed is retryable and visible; queued is neither',
      );

      // An in-flight send must survive the sweep untouched.
      await repo.setContactStatus(after.id, ContactStatus.queued);
      await db.insert('message', {
        'contact_id': contact.id,
        'direction': 'outbound',
        'body': 'hello again',
        'segments': 1,
        'status': 'pending',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'parts_total': 1,
        'parts_ok': 0,
        'parts_failed': 0,
      });
      expect(await repo.sweepStalePending(), 0);
      expect(
        (await repo.contactById(contact.id))!.status,
        ContactStatus.queued,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a version 1 database upgrades in place without losing anything',
    () async {
      // The note table arrived in version 2. Existing installs are full of real
      // contacts and real send history, so the upgrade has to add a table and
      // touch nothing else — and it runs during the open that `main()` awaits, so
      // a failure here is a phone that will not start rather than a missing
      // feature.
      final dir = await Directory.systemTemp.createTemp('campaign_sms_v1');
      final path = '${dir.path}/campaign_sms.db';
      addTearDown(() => dir.delete(recursive: true));

      final v1 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE contact ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'phone_e164 TEXT NOT NULL UNIQUE, phone_local TEXT, name TEXT, '
              'source TEXT, status TEXT NOT NULL DEFAULT \'not_sent\', '
              'batch_id INTEGER, last_sent_at INTEGER, last_error TEXT, '
              'attempts INTEGER NOT NULL DEFAULT 0, '
              'is_campaign INTEGER NOT NULL DEFAULT 1, '
              'created_at INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
            // A real version 1 database has every table version 1 shipped.
            // Leaving one out made the fixture easier to write and the
            // migration harder to trust: version 3 adds an index on `message`,
            // which only means anything against a database that has one.
            await db.execute(
              'CREATE TABLE batch ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
              'size INTEGER NOT NULL, '
              "status TEXT NOT NULL DEFAULT 'pending', "
              'created_at INTEGER NOT NULL, completed_at INTEGER)',
            );
            await db.execute(
              'CREATE TABLE message ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'contact_id INTEGER NOT NULL, campaign_id INTEGER, '
              'direction TEXT NOT NULL, body TEXT NOT NULL, '
              'segments INTEGER NOT NULL DEFAULT 1, '
              "status TEXT NOT NULL DEFAULT 'pending', error TEXT, "
              'created_at INTEGER NOT NULL, sent_at INTEGER, '
              'delivered_at INTEGER, parts_total INTEGER NOT NULL DEFAULT 1, '
              'parts_ok INTEGER NOT NULL DEFAULT 0, '
              'parts_failed INTEGER NOT NULL DEFAULT 0)',
            );
            // Version 7 alters `thread`; version 1 had one.
            await db.execute(
              'CREATE TABLE thread ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'contact_id INTEGER NOT NULL UNIQUE, '
              "kind TEXT NOT NULL DEFAULT 'campaign', "
              'last_message_at INTEGER NOT NULL, '
              'unread_count INTEGER NOT NULL DEFAULT 0, '
              'snippet TEXT)',
            );
            // Version 6 alters `campaign`, which version 1 shipped too — the
            // fixture found that out the hard way when the ALTER hit a table
            // that was not there.
            await db.execute(
              'CREATE TABLE campaign ('
              'id INTEGER PRIMARY KEY AUTOINCREMENT, '
              'batch_id INTEGER NOT NULL, message_template TEXT NOT NULL, '
              'sim_subscription_id INTEGER, '
              'delay_seconds INTEGER NOT NULL DEFAULT 5, '
              "status TEXT NOT NULL DEFAULT 'in_progress', "
              'started_at INTEGER NOT NULL, finished_at INTEGER, '
              'sent_count INTEGER NOT NULL DEFAULT 0, '
              'delivered_count INTEGER NOT NULL DEFAULT 0, '
              'failed_count INTEGER NOT NULL DEFAULT 0)',
            );
          },
        ),
      );
      await v1.insert('contact', {
        'phone_e164': '+251911111111',
        'name': 'Abebe',
        'status': 'sent',
      });
      await v1.insert('settings', {'key': 'daily_cap', 'value': '250'});
      await v1.insert('batch', {'name': 'Batch 1', 'size': 2, 'created_at': 1});
      await v1.insert('batch', {'name': 'Batch 2', 'size': 2, 'created_at': 2});
      await v1.close();

      final upgraded = await openCampaignDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(upgraded.close);
      final repo = Repo(upgraded);

      expect(await upgraded.getVersion(), 13);
      expect(
        (await repo.contactByPhone('+251911111111'))?.name,
        'Abebe',
        reason: 'the upgrade must not disturb what is already there',
      );
      expect(
        await repo.getSetting('daily_cap', ''),
        '250',
        reason:
            'a setting the user changed survives, rather than being re-seeded',
      );

      // The indexes the later versions add are there too.
      final indexes = (await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      )).map((r) => r['name']).toSet();
      expect(indexes, contains('idx_message_outbound'));
      expect(indexes, contains('idx_contact_batch_status'));
      expect(indexes, contains('idx_batch_position'));

      // Batches that predate the column keep the order they were listed in.
      expect(
        (await repo.batches()).map((b) => b.name).toList(),
        ['Batch 1', 'Batch 2'],
        reason: 'the position backfill must not shuffle an existing list',
      );

      // v5: the muted flag exists and defaults to off.
      final abebe = await repo.contactByPhone('+251911111111');
      expect(abebe!.muted, isFalse);
      await repo.setMuted(abebe.id, true);
      expect((await repo.contactByPhone('+251911111111'))!.muted, isTrue);

      // And the new table works.
      final id = await repo.saveNote(
        title: 'Call back',
        body: '- Dawit\nx Sara',
      );
      final notes = await repo.notes();
      expect(notes.single.id, id);
      expect(notes.single.title, 'Call back');

      // v7: conversations gained pin, archive and drafts, and personal
      // messages gained a schedule of their own.
      await repo.journalOutbound(contactId: abebe.id, body: 'hello');
      await repo.setPinned(abebe.id, true);
      await repo.saveDraft(abebe.id, 'later');
      final thread = (await repo.threads('campaign')).single;
      expect(thread.pinned, isTrue);
      expect(thread.draft, 'later');
      expect(thread.archived, isFalse);
      final laterId = await repo.scheduleMessage(
        contactId: abebe.id,
        body: 'tomorrow',
        sendAt: DateTime.now().millisecondsSinceEpoch + 60000,
      );
      expect((await repo.scheduledMessagesFor(abebe.id)).single.id, laterId);

      // v8: templates, notes about a person, and the diary.
      await repo.saveTemplate(body: 'Still available?');
      expect((await repo.templates()).single.body, 'Still available?');
      final about = await repo.saveNote(
        title: 'Wants',
        body: '3 bedroom',
        contactId: abebe.id,
      );
      expect((await repo.notesForContact(abebe.id)).single.id, about);
      final booking = await repo.saveAppointment(
        contactId: abebe.id,
        title: 'Viewing',
        at: DateTime.now().millisecondsSinceEpoch + 3600000,
        remindAt: DateTime.now().millisecondsSinceEpoch + 1800000,
      );
      expect((await repo.appointments()).single.id, booking);

      // v6: a campaign can wait on the clock.
      final batches = await repo.batches();
      final scheduledId = await repo.scheduleCampaign(
        batchId: batches.first.id,
        template: 'Selam {name}',
        simSubscriptionId: null,
        delaySeconds: 5,
        at: DateTime.now().millisecondsSinceEpoch + 60000,
      );
      final scheduled = await repo.scheduledCampaign();
      expect(scheduled?.campaignId, scheduledId);
      await repo.cancelScheduled(scheduledId);
      expect(await repo.scheduledCampaign(), isNull);

      // v9: deals, tags and the last-talked stamp all work on the upgraded
      // database.
      final dealId = await repo.saveDeal(contactId: abebe.id, title: 'Corolla');
      expect((await repo.dealForContact(abebe.id))?.id, dealId);
      final tagId = await repo.ensureTag('buyer');
      await repo.setContactTag(abebe.id, tagId!, true);
      expect((await repo.tagsForContact(abebe.id)).single.name, 'buyer');
      await repo.touchContact(abebe.id);

      // v10: the licence tables answer, and a code round-trips.
      final status = await repo.licenseStatus();
      expect(status.phase, LicensePhase.trial);
      final code = License.issue(installCode: status.installCode, days: 30);
      expect(await repo.redeemCode(code), isNull);
      expect((await repo.licenseStatus()).phase, LicensePhase.active);

      // v11: the shelf files and finds.
      final listingId = await repo.saveListing(
        title: 'White Corolla 2018',
        sourceContactId: abebe.id,
      );
      expect((await repo.listings()).single.id, listingId);

      // v12: the chat feed's tables answer.
      expect(await repo.chatMessages(), isEmpty);
      expect(await repo.unseenChatCount(), 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a checklist line cycles plain → open → done → plain', () {
    // What the editor's one checklist button does to the line the cursor is
    // on. Round-tripping through NoteLine is the whole mechanism, so the
    // syntax never has to be explained to anybody.
    String next(String line) {
      final parsed = NoteLine.parse(line);
      if (!parsed.checkable) return '- $line';
      return parsed.done ? parsed.text : 'x ${parsed.text}';
    }

    expect(next('buy cement'), '- buy cement');
    expect(next('- buy cement'), 'x buy cement');
    expect(next('x buy cement'), 'buy cement');
    expect(next(''), '- ');
  });

  test('note bodies carry their own checklist', () {
    expect(NoteLine.parse('- ring Dawit').checkable, isTrue);
    expect(NoteLine.parse('- ring Dawit').done, isFalse);
    expect(NoteLine.parse('x ring Dawit').done, isTrue);
    expect(NoteLine.parse('X ring Dawit').done, isTrue);
    expect(NoteLine.parse('just prose').checkable, isFalse);

    // Toggling round-trips through the text, which is where it is stored.
    expect(NoteLine.parse('- a').toggled().render(), 'x a');
    expect(NoteLine.parse('x a').toggled().render(), '- a');
    expect(NoteLine.parse('prose').toggled().render(), 'prose');
  });

  test(
    'the trend buckets sends by day and always covers the window',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      final contact = await repo.contactByPhone('+251911111111');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      Future<void> sentOn(DateTime day, int count) async {
        for (var i = 0; i < count; i++) {
          // Midday, so a timezone offset cannot tip one into the day either side.
          final at = day.add(const Duration(hours: 12)).millisecondsSinceEpoch;
          await db.insert('message', {
            'contact_id': contact!.id,
            'direction': 'outbound',
            'body': 'hello',
            'segments': 1,
            'status': 'sent',
            'created_at': at,
            'sent_at': at,
            'parts_total': 1,
            'parts_ok': 1,
            'parts_failed': 0,
          });
        }
      }

      await sentOn(today, 3);
      await sentOn(today.subtract(const Duration(days: 1)), 5);
      await sentOn(today.subtract(const Duration(days: 6)), 2);
      // Outside the window entirely.
      await sentOn(today.subtract(const Duration(days: 20)), 99);

      final trend = await repo.trend();
      expect(trend.days.length, 7, reason: 'a quiet day is a zero, not a gap');
      expect(trend.today, 3);
      expect(trend.yesterday, 5);
      expect(trend.days.first.messages, 2);
      expect(trend.total, 10, reason: 'the older run is out of range');
      expect(trend.peak, 5);
      expect(trend.change, closeTo(-40, 0.001));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  group('describeBackup', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('backup_test');
    });
    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('reads back a real database', () async {
      final path = '${dir.path}/campaign_sms.db';
      final db = await openCampaignDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      final repo = Repo(db);
      await repo.upsertContact(e164: '+251911000001', source: 'test');
      await repo.upsertContact(e164: '+251911000002', source: 'test');
      await repo.checkpoint();
      await db.close();

      expect(
        await Repo.describeBackup(path, factory: databaseFactoryFfi),
        'ok:2:0',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test(
      'refuses a file that is not a backup',
      () async {
        final path = '${dir.path}/holiday.jpg';
        await File(path).writeAsBytes(List.filled(64, 7));

        final result = await Repo.describeBackup(
          path,
          factory: databaseFactoryFfi,
        );
        expect(result, isNotNull);
        expect(result!.startsWith('ok:'), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'refuses a database that is not ours',
      () async {
        final path = '${dir.path}/other.db';
        final db = await databaseFactoryFfi.openDatabase(path);
        await db.execute('CREATE TABLE recipes (id INTEGER PRIMARY KEY)');
        await db.close();

        final result = await Repo.describeBackup(
          path,
          factory: databaseFactoryFfi,
        );
        expect(result, 'That file is not a LeadForce backup.');
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  test(
    'a batch can be moved up and down the sending order',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '1');

      for (final phone in ['+251911111111', '+251922222222', '+251933333333']) {
        await repo.upsertContact(e164: phone, source: 'Gari');
      }
      await repo.generateBatches();
      expect((await repo.batches()).map((b) => b.name), [
        'Batch 1',
        'Batch 2',
        'Batch 3',
      ]);

      // Third to second.
      final third = (await repo.batches())[2];
      expect(await repo.moveBatch(third.id, -1), isTrue);
      expect((await repo.batches()).map((b) => b.name), [
        'Batch 1',
        'Batch 3',
        'Batch 2',
      ]);

      // And on to the front, where it becomes the one that gets sent next.
      expect(await repo.moveBatch(third.id, -1), isTrue);
      expect((await repo.batches()).map((b) => b.name), [
        'Batch 3',
        'Batch 1',
        'Batch 2',
      ]);
      expect((await repo.nextPendingBatch())!.name, 'Batch 3');

      // The ends are ends.
      expect(await repo.moveBatch(third.id, -1), isFalse);
      final last = (await repo.batches()).last;
      expect(await repo.moveBatch(last.id, 1), isFalse);
      expect((await repo.batches()).map((b) => b.name), [
        'Batch 3',
        'Batch 1',
        'Batch 2',
      ]);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a contact added by hand joins the first batch with room in it',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '2');

      for (final phone in ['+251911111111', '+251922222222']) {
        await repo.upsertContact(e164: phone, source: 'Gari');
      }
      await repo.generateBatches();
      expect((await repo.batches()).single.total, 2, reason: 'full at two');

      // Nowhere to put them, so a batch is made.
      final walkIn = await repo.addContact(
        rawPhone: '0944444444',
        name: 'Hana',
      );
      expect(walkIn.ok, isTrue);
      expect(walkIn.batchName, 'Batch 2');
      expect(walkIn.message, 'Added to Batch 2.');

      final saved = await repo.contactByPhone('+251944444444');
      expect(saved!.name, 'Hana');
      expect(
        saved.phoneLocal,
        '0944444444',
        reason: '09… form is what gets shown',
      );
      expect(saved.status, ContactStatus.notSent);

      // The second one has somewhere to go: Batch 2 has one free place.
      final second = await repo.addContact(rawPhone: '+251955555555');
      expect(second.ok, isTrue);
      expect(second.batchName, 'Batch 2');
      expect((await repo.batches()).last.total, 2);

      // Same number, typed any of the three ways, is the same person.
      final again = await repo.addContact(
        rawPhone: '251944444444',
        name: 'Hana B',
      );
      expect(again.ok, isFalse);
      expect(again.outcome, ManualAddOutcome.duplicate);
      expect(again.message, contains('0944444444'));

      final bad = await repo.addContact(rawPhone: '0812345678');
      expect(bad.ok, isFalse);
      expect(bad.outcome, ManualAddOutcome.rejected);
      expect(bad.message, isNotEmpty);

      expect((await repo.stats()).totalContacts, 4, reason: 'no duplicate row');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'deleting a conversation keeps the contact and their status',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '10');

      await repo.addContact(rawPhone: '0911111111', name: 'Abebe');
      final contact = await repo.contactByPhone('+251911111111');
      await repo.setContactStatus(contact!.id, ContactStatus.replied);
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('message', {
        'contact_id': contact.id,
        'direction': 'inbound',
        'body': 'selam',
        'segments': 1,
        'status': 'delivered',
        'created_at': now,
      });
      await db.insert('thread', {
        'contact_id': contact.id,
        'kind': 'campaign',
        'last_message_at': now,
        'unread_count': 1,
      });

      await repo.deleteThread(contact.id);

      expect(await repo.messagesFor(contact.id), isEmpty);
      expect(await repo.threads('campaign'), isEmpty);
      final after = await repo.contactById(contact.id);
      expect(
        after!.status,
        ContactStatus.replied,
        reason:
            'clearing a chat must not put someone who answered back in the pool',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'removing a contact takes their messages and conversation with them',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '2');

      await repo.addContact(rawPhone: '0911111111', name: 'Abebe');
      await repo.addContact(rawPhone: '0922222222');
      final contact = await repo.contactByPhone('+251911111111');
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('message', {
        'contact_id': contact!.id,
        'direction': 'outbound',
        'body': 'hello',
        'segments': 1,
        'status': 'sent',
        'created_at': now,
        'sent_at': now,
      });
      await db.insert('thread', {
        'contact_id': contact.id,
        'kind': 'campaign',
        'last_message_at': now,
      });

      final before = (await repo.batches()).single;
      expect(before.total, 2);

      await repo.deleteContact(contact.id);

      expect(await repo.contactByPhone('+251911111111'), isNull);
      expect(await repo.messagesFor(contact.id), isEmpty);
      expect(
        (await db.query(
          'thread',
          where: 'contact_id = ?',
          whereArgs: [contact.id],
        )),
        isEmpty,
        reason: 'a deleted number must not linger in the inbox',
      );

      final after = (await repo.batches()).single;
      expect(after.total, 1);
      expect(after.size, 1, reason: 'the batch no longer claims to hold two');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'composing to a raw number reuses or creates a non-campaign contact',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      // A campaign contact is found, not duplicated.
      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      final existing = await repo.contactByPhone('+251911111111');
      expect(await repo.contactForCompose('0911 111 111'), existing!.id);

      // A short code becomes an ad-hoc row that can never be batched.
      final short = await repo.contactForCompose('127');
      final row = await repo.contactById(short!);
      expect(row!.isCampaign, isFalse);
      expect(row.status, ContactStatus.doNotContact);
      expect(await repo.contactForCompose('127'), short, reason: 'stable row');

      // Nothing to dial is refused, not inserted.
      expect(await repo.contactForCompose('   '), isNull);

      // A reply typed to the short code files the thread under Messages.
      await repo.journalOutbound(contactId: short, body: 'hello');
      final threads = await repo.threads('other');
      expect(threads.single.contactId, short);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'batches can be renamed and created by hand',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final id = await repo.createBatch('Walk-ins');
      var batches = await repo.batches();
      expect(batches.single.name, 'Walk-ins');
      expect(batches.single.total, 0, reason: 'born empty');

      await repo.renameBatch(id, '  Saturday market  ');
      batches = await repo.batches();
      expect(batches.single.name, 'Saturday market', reason: 'trimmed');

      await repo.renameBatch(id, '   ');
      batches = await repo.batches();
      expect(
        batches.single.name,
        'Saturday market',
        reason: 'a blank rename is a no-op, not an erasure',
      );

      // A hand-made batch lands at the end of the queue, not the front.
      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      await repo.generateBatches();
      final second = await repo.createBatch('Later');
      final names = (await repo.batches()).map((b) => b.name).toList();
      expect(names.last, 'Later');
      expect(second, isNot(id));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'adding a contact straight into a chosen batch targets that batch',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final mine = await repo.createBatch('Mine');
      final outcome = await repo.addContact(
        rawPhone: '0911 111 111',
        name: 'Abebe',
        toBatchId: mine,
      );
      expect(outcome.ok, isTrue);
      expect(outcome.batchName, 'Mine');

      final batch = (await repo.batches()).single;
      expect(batch.total, 1);
      expect(batch.size, 1, reason: 'size follows the membership');
      final contacts = await repo.contactsInBatch(mine);
      expect(contacts.single.name, 'Abebe');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'moving a contact between batches respects status and bookkeeping',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '2');

      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      await repo.upsertContact(e164: '+251922222222', source: 'Gari');
      await repo.generateBatches();
      final from = (await repo.batches()).single;
      final to = await repo.createBatch('Hand-picked');

      final contact = (await repo.contactsInBatch(from.id)).first;
      expect(await repo.moveContactToBatch(contact.id, to), isTrue);

      final batches = await repo.batches();
      expect(batches.firstWhere((b) => b.id == from.id).total, 1);
      expect(batches.firstWhere((b) => b.id == to).total, 1);
      expect(
        batches.firstWhere((b) => b.id == from.id).size,
        1,
        reason: 'both sizes follow the move',
      );

      // Somebody already reached stays put.
      final other = (await repo.contactsInBatch(from.id)).first;
      await db.update(
        'contact',
        {'status': ContactStatus.sent},
        where: 'id = ?',
        whereArgs: [other.id],
      );
      expect(await repo.moveContactToBatch(other.id, to), isFalse);
      expect(
        (await repo.batches()).firstWhere((b) => b.id == from.id).total,
        1,
        reason: 'the refused move must change nothing',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'phone-book picks are normalized, deduplicated and claimed into the batch',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      // One number already lives in another batch; one is unbatched; one is
      // new; one is garbage.
      await repo.setSetting(SettingKeys.batchSize, '1');
      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      await repo.generateBatches();
      await repo.upsertContact(e164: '+251922222222', source: 'Gari');

      final mine = await repo.createBatch('Picked');
      final result = await repo.addPhonesToBatch(mine, [
        (name: 'Abebe', phone: '0911 111 111'), // batched elsewhere
        (name: 'Sara', phone: '0922 222 222'), // unbatched — claimable
        (name: 'Dawit', phone: '0933333333'), // brand new
        (name: 'Junk', phone: 'no digits'),
      ]);
      expect(result.added, 2);
      expect(result.existing, 1);
      expect(result.invalid, 1);

      final batches = await repo.batches();
      expect(batches.firstWhere((b) => b.id == mine).total, 2);
      expect(
        batches.firstWhere((b) => b.id != mine).total,
        1,
        reason: 'the other batch keeps its member',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'conversations pin, archive, hold a draft and give it up when sent',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final id = (await repo.contactForCompose('0911111111'))!;
      await repo.journalOutbound(contactId: id, body: 'first');

      // Pinned sorts above a newer conversation.
      final other = (await repo.contactForCompose('0922222222'))!;
      await repo.journalOutbound(contactId: other, body: 'newer');
      await repo.setPinned(id, true);
      expect((await repo.threads('other')).first.contactId, id);
      expect((await repo.threads('other')).first.pinned, isTrue);

      // Archiving takes it out of the list and clears its badge.
      await repo.setThreadUnread(id, true);
      await repo.setArchived(id, true);
      expect(
        (await repo.threads('other')).map((t) => t.contactId),
        [other],
        reason: 'an archived conversation leaves the inbox',
      );
      expect(await repo.archivedCount('other'), 1);
      final away = (await repo.threads('other', archived: true)).single;
      expect(away.contactId, id);
      expect(away.unreadCount, 0, reason: 'putting it away stops it asking');
      await repo.setArchived(id, false);
      expect((await repo.threads('other')).length, 2);

      // Drafts survive, trim, and clear.
      await repo.saveDraft(id, '  half a thought  ');
      expect(await repo.draftFor(id), 'half a thought');
      expect((await repo.threads('other')).first.hasDraft, isTrue);
      await repo.saveDraft(id, '   ');
      expect(await repo.draftFor(id), isNull);

      // A draft to somebody with no conversation yet creates one.
      final fresh = (await repo.contactForCompose('0933333333'))!;
      await repo.saveDraft(fresh, 'hello?');
      expect(await repo.draftFor(fresh), 'hello?');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'message search finds bodies, escapes wildcards and ignores one letter',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final id = (await repo.contactForCompose('0911111111'))!;
      await repo.journalOutbound(contactId: id, body: 'Your order is ready');
      await repo.journalOutbound(contactId: id, body: 'Paid 100 birr');
      await repo.journalOutbound(contactId: id, body: '50% off today');

      expect((await repo.searchMessages('birr')).single.body, 'Paid 100 birr');
      expect(
        (await repo.searchMessages('READY')).single.body,
        'Your order is ready',
        reason: 'LIKE is case-insensitive for ASCII, which is the point',
      );
      expect(
        (await repo.searchMessages('%')).length,
        0,
        reason: 'not a wildcard',
      );
      expect((await repo.searchMessages('50%')).single.body, '50% off today');
      expect(
        await repo.searchMessages('b'),
        isEmpty,
        reason: 'one letter matches half the inbox and helps nobody',
      );

      final hit = (await repo.searchMessages('birr')).single;
      expect(hit.contactId, id);
      expect(hit.isInbound, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'deleting one message leaves the conversation summary honest',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final id = (await repo.contactForCompose('0911111111'))!;
      await repo.journalOutbound(contactId: id, body: 'first');
      final second = await repo.journalOutbound(contactId: id, body: 'second');
      expect((await repo.threads('other')).single.snippet, 'second');

      await repo.deleteMessage(second);
      expect((await repo.messagesFor(id)).map((m) => m.body), ['first']);
      expect(
        (await repo.threads('other')).single.snippet,
        'first',
        reason: 'the snippet follows what is actually left',
      );

      // Deleting the last one empties the summary rather than lying.
      final first = (await repo.messagesFor(id)).single.id;
      await repo.deleteMessage(first);
      expect((await repo.threads('other')).single.snippet, '');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'writing off a batch\'s failures finishes it without forgetting them',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '3');

      for (final p in ['0911111111', '0922222222', '0933333333']) {
        await repo.upsertContact(e164: '+251${p.substring(1)}', source: 'Gari');
      }
      await repo.generateBatches();
      final batch = (await repo.batches()).single;

      // Two reached, one failed: the stuck state the Partial tab shows.
      final contacts = await repo.contactsInBatch(batch.id);
      await repo.setContactStatus(contacts[0].id, ContactStatus.sent);
      await repo.setContactStatus(contacts[1].id, ContactStatus.delivered);
      await db.update(
        'contact',
        {'status': ContactStatus.failed, 'last_error': 'Generic failure'},
        where: 'id = ?',
        whereArgs: [contacts[2].id],
      );

      expect(await repo.writeOffFailed(batch.id), 1);

      final after = (await repo.batches()).single;
      expect(after.total, 2, reason: 'the batch stops counting them');
      expect(after.failed, 0);
      expect(after.remaining, 0, reason: 'nothing outstanding — reads as done');
      expect(after.size, 2, reason: 'size follows');

      // The person is not forgotten: still failed, still carrying the error,
      // just not on any list.
      final person = await repo.contactById(contacts[2].id);
      expect(person!.status, ContactStatus.failed);
      expect(person.batchId, isNull);
      expect(person.lastError, 'Generic failure');

      // And not silently re-batched: only not_sent contacts are pooled.
      expect(await repo.generateBatches(), 0);

      // Nothing failed → nothing to write off.
      expect(await repo.writeOffFailed(batch.id), 0);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'templates keep the order they are given',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final a = await repo.saveTemplate(label: 'Ask', body: 'Still available?');
      final b = await repo.saveTemplate(body: '  The price is negotiable.  ');
      await repo.saveTemplate(label: 'Docs', body: 'Send me your ID and TIN.');

      var all = await repo.templates();
      expect(all.map((t) => t.id), [a, b, all.last.id]);
      expect(all[1].body, 'The price is negotiable.', reason: 'trimmed');
      expect(
        all[1].display,
        'The price is negotiable.',
        reason: 'an unlabelled template is known by its opening words',
      );
      expect(all[0].display, 'Ask');

      await repo.moveTemplate(b, -1);
      all = await repo.templates();
      expect(all.map((t) => t.id).take(2), [b, a]);

      // Off either end is a no-op rather than a crash.
      await repo.moveTemplate(b, -1);
      expect((await repo.templates()).first.id, b);

      await repo.saveTemplate(
        id: a,
        label: 'Asking',
        body: 'Is it still free?',
      );
      expect(
        (await repo.templates()).firstWhere((t) => t.id == a).body,
        'Is it still free?',
      );
      await repo.deleteTemplate(a);
      expect((await repo.templates()).any((t) => t.id == a), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'notes can belong to a person without leaving the board',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Dawit');
      final dawit = (await repo.contactByPhone('+251911111111'))!;

      final loose = await repo.saveNote(title: 'Errands', body: 'bank');
      final about = await repo.saveNote(
        title: 'Dawit',
        body: 'wants 3 bedroom, max 8M',
        contactId: dawit.id,
      );

      expect((await repo.notesForContact(dawit.id)).single.id, about);
      expect(await repo.notesCountForContact(dawit.id), 1);
      expect(
        (await repo.notes()).map((n) => n.id).toSet(),
        {loose, about},
        reason: 'a note about somebody is still a note',
      );
      expect((await repo.noteById(loose))!.contactId, isNull);

      // Editing must not silently unhook it from the person.
      await repo.saveNote(id: about, title: 'Dawit', body: 'wants 3 bedroom');
      expect((await repo.noteById(about))!.contactId, dawit.id);

      await repo.attachNote(loose, dawit.id);
      expect(await repo.notesCountForContact(dawit.id), 2);
      await repo.attachNote(loose, null);
      expect(await repo.notesCountForContact(dawit.id), 1);

      // A note about somebody carries who, so a card can name them and a
      // search can find them by it.
      final carried = (await repo.notes()).firstWhere((n) => n.id == about);
      expect(carried.about, 'Dawit');
      expect(carried.contactPhone, '0911111111');
      expect(
        (await repo.notes()).firstWhere((n) => n.id == loose).about,
        isNull,
      );
      expect(
        (await repo.notes(query: 'Dawit')).map((n) => n.id),
        contains(about),
        reason: 'searching a person finds what was written about them',
      );
      expect(
        (await repo.notes(query: '0911')).map((n) => n.id),
        contains(about),
        reason: 'and so does searching their number',
      );

      // A nameless contact falls back to the number rather than to nothing.
      final short = (await repo.contactForCompose('8100'))!;
      final about8100 = await repo.saveNote(
        title: 'Bank',
        body: 'code',
        contactId: short,
      );
      expect(
        (await repo.notes()).firstWhere((n) => n.id == about8100).about,
        '8100',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the diary shows what is next and forgets what is done',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Sara');
      final sara = (await repo.contactByPhone('+251911111111'))!;
      final now = DateTime.now().millisecondsSinceEpoch;

      final later = await repo.saveAppointment(
        title: 'Second viewing',
        at: now + 7200000,
        remindAt: now + 5400000,
      );
      final sooner = await repo.saveAppointment(
        contactId: sara.id,
        title: 'Viewing — CMC',
        place: 'CMC',
        at: now + 3600000,
        remindAt: now + 1800000,
      );

      final list = await repo.appointments();
      expect(list.map((a) => a.id), [sooner, later], reason: 'soonest first');
      expect(list.first.who, 'Sara', reason: 'the contact is joined in');
      expect(list.first.place, 'CMC');
      expect((await repo.nextAppointment())!.id, sooner);
      expect((await repo.appointmentsForContact(sara.id)).single.id, sooner);

      // An untitled reminder is still a reminder.
      final bare = await repo.saveAppointment(
        title: '   ',
        at: now + 60000,
        remindAt: now,
      );
      expect((await repo.nextAppointment())!.title, 'Reminder');

      await repo.setAppointmentDone(bare, true);
      await repo.setAppointmentDone(sooner, true);
      expect((await repo.nextAppointment())!.id, later);
      expect((await repo.appointmentsForContact(sara.id)), isEmpty);
      expect(
        (await repo.appointments(includeDone: true)).length,
        3,
        reason: 'done is hidden, not destroyed',
      );

      await repo.deleteAppointment(later);
      expect(await repo.nextAppointment(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'notes pin to the top, recolour without reshuffling, and copy',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final first = await repo.saveNote(title: 'First', body: 'a');
      final second = await repo.saveNote(title: 'Second', body: 'b', tint: 3);
      expect(
        (await repo.notes()).map((n) => n.id),
        [second, first],
        reason: 'newest first while nothing is pinned',
      );

      await repo.setNotePinned(first, true);
      expect((await repo.notes()).first.id, first);
      expect((await repo.notes()).first.pinned, isTrue);

      // Recolouring must not count as editing, or the board reorders itself
      // while the user is picking colours for several notes.
      final before = (await repo.notes()).map((n) => n.id).toList();
      await repo.setNoteTint(second, 7);
      final after = await repo.notes();
      expect(after.map((n) => n.id), before);
      expect(after.firstWhere((n) => n.id == second).tint, 7);

      final copy = await repo.duplicateNote(second);
      final copied = (await repo.notes()).firstWhere((n) => n.id == copy);
      expect(copied.title, 'Second');
      expect(copied.tint, 7);
      expect(
        copied.pinned,
        isFalse,
        reason: 'a copy of a pinned note does not fight it for the top',
      );
      expect(await repo.duplicateNote(9999), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a personal message can wait on the clock and be called off',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      final id = (await repo.contactForCompose('0911111111'))!;
      final at = DateTime.now().millisecondsSinceEpoch + 3600000;
      final scheduled = await repo.scheduleMessage(
        contactId: id,
        body: 'Happy birthday',
        sendAt: at,
      );

      final pending = await repo.scheduledMessagesFor(id);
      expect(pending.single.id, scheduled);
      expect(pending.single.body, 'Happy birthday');
      expect(pending.single.sendAt, at);
      expect(
        await repo.messagesFor(id),
        isEmpty,
        reason: 'a scheduled message is not in the conversation until it goes',
      );

      await repo.cancelScheduledMessage(scheduled);
      expect(await repo.scheduledMessagesFor(id), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the phone book names nameless threads and outranks nobody',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      // A nameless inbound sender, a named contact, and a short code.
      final nameless = await repo.contactForCompose('0911111111');
      await repo.upsertContact(e164: '+251922222222', name: 'Imported Name');
      final short = await repo.contactForCompose('8100');

      final filled = await repo.fillNamesFromDevice([
        (name: 'Abebe', phone: '0911 111 111'),
        (name: 'Wrong', phone: '0922222222'),
        (name: 'Bank', phone: '8100'),
        (name: '', phone: '0933333333'),
      ]);
      expect(filled, 2, reason: 'the nameless two; the named one is kept');

      expect((await repo.contactById(nameless!))!.name, 'Abebe');
      expect(
        (await repo.contactByPhone('+251922222222'))!.name,
        'Imported Name',
        reason: 'an existing name outranks the phone book',
      );
      expect(
        (await repo.contactById(short!))!.name,
        'Bank',
        reason: 'raw-keyed short codes match too',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a scheduled campaign waits, shows itself, and does not read as active',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', source: 'Gari');
      await repo.generateBatches();
      final batch = (await repo.batches()).single;

      final at = DateTime.now().millisecondsSinceEpoch + 3600000;
      final id = await repo.scheduleCampaign(
        batchId: batch.id,
        template: 'Selam {name}',
        simSubscriptionId: null,
        delaySeconds: 5,
        at: at,
      );

      final pending = await repo.scheduledCampaign();
      expect(pending!.campaignId, id);
      expect(pending.batchName, batch.name);
      expect(pending.at, at);
      expect(
        await repo.activeCampaign(),
        isNull,
        reason: 'waiting on the clock is not sending',
      );

      await repo.cancelScheduled(id);
      expect(await repo.scheduledCampaign(), isNull);
      expect(
        (await db.query('campaign')).length,
        0,
        reason: 'a cancelled schedule leaves no husk behind',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a deal moves through stages and the stage clock behaves',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Dani');
      final dani = (await repo.contactByPhone('+251911111111'))!;

      final id = await repo.saveDeal(
        contactId: dani.id,
        title: 'Bole 3BR',
        price: 8500000,
      );
      var deal = (await repo.dealForContact(dani.id))!;
      expect(deal.stage, DealStage.newLead);
      expect(deal.price, 8500000);
      expect(deal.isOpen, isTrue);
      expect(deal.closedAt, isNull);

      // Renaming must not reset the stage clock.
      final clockBefore = deal.stageChangedAt;
      await repo.saveDeal(id: id, contactId: dani.id, title: 'Bole 3BR corner');
      deal = (await repo.dealForContact(dani.id))!;
      expect(deal.title, 'Bole 3BR corner');
      expect(deal.stageChangedAt, clockBefore);

      await repo.setDealStage(id, DealStage.negotiating);
      deal = (await repo.dealForContact(dani.id))!;
      expect(deal.stage, DealStage.negotiating);
      expect((await repo.pipelineCounts())[DealStage.negotiating], 1);

      // Won stamps the close; reopening clears it.
      await repo.setDealStage(id, DealStage.won);
      deal = (await repo.dealForContact(dani.id))!;
      expect(deal.closedAt, isNotNull);
      expect(deal.isOpen, isFalse);
      expect(await repo.pipelineCounts(), isEmpty);
      await repo.setDealStage(id, DealStage.viewing);
      deal = (await repo.dealForContact(dani.id))!;
      expect(deal.closedAt, isNull);

      // The board query names the person.
      expect((await repo.deals()).single.who, 'Dani');

      await repo.deleteDeal(id);
      expect(await repo.dealForContact(dani.id), isNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'tags are shared labels: case-insensitive, wearable, and a batch audience',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '10');

      for (final phone in ['0911111111', '0922222222', '0933333333']) {
        await repo.upsertContact(e164: '+251${phone.substring(1)}');
      }
      await repo.generateBatches();
      final a = (await repo.contactByPhone('+251911111111'))!;
      final b = (await repo.contactByPhone('+251922222222'))!;

      final buyer = (await repo.ensureTag('buyer'))!;
      expect(
        await repo.ensureTag('BUYER'),
        buyer,
        reason: '"Buyer" and "buyer" must be one audience, not two',
      );
      expect(await repo.ensureTag('   '), isNull);

      await repo.setContactTag(a.id, buyer, true);
      await repo.setContactTag(b.id, buyer, true);
      await repo.setContactTag(b.id, buyer, true); // twice is still once
      expect((await repo.tags()).single.count, 2);
      expect(await repo.contactIdsWithTag(buyer), hasLength(2));

      // Everyone tagged buyer lands in the new batch; untagged stay put.
      final target = await repo.createBatch('Buyers');
      final moved = await repo.addTagToBatch(target, buyer);
      expect(moved.moved, 2);
      final inBatch = await repo.contactsInBatch(target);
      expect(inBatch.map((c) => c.id).toSet(), {a.id, b.id});

      // Taking the tag off, and deleting it everywhere.
      await repo.setContactTag(b.id, buyer, false);
      expect((await repo.tagsForContact(b.id)), isEmpty);
      await repo.deleteTag(buyer);
      expect(await repo.tags(), isEmpty);
      expect(await repo.tagsForContact(a.id), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'going cold surfaces quiet open deals and talking warms them back up',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Quiet');
      await repo.upsertContact(e164: '+251922222222', name: 'Fresh');
      await repo.upsertContact(e164: '+251933333333', name: 'NoDeal');
      final quiet = (await repo.contactByPhone('+251911111111'))!;
      final fresh = (await repo.contactByPhone('+251922222222'))!;

      final old =
          DateTime.now().millisecondsSinceEpoch -
          10 * Duration.millisecondsPerDay;
      final quietDeal = await repo.saveDeal(
        contactId: quiet.id,
        title: 'Corolla',
      );
      await repo.saveDeal(contactId: fresh.id, title: 'Vitz');
      // Backdate the quiet one's stage clock — with no talk recorded, the
      // stage change is what quiet is measured from.
      await db.update(
        'deal',
        {'stage_changed_at': old},
        where: 'id = ?',
        whereArgs: [quietDeal],
      );

      var cold = await repo.goingCold();
      expect(cold.single.contact.id, quiet.id);
      expect(cold.single.daysQuiet, greaterThanOrEqualTo(9));

      // A personal message counts as talking; the row disappears.
      await repo.journalOutbound(contactId: quiet.id, body: 'selam');
      cold = await repo.goingCold();
      expect(cold, isEmpty);

      // A campaign blast is NOT talking: backdate again, journal with a
      // campaign id, still cold.
      await db.update(
        'contact',
        {'last_talked_at': old},
        where: 'id = ?',
        whereArgs: [quiet.id],
      );
      await repo.journalOutbound(
        contactId: quiet.id,
        body: 'blast',
        campaignId: 1,
      );
      cold = await repo.goingCold();
      expect(
        cold.single.contact.id,
        quiet.id,
        reason: 'a blast to 6,800 people is not a relationship',
      );

      // A won deal stops being watched.
      await repo.setDealStage(quietDeal, DealStage.won);
      await db.update(
        'deal',
        {'stage_changed_at': old},
        where: 'id = ?',
        whereArgs: [quietDeal],
      );
      expect(await repo.goingCold(), isEmpty);

      // touchContact never moves the clock backwards.
      final now = DateTime.now().millisecondsSinceEpoch;
      await repo.touchContact(quiet.id, now);
      await repo.touchContact(quiet.id, now - 5000);
      final row = await db.query(
        'contact',
        columns: ['last_talked_at'],
        where: 'id = ?',
        whereArgs: [quiet.id],
      );
      expect(row.single['last_talked_at'], now);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'messages from other apps land in the feed and can be claimed by a person',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Teddy');
      final teddy = (await repo.contactByPhone('+251911111111'))!;

      // What the native listener writes: two from a WhatsApp name the app
      // does not recognise, one from a Telegram group.
      final now = DateTime.now().millisecondsSinceEpoch;
      Future<void> capture(
        String app,
        String sender,
        String body,
        int at, {
        String? room,
        int? contactId,
      }) => db.insert('chat_message', {
        'app': app,
        'sender': sender,
        'room': room,
        'body': body,
        'at': at,
        'contact_id': contactId,
        'seen': 0,
      });

      await capture('com.whatsapp', 'Teddy Cars', 'Vitz 2012, 850k', now - 200);
      await capture(
        'com.whatsapp',
        'Teddy Cars',
        'Still available?',
        now - 100,
      );
      await capture(
        'org.telegram.messenger',
        'Yabu',
        'Corolla coming tomorrow',
        now,
        room: 'Broker group',
      );

      // Newest first, with the app and the room legible.
      final feed = await repo.chatMessages();
      expect(feed.map((m) => m.body).first, 'Corolla coming tomorrow');
      expect(feed.first.appLabel, 'Telegram');
      expect(feed.first.room, 'Broker group');
      expect(feed.first.who, 'Yabu', reason: 'unlinked shows the app name');

      // The badge counts what has not been looked at, and opening clears it.
      expect(await repo.unseenChatCount(), 3);
      await repo.markChatsSeen();
      expect(await repo.unseenChatCount(), 0);

      // Claiming a sender names them everywhere they have already spoken,
      // and counts as having talked — which is what stops a live deal being
      // called cold just because the talking happened on WhatsApp.
      await repo.linkChatSender(
        app: 'com.whatsapp',
        sender: 'Teddy Cars',
        contactId: teddy.id,
      );
      final linked = (await repo.chatMessages())
          .where((m) => m.app == 'com.whatsapp')
          .toList();
      expect(linked, hasLength(2));
      expect(linked.every((m) => m.contactId == teddy.id), isTrue);
      expect(linked.first.who, 'Teddy', reason: 'the contact name wins');
      expect((await repo.contactById(teddy.id))!.id, teddy.id);
      final stamped = await db.query(
        'contact',
        columns: ['last_talked_at'],
        where: 'id = ?',
        whereArgs: [teddy.id],
      );
      expect(stamped.single['last_talked_at'], now - 100);

      // The Telegram sender is untouched by a WhatsApp link.
      final telegram = (await repo.chatMessages()).firstWhere(
        (m) => m.app == 'org.telegram.messenger',
      );
      expect(telegram.contactId, isNull);

      // And the escape hatch empties everything.
      await repo.clearChatMessages();
      expect(await repo.chatMessages(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the shelf answers "who sent me this?" by words and by code',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      await repo.upsertContact(e164: '+251911111111', name: 'Teddy');
      final teddy = (await repo.contactByPhone('+251911111111'))!;

      final corolla = await repo.saveListing(
        title: 'White Corolla 2018',
        body: 'Clean, 120k km, first owner',
        sourceContactId: teddy.id,
        photos: ['/data/cars/a.jpg', '/data/cars/b.jpg'],
      );
      final vitz = await repo.saveListing(
        title: 'Vitz 2012',
        sourceText: '@yabu_cars on Telegram',
      );

      // The shelf lists both, newest first, with the sender named.
      final shelf = await repo.listings();
      expect(shelf.map((c) => c.id).toList(), [vitz, corolla]);
      expect(shelf.last.who, 'Teddy');
      expect(shelf.first.who, '@yabu_cars on Telegram');
      expect(shelf.last.photos, hasLength(2));

      // Search by words, by sender, and — the point — by the posted code,
      // in every sloppy form it will be typed.
      expect((await repo.listings(query: 'corolla')).single.id, corolla);
      expect((await repo.listings(query: 'teddy')).single.id, corolla);
      expect((await repo.listings(query: 'yabu')).single.id, vitz);
      final code = (await repo.listingById(corolla))!.code;
      expect(code, '#LF00$corolla');
      // Including #TR and #AW — prefixes from before the renames. Posts
      // captioned that way are out in the world and must keep working.
      for (final form in [
        code,
        'TR00$corolla',
        '#AW00$corolla',
        '00$corolla',
        'tr 00$corolla',
      ]) {
        expect(
          (await repo.listings(query: form)).single.id,
          corolla,
          reason: '"$form" must find the car',
        );
      }

      // Sold moves it off the shelf but never loses it.
      await repo.setListingSold(corolla, true);
      expect((await repo.listings()).single.id, vitz);
      expect((await repo.listings(sold: true)).single.id, corolla);
      expect((await repo.listingById(corolla))!.soldAt, isNotNull);
      await repo.setListingSold(corolla, false);
      expect(await repo.listings(sold: true), isEmpty);

      // The quick lookup behind "who sent this?".
      expect((await repo.quickContactLookup('ted')).single.id, teddy.id);
      expect((await repo.quickContactLookup('0911111111')).single.id, teddy.id);

      await repo.deleteListing(vitz);
      expect((await repo.listings()).single.id, corolla);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a search for punctuation searches for punctuation',
    () async {
      final db = await open();
      addTearDown(db.close);
      final repo = Repo(db);

      // SQLite's LIKE reads % as "anything" and _ as "any one character". Left
      // unescaped, a broker searching for a percentage or an underscore in a
      // price note matched their whole book instead — the worst kind of bug,
      // because it looks like the search simply did not work.
      await repo.saveNote(title: 'Loan 30% down', body: 'Dzire');
      await repo.saveNote(title: 'Cash only', body: 'Vitz');
      await repo.upsertContact(e164: '+251911000001', name: 'Abebe 50% man');
      await repo.upsertContact(e164: '+251911000002', name: 'Chala');

      expect(
        (await repo.notes(query: '%')).length,
        1,
        reason: 'the wildcard must be read as a literal per cent sign',
      );
      expect((await repo.notes(query: '30%')).single.title, 'Loan 30% down');
      expect((await repo.notes(query: '_')).length, 0);

      final hits = await repo.searchContacts(query: '%');
      expect(hits.length, 1);
      expect(hits.single.name, 'Abebe 50% man');
      expect((await repo.searchContacts(query: '_')).length, 0);

      // And an ordinary search still behaves.
      expect((await repo.notes(query: 'vitz')).single.title, 'Cash only');
      expect((await repo.searchContacts(query: 'chala')).length, 1);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a shelf built as "car" comes through the rename with its codes',
    () async {
      // The table was named for cars because that is what the first user
      // sells; it is named for listings now. The rows and their ids have to
      // survive that, because the id IS the #LF code already printed into
      // channel posts out in the world — losing it would orphan every one.
      final dir = await Directory.systemTemp.createTemp('campaign_sms_v12');
      final path = '${dir.path}/campaign_sms.db';
      addTearDown(() => dir.delete(recursive: true));

      // A v12 database, with the shelf under its old name.
      final old = await openCampaignDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      await old.close();
      final raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await raw.execute('ALTER TABLE listing RENAME TO car');
      await raw.insert('car', {
        'title': 'White Corolla 2018',
        'body': 'Teddy sent this',
        'source_text': 'Teddy',
        'photos': '[]',
        'created_at': 1,
      });
      await raw.setVersion(12);
      await raw.close();

      final upgraded = await openCampaignDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(upgraded.close);
      expect(await upgraded.getVersion(), 13);

      final repo = Repo(upgraded);
      final shelf = await repo.listings();
      expect(shelf.single.title, 'White Corolla 2018');
      expect(
        shelf.single.code,
        '#LF001',
        reason: 'the id, and so the printed code, must be untouched',
      );
      expect((await repo.listings(query: '#LF001')).single.id, shelf.single.id);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
