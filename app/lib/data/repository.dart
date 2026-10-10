import 'dart:convert';

// `Batch` here means a batch of campaign contacts, not sqflite's statement batch.
import 'package:sqflite/sqflite.dart' hide Batch;

import 'applock.dart';
import 'database.dart';
import 'license.dart';
import 'models.dart';
import 'phone.dart';
import 'segments.dart';
import 'selling.dart';

/// Everything that touches the database from Dart.
///
/// Spec 4 asks for the status transition rules to live in one place; that place is
/// [setContactStatus] and the guarded UPDATEs below. Nothing else in `lib/` writes
/// `contact.status` directly.
class Repo {
  Repo(this.db);

  final Database db;

  // ------------------------------------------------------------------ settings

  Future<Map<String, String>> allSettings() async {
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<String> getSetting(String key, String fallback) async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return fallback;
    return rows.first['value'] as String;
  }

  Future<int> getSettingInt(String key, int fallback) async =>
      int.tryParse(await getSetting(key, '$fallback')) ?? fallback;

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------------ the lock

  /// Is a PIN set? Everything else about the lock hangs off this one answer.
  Future<bool> lockIsSet() async =>
      (await getSetting(SettingKeys.lockHash, '')).isNotEmpty;

  /// Sets or replaces the PIN, and clears whatever wrong-guess state was
  /// standing — a new code starts with a clean slate.
  Future<void> setLockPin(String pin) async {
    final salt = AppLock.newSalt();
    await setSetting(SettingKeys.lockSalt, salt);
    await setSetting(SettingKeys.lockHash, AppLock.hash(pin, salt));
    // The length, so the keypad knows when a guess is complete and can check
    // it once instead of after every digit — checking as you type would count
    // one attempt per keystroke and lock the owner out of their own app.
    // It is the same thing the row of dots gives away anyway.
    await setSetting(SettingKeys.lockLength, '${pin.trim().length}');
    await setSetting(SettingKeys.lockWrongCount, '0');
    await setSetting(SettingKeys.lockCooldownUntil, '0');
  }

  /// How many digits the code has, for drawing the dots. Four if unset.
  Future<int> lockLength() async {
    final n = await getSettingInt(SettingKeys.lockLength, 4);
    return n.clamp(4, 8);
  }

  /// Removes the lock. Requires the current PIN, so somebody holding an
  /// unlocked phone cannot quietly turn the lock off for later.
  Future<bool> clearLockPin(String currentPin) async {
    if (!await checkLockPin(currentPin)) return false;
    await setSetting(SettingKeys.lockHash, '');
    await setSetting(SettingKeys.lockSalt, '');
    await setSetting(SettingKeys.lockWrongCount, '0');
    await setSetting(SettingKeys.lockCooldownUntil, '0');
    return true;
  }

  /// Checks a PIN and keeps the wrong-guess tally. A correct code clears the
  /// tally; a wrong one extends the wait.
  Future<bool> checkLockPin(String pin) async {
    final salt = await getSetting(SettingKeys.lockSalt, '');
    final stored = await getSetting(SettingKeys.lockHash, '');
    final ok = AppLock.verify(pin, salt: salt, stored: stored);
    if (ok) {
      await setSetting(SettingKeys.lockWrongCount, '0');
      await setSetting(SettingKeys.lockCooldownUntil, '0');
      return true;
    }
    final wrong = await getSettingInt(SettingKeys.lockWrongCount, 0) + 1;
    await setSetting(SettingKeys.lockWrongCount, '$wrong');
    final wait = AppLock.cooldown(wrong);
    if (wait > Duration.zero) {
      await setSetting(
        SettingKeys.lockCooldownUntil,
        '${DateTime.now().millisecondsSinceEpoch + wait.inMilliseconds}',
      );
    }
    return false;
  }

  /// How long the lock screen must refuse to take a guess. Zero means now.
  ///
  /// Read against the clock rather than a timer, so force-quitting the app or
  /// rebooting the phone does not shorten the wait — but the stored moment is
  /// also ignored if it is absurdly far in the future, which is what winding
  /// the clock forward and back would otherwise leave behind.
  Future<Duration> lockCooldownLeft() async {
    final until = await getSettingInt(SettingKeys.lockCooldownUntil, 0);
    if (until <= 0) return Duration.zero;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return Duration.zero;
    const ceiling = Duration(minutes: 5);
    return left > ceiling.inMilliseconds
        ? ceiling
        : Duration(milliseconds: left);
  }

  // ------------------------------------------------------------------ backups

  /// Stamped every time a backup is actually written or handed to another app.
  Future<void> markBackedUp() => setSetting(
    SettingKeys.lastBackupAt,
    '${DateTime.now().millisecondsSinceEpoch}',
  );

  /// When the last backup happened, or null if there has never been one.
  Future<DateTime?> lastBackupAt() async {
    final at = await getSettingInt(SettingKeys.lastBackupAt, 0);
    return at <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(at);
  }

  // ------------------------------------------------------------------ status transitions

  /// The only sanctioned way to move a contact's status from Dart.
  ///
  /// `replied` and `do_not_contact` are terminal for campaigns; nothing may move a
  /// contact out of them except an explicit user action ([reinstate]).
  Future<void> setContactStatus(
    int contactId,
    String next, {
    String? error,
  }) async {
    const terminal = [ContactStatus.replied, ContactStatus.doNotContact];
    if (terminal.contains(next)) {
      await db.update(
        'contact',
        {'status': next, 'last_error': ?error},
        where: 'id = ?',
        whereArgs: [contactId],
      );
      return;
    }
    // Guarded: never drag a contact back out of a terminal state.
    await db.update(
      'contact',
      {'status': next, 'last_error': ?error},
      where: 'id = ? AND status NOT IN (?, ?)',
      whereArgs: [contactId, ContactStatus.replied, ContactStatus.doNotContact],
    );
  }

  Future<void> markDoNotContact(int contactId) => setContactStatus(
    contactId,
    ContactStatus.doNotContact,
    error: 'Blocked by user',
  );

  /// Explicit user override: put a do-not-contact / replied contact back in the pool.
  /// Clears the batch assignment so batch rebuilding can pick it up cleanly.
  Future<void> reinstate(int contactId) async {
    await db.update(
      'contact',
      {'status': ContactStatus.notSent, 'batch_id': null, 'last_error': null},
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  // ------------------------------------------------------------------ import

  /// Inserts one normalized contact, or fills in a missing name on an existing one.
  /// Returns true when a new row was created.
  Future<bool> upsertContact({
    required String e164,
    String? name,
    String? source,
    Transaction? txn,
  }) async {
    final exec = txn ?? db;
    final existing = await exec.query(
      'contact',
      columns: ['id', 'name', 'source'],
      where: 'phone_e164 = ?',
      whereArgs: [e164],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final currentName = row['name'] as String?;
      final currentSource = row['source'] as String?;
      final updates = <String, Object?>{};
      if ((currentName == null || currentName.trim().isEmpty) &&
          name != null &&
          name.trim().isNotEmpty) {
        updates['name'] = name.trim();
      }
      // Keep every account the number came from, so "Gari / Jiji" survives a re-import.
      if (source != null && source.trim().isNotEmpty) {
        final merged = _mergeSources(currentSource, source.trim());
        if (merged != currentSource) updates['source'] = merged;
      }
      if (updates.isNotEmpty) {
        await exec.update(
          'contact',
          updates,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      return false;
    }

    await exec.insert('contact', {
      'phone_e164': e164,
      'phone_local': localForm(e164),
      'name': (name != null && name.trim().isNotEmpty) ? name.trim() : null,
      'source': source?.trim(),
      'status': ContactStatus.notSent,
      'batch_id': null,
      'attempts': 0,
      'is_campaign': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  }

  static String _mergeSources(String? existing, String incoming) {
    if (existing == null || existing.trim().isEmpty) return incoming;
    final parts = existing
        .split('/')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.any((p) => p.toLowerCase() == incoming.toLowerCase())) {
      return existing;
    }
    parts.add(incoming);
    return parts.join(' / ');
  }

  Future<void> addNeedsReview({
    String? name,
    String? phone,
    String? source,
    required String reason,
    Transaction? txn,
  }) async {
    await (txn ?? db).insert('needs_review', {
      'raw_name': name,
      'raw_phone': phone,
      'raw_source': source,
      'reason': reason,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<NeedsReviewRow>> needsReview() async {
    final rows = await db.query('needs_review', orderBy: 'id');
    return rows.map(NeedsReviewRow.fromRow).toList();
  }

  Future<int> needsReviewCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM needs_review'),
      ) ??
      0;

  /// Fixes a needs-review row: if the corrected phone normalizes, it joins the pool.
  Future<String?> resolveNeedsReview(
    int id,
    String phone,
    String? name,
    String? source,
  ) async {
    final e164 = normalizePhone(phone);
    if (e164 == null) return rejectionReason(phone);
    await upsertContact(e164: e164, name: name, source: source);
    await db.delete('needs_review', where: 'id = ?', whereArgs: [id]);
    return null;
  }

  Future<void> discardNeedsReview(int id) async {
    await db.delete('needs_review', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------------ batches

  /// Assigns unbatched `not_sent` contacts into batches (spec 5).
  ///
  /// Idempotent by construction: it only ever looks at contacts with
  /// `batch_id IS NULL AND status = 'not_sent'`, so a contact already in a batch, or
  /// one that has been sent to / replied / blocked, can never be moved or re-added.
  /// Returns the number of batches created.
  Future<int> generateBatches() async {
    final size = await getSettingInt(SettingKeys.batchSize, 100);
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction<int>((txn) async {
      final pool = await txn.query(
        'contact',
        columns: ['id'],
        where: 'batch_id IS NULL AND status = ? AND is_campaign = 1',
        whereArgs: [ContactStatus.notSent],
        orderBy: 'id',
      );
      if (pool.isEmpty) return 0;

      // Continue the numbering rather than restarting at 1.
      final maxRow = await txn.rawQuery('SELECT COUNT(*) AS c FROM batch');
      var index = (maxRow.first['c'] as int?) ?? 0;
      // New batches join the back of the queue, wherever the user has since
      // dragged the existing ones.
      var position = await _lastPosition(txn);

      var created = 0;
      for (var offset = 0; offset < pool.length; offset += size) {
        final slice = pool.skip(offset).take(size).toList();
        index += 1;
        position += 1;
        final batchId = await txn.insert('batch', {
          'name': 'Batch $index',
          'size': slice.length,
          'status': BatchStatus.pending,
          'position': position,
          'created_at': now,
        });
        final ids = slice.map((r) => r['id'] as int).toList();
        await txn.rawUpdate(
          'UPDATE contact SET batch_id = ? WHERE id IN (${List.filled(ids.length, '?').join(',')})',
          [batchId, ...ids],
        );
        created += 1;
      }
      return created;
    });
  }

  Future<void> renameBatch(int batchId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await db.update(
      'batch',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [batchId],
    );
  }

  /// An empty batch of the user's own, at the end of the queue. It fills by
  /// hand, from the phone book, or by moving people in — never by the
  /// automatic batcher, which only ever creates its own.
  Future<int> createBatch(String name) async {
    final trimmed = name.trim();
    return db.insert('batch', {
      'name': trimmed.isEmpty ? 'New batch' : trimmed,
      'size': 0,
      'status': BatchStatus.pending,
      'position': await _lastPosition(db) + 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Moves one contact into [toBatchId].
  ///
  /// Only the unreached move — someone already sent to belongs to the story of
  /// the batch that reached them, and moving them would quietly rewrite both
  /// batches' numbers. Returns false when the move is refused.
  Future<bool> moveContactToBatch(int contactId, int toBatchId) {
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'contact',
        columns: ['batch_id', 'status'],
        where: 'id = ?',
        whereArgs: [contactId],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final status = rows.first['status'] as String;
      if (status != ContactStatus.notSent && status != ContactStatus.failed) {
        return false;
      }
      final from = rows.first['batch_id'] as int?;
      if (from == toBatchId) return false;

      await txn.update(
        'contact',
        {'batch_id': toBatchId},
        where: 'id = ?',
        whereArgs: [contactId],
      );
      if (from != null) {
        await txn.rawUpdate(
          'UPDATE batch SET size = MAX(size - 1, 0) WHERE id = ?',
          [from],
        );
      }
      await txn.rawUpdate('UPDATE batch SET size = size + 1 WHERE id = ?', [
        toBatchId,
      ]);
      return true;
    });
  }

  /// Rows ticked in the phone-book picker, headed for one batch.
  ///
  /// Same normalizer as a CSV row. An existing unbatched contact is claimed
  /// for this batch; one already living in a batch is left where it is and
  /// reported as a duplicate — a number can only ever be in one batch.
  Future<({int added, int existing, int invalid})> addPhonesToBatch(
    int batchId,
    List<({String? name, String? phone})> entries,
  ) {
    return db.transaction((txn) async {
      var added = 0, existing = 0, invalid = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in entries) {
        final e164 = normalizePhone(e.phone);
        if (e164 == null) {
          invalid++;
          continue;
        }
        final rows = await txn.query(
          'contact',
          columns: ['id', 'batch_id', 'status', 'is_campaign'],
          where: 'phone_e164 = ?',
          whereArgs: [e164],
          limit: 1,
        );
        if (rows.isEmpty) {
          await txn.insert('contact', {
            'phone_e164': e164,
            'phone_local': localForm(e164),
            'name': (e.name?.trim().isEmpty ?? true) ? null : e.name!.trim(),
            'source': 'Phone contacts',
            'status': ContactStatus.notSent,
            'batch_id': batchId,
            'attempts': 0,
            'is_campaign': 1,
            'created_at': now,
          });
          added++;
        } else {
          final r = rows.first;
          final claimable =
              r['batch_id'] == null &&
              r['status'] == ContactStatus.notSent &&
              (r['is_campaign'] as int? ?? 1) == 1;
          if (claimable) {
            await txn.update(
              'contact',
              {'batch_id': batchId},
              where: 'id = ?',
              whereArgs: [r['id']],
            );
            added++;
          } else {
            existing++;
          }
        }
      }
      if (added > 0) {
        await txn.rawUpdate('UPDATE batch SET size = size + ? WHERE id = ?', [
          added,
          batchId,
        ]);
      }
      return (added: added, existing: existing, invalid: invalid);
    });
  }

  /// Names nameless contacts from the phone book.
  ///
  /// New senders are named the moment their message arrives; this is for the
  /// threads that already existed when the contacts permission was granted —
  /// they were stored as bare numbers because there was nothing to ask at the
  /// time. Never overwrites a name that is already there: an import or a
  /// hand-typed name outranks the phone book. Returns how many gained one.
  Future<int> fillNamesFromDevice(
    List<({String? name, String? phone})> entries,
  ) async {
    // Nameless first: on a phone with a thousand contacts and three unnamed
    // threads, walking the threads beats walking the phone book.
    final nameless = await db.query(
      'contact',
      columns: ['id', 'phone_e164'],
      where: "name IS NULL OR TRIM(name) = ''",
    );
    if (nameless.isEmpty) return 0;

    final byPhone = <String, String>{};
    for (final e in entries) {
      final name = e.name?.trim() ?? '';
      if (name.isEmpty) continue;
      final e164 = normalizePhone(e.phone);
      if (e164 != null) byPhone.putIfAbsent(e164, () => name);
      // Short codes and foreign numbers are keyed raw, so match those too.
      final raw = e.phone?.trim() ?? '';
      if (raw.isNotEmpty) byPhone.putIfAbsent(raw, () => name);
    }
    if (byPhone.isEmpty) return 0;

    var filled = 0;
    for (final row in nameless) {
      final name = byPhone[row['phone_e164'] as String];
      if (name == null) continue;
      await db.update(
        'contact',
        {'name': name},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      filled++;
    }
    return filled;
  }

  static Future<int> _lastPosition(DatabaseExecutor exec) async {
    final row = await exec.rawQuery('SELECT MAX(position) AS p FROM batch');
    return (row.first['p'] as int?) ?? 0;
  }

  Future<List<Batch>> batches() async {
    final rows = await db.rawQuery('''
      SELECT b.id, b.name, b.size, b.status, b.position, b.created_at, b.completed_at,
             COUNT(c.id) AS total,
             SUM(CASE WHEN c.status = 'not_sent' THEN 1 ELSE 0 END) AS remaining,
             SUM(CASE WHEN c.status IN ('sent','delivered') THEN 1 ELSE 0 END) AS sent,
             SUM(CASE WHEN c.status = 'replied' THEN 1 ELSE 0 END) AS replied,
             SUM(CASE WHEN c.status = 'failed' THEN 1 ELSE 0 END) AS failed
      FROM batch b
      LEFT JOIN contact c ON c.batch_id = b.id
      GROUP BY b.id
      ORDER BY b.position, b.id
    ''');
    return rows.map(Batch.fromRow).toList();
  }

  /// Gives up on a batch's failed contacts: takes them off the list so the
  /// batch can finish, without pretending anything about them.
  ///
  /// They keep `status = 'failed'`, their attempts and their last error — the
  /// dashboard's Failed count stays honest and they can still be found,
  /// retried by hand from their own page, or re-batched deliberately. What
  /// changes is only that this batch stops waiting for them: a batch at 99
  /// of 100 otherwise sits in "Partial" forever on the strength of one number
  /// that will never answer. Returns how many were written off.
  Future<int> writeOffFailed(int batchId) {
    return db.transaction<int>((txn) async {
      final n = await txn.update(
        'contact',
        {'batch_id': null},
        where: 'batch_id = ? AND status = ?',
        whereArgs: [batchId, ContactStatus.failed],
      );
      if (n > 0) {
        await txn.rawUpdate(
          'UPDATE batch SET size = MAX(0, size - ?) WHERE id = ?',
          [n, batchId],
        );
      }
      return n;
    });
  }

  /// Moves a batch one place earlier (-1) or later (+1) in the sending order.
  ///
  /// Swapping with the neighbour rather than renumbering the whole list keeps
  /// this to two writes however many batches there are, and there is nothing to
  /// go wrong halfway. Returns false when the batch is already at the end it is
  /// being moved towards.
  Future<bool> moveBatch(int batchId, int delta) async {
    if (delta == 0) return false;
    return db.transaction<bool>((txn) async {
      final ordered = await txn.query(
        'batch',
        columns: ['id', 'position'],
        orderBy: 'position, id',
      );
      final index = ordered.indexWhere((r) => r['id'] == batchId);
      final target = index + delta;
      if (index < 0 || target < 0 || target >= ordered.length) return false;

      // Positions can be equal after a migration seeded them, so write both
      // sides explicitly from the list order instead of trusting the stored
      // numbers to differ.
      await txn.update(
        'batch',
        {'position': target + 1},
        where: 'id = ?',
        whereArgs: [batchId],
      );
      await txn.update(
        'batch',
        {'position': index + 1},
        where: 'id = ?',
        whereArgs: [ordered[target]['id']],
      );
      // Everything else keeps its place, renumbered so a later swap has clean
      // neighbours to work with.
      for (var i = 0; i < ordered.length; i++) {
        if (i == index || i == target) continue;
        await txn.update(
          'batch',
          {'position': i + 1},
          where: 'id = ?',
          whereArgs: [ordered[i]['id']],
        );
      }
      return true;
    });
  }

  /// Writes a whole order at once, for a list the user has dragged.
  ///
  /// The caller passes every batch id in the order it should now be in, so one
  /// drag is one consistent write rather than a chain of swaps that could each
  /// leave the list half-moved.
  Future<void> saveBatchOrder(List<int> orderedIds) =>
      db.transaction((txn) async {
        for (var i = 0; i < orderedIds.length; i++) {
          await txn.update(
            'batch',
            {'position': i + 1},
            where: 'id = ?',
            whereArgs: [orderedIds[i]],
          );
        }
      });

  /// One walk-in customer, typed in by hand.
  ///
  /// The number goes through exactly the same normalizer a CSV row does, so
  /// `0911…`, `+251911…` and `251911…` all land as one E.164 number and a
  /// duplicate is still a duplicate. A new contact joins the first batch with
  /// room in it rather than waiting for a rebuild — somebody standing at the
  /// counter should be in the next send, not the one after next.
  Future<ManualAdd> addContact({
    required String rawPhone,
    String? name,
    int? toBatchId,
  }) async {
    final e164 = normalizePhone(rawPhone);
    if (e164 == null) return ManualAdd.rejected(rejectionReason(rawPhone));

    final trimmed = name?.trim();
    final existing = await contactByPhone(e164);
    if (existing != null) {
      // Filling in a missing name is still worth doing; adding the row twice is not.
      if ((existing.name == null || existing.name!.trim().isEmpty) &&
          trimmed != null &&
          trimmed.isNotEmpty) {
        await db.update(
          'contact',
          {'name': trimmed},
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      }
      return ManualAdd.duplicate(existing);
    }

    final size = await getSettingInt(SettingKeys.batchSize, 100);
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction<ManualAdd>((txn) async {
      final contactId = await txn.insert('contact', {
        'phone_e164': e164,
        'phone_local': localForm(e164),
        'name': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        'source': 'Added by hand',
        'status': ContactStatus.notSent,
        'is_campaign': 1,
        'created_at': now,
      });

      // Added from inside a batch: that batch, no questions. Capacity is a
      // default for the automatic path, not a wall against the user's intent.
      if (toBatchId != null) {
        final named = await txn.query(
          'batch',
          columns: ['name'],
          where: 'id = ?',
          whereArgs: [toBatchId],
          limit: 1,
        );
        if (named.isNotEmpty) {
          await txn.update(
            'contact',
            {'batch_id': toBatchId},
            where: 'id = ?',
            whereArgs: [contactId],
          );
          await txn.rawUpdate('UPDATE batch SET size = size + 1 WHERE id = ?', [
            toBatchId,
          ]);
          return ManualAdd.added(
            contactId: contactId,
            batchId: toBatchId,
            batchName: named.first['name'] as String,
          );
        }
      }

      // The first batch still waiting that has not filled up. A batch mid-send
      // is left alone: the service is walking its contacts right now.
      final room = await txn.rawQuery(
        '''
        SELECT b.id, b.name, COUNT(c.id) AS total
        FROM batch b LEFT JOIN contact c ON c.batch_id = b.id
        WHERE b.status IN (?, ?)
        GROUP BY b.id
        HAVING total < ?
        ORDER BY b.position, b.id
        LIMIT 1
        ''',
        [BatchStatus.pending, BatchStatus.partial, size],
      );

      int batchId;
      String batchName;
      if (room.isNotEmpty) {
        batchId = room.first['id'] as int;
        batchName = room.first['name'] as String;
        await txn.rawUpdate('UPDATE batch SET size = size + 1 WHERE id = ?', [
          batchId,
        ]);
      } else {
        final count =
            Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM batch'),
            ) ??
            0;
        batchName = 'Batch ${count + 1}';
        batchId = await txn.insert('batch', {
          'name': batchName,
          'size': 1,
          'status': BatchStatus.pending,
          'position': await _lastPosition(txn) + 1,
          'created_at': now,
        });
      }

      await txn.update(
        'contact',
        {'batch_id': batchId},
        where: 'id = ?',
        whereArgs: [contactId],
      );
      return ManualAdd.added(
        contactId: contactId,
        batchId: batchId,
        batchName: batchName,
      );
    });
  }

  /// Takes somebody off the list for good — the row, its messages and its
  /// conversation.
  ///
  /// Leaving the messages behind would keep the number in the inbox and in the
  /// usage figures after the user had told the app to forget it, which is the
  /// opposite of what "delete" means to the person pressing it.
  Future<void> deleteContact(int contactId) => db.transaction((txn) async {
    final row = await txn.query(
      'contact',
      columns: ['batch_id'],
      where: 'id = ?',
      whereArgs: [contactId],
      limit: 1,
    );
    if (row.isEmpty) return;
    final batchId = row.first['batch_id'] as int?;

    await txn.delete(
      'message',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
    await txn.delete('thread', where: 'contact_id = ?', whereArgs: [contactId]);
    await txn.delete('contact', where: 'id = ?', whereArgs: [contactId]);

    if (batchId != null) {
      // The recorded size is what the batch says it holds; keep it honest, and
      // do not let a batch emptied by hand claim a negative one.
      await txn.rawUpdate(
        'UPDATE batch SET size = MAX(size - 1, 0) WHERE id = ?',
        [batchId],
      );
    }
  });

  /// Failed contacts count as work left to do, not just unsent ones.
  ///
  /// Running out of SIM credit mid-batch leaves every remaining contact `failed`,
  /// not `not_sent` — so a batch can have nothing "remaining" and still be
  /// unfinished. Offering it back is the only way the user gets to those people.
  Future<Batch?> nextPendingBatch() async {
    final all = await batches().then(
      (l) => l.where((b) => b.status != BatchStatus.inProgress).toList(),
    );
    // Fresh contacts first. A batch that is 97% done with a handful of failures
    // is worth retrying, but it should not stand in front of the next hundred
    // people who have never been messaged at all.
    for (final b in all) {
      if (b.remaining > 0) return b;
    }
    for (final b in all) {
      if (b.failed > 0) return b;
    }
    return null;
  }

  /// Puts one failed contact straight back in the queue.
  ///
  /// An explicit tap outranks the attempts budget — the budget exists to stop
  /// the *engine* hammering a dead number, not to overrule a person looking at
  /// exactly this row. The engine only ever picks `not_sent`, so if a campaign
  /// is running this contact is simply next again.
  Future<bool> retryContact(int contactId) async {
    final n = await db.update(
      'contact',
      {'status': ContactStatus.notSent, 'last_error': null},
      where: 'id = ? AND status = ?',
      whereArgs: [contactId, ContactStatus.failed],
    );
    return n > 0;
  }

  /// Contacts in [batchId] that failed and still have attempts left.
  Future<int> retryableInBatch(int batchId) => failedCount(batchId: batchId);

  Future<List<Contact>> contactsInBatch(int batchId, {int? limit}) async {
    final rows = await db.query(
      'contact',
      where: 'batch_id = ?',
      whereArgs: [batchId],
      orderBy: 'id',
      limit: limit,
    );
    return rows.map(Contact.fromRow).toList();
  }

  // ------------------------------------------------------------------ scheduling

  /// Writes the campaign that will start later. The row exists now — visible,
  /// cancellable — and the native alarm promotes it to `in_progress` at [at].
  Future<int> scheduleCampaign({
    required int batchId,
    required String template,
    required int? simSubscriptionId,
    required int delaySeconds,
    required int at,
  }) {
    return db.insert('campaign', {
      'batch_id': batchId,
      'message_template': template,
      'sim_subscription_id': simSubscriptionId,
      'delay_seconds': delaySeconds,
      'status': 'scheduled',
      'started_at': at,
      'scheduled_at': at,
    });
  }

  /// The one pending schedule, if any. One at a time by design: two alarms
  /// promoting two campaigns would race for a single send loop.
  Future<ScheduledCampaign?> scheduledCampaign() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.batch_id, c.scheduled_at, c.message_template, b.name
      FROM campaign c JOIN batch b ON b.id = c.batch_id
      WHERE c.status = 'scheduled'
      ORDER BY c.scheduled_at LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ScheduledCampaign(
      campaignId: r['id'] as int,
      batchId: r['batch_id'] as int,
      batchName: r['name'] as String,
      template: r['message_template'] as String,
      at: (r['scheduled_at'] as int?) ?? 0,
    );
  }

  /// Nothing has been sent yet, so cancelling is simply deleting the row.
  Future<void> cancelScheduled(int campaignId) async {
    await db.delete(
      'campaign',
      where: "id = ? AND status = 'scheduled'",
      whereArgs: [campaignId],
    );
  }

  // ------------------------------------------------------------------ campaigns

  /// Creates the campaign row the native send service will pick up.
  ///
  /// The service is driven entirely by `campaign.status = 'in_progress'`, so writing
  /// this row *is* starting the campaign; the channel call just wakes the service.
  Future<int> createCampaign({
    required int batchId,
    required String template,
    required int? simSubscriptionId,
    required int delaySeconds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction<int>((txn) async {
      final id = await txn.insert('campaign', {
        'batch_id': batchId,
        'message_template': template,
        'sim_subscription_id': simSubscriptionId,
        'delay_seconds': delaySeconds,
        'status': 'in_progress',
        'started_at': now,
        'sent_count': 0,
        'delivered_count': 0,
        'failed_count': 0,
      });
      await txn.update(
        'batch',
        {'status': BatchStatus.inProgress, 'completed_at': null},
        where: 'id = ?',
        whereArgs: [batchId],
      );
      await txn.insert('settings', {
        'key': SettingKeys.campaignActive,
        'value': '1',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return id;
    });
  }

  Future<CampaignProgress?> activeCampaign() async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.batch_id, c.message_template, c.started_at, b.name AS batch_name
      FROM campaign c JOIN batch b ON b.id = c.batch_id
      WHERE c.status = 'in_progress'
      ORDER BY c.id DESC LIMIT 1
    ''');
    if (rows.isEmpty) return null;
    return _progressFor(rows.first);
  }

  Future<CampaignProgress?> campaignById(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.id, c.batch_id, c.message_template, c.started_at, b.name AS batch_name
      FROM campaign c JOIN batch b ON b.id = c.batch_id
      WHERE c.id = ? LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    return _progressFor(rows.first);
  }

  Future<CampaignProgress> _progressFor(Map<String, Object?> row) async {
    final batchId = row['batch_id'] as int;
    final counts = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'not_sent' THEN 1 ELSE 0 END) AS remaining,
        SUM(CASE WHEN status IN ('sent','delivered') THEN 1 ELSE 0 END) AS sent,
        SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
        SUM(CASE WHEN status = 'replied' THEN 1 ELSE 0 END) AS replied
      FROM contact WHERE batch_id = ?
    ''',
      [batchId],
    );
    final c = counts.first;
    return CampaignProgress(
      campaignId: row['id'] as int,
      batchId: batchId,
      batchName: (row['batch_name'] as String?) ?? 'Batch',
      total: (c['total'] as int?) ?? 0,
      remaining: (c['remaining'] as int?) ?? 0,
      sent: (c['sent'] as int?) ?? 0,
      delivered: (c['delivered'] as int?) ?? 0,
      failed: (c['failed'] as int?) ?? 0,
      replied: (c['replied'] as int?) ?? 0,
      engineState: await getSetting(SettingKeys.engineState, 'idle'),
      template: (row['message_template'] as String?) ?? '',
      startedAt: (row['started_at'] as int?) ?? 0,
    );
  }

  /// Stop requested from the UI. The service also flips these, but doing it here too
  /// means a stop still takes effect if the service was already gone.
  Future<void> markCampaignStopped(int campaignId, int batchId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.update(
        'campaign',
        {'status': 'stopped', 'finished_at': now},
        where: 'id = ? AND status = ?',
        whereArgs: [campaignId, 'in_progress'],
      );
      await txn.update(
        'batch',
        {'status': BatchStatus.partial, 'completed_at': now},
        where: 'id = ?',
        whereArgs: [batchId],
      );
      await txn.insert('settings', {
        'key': SettingKeys.campaignActive,
        'value': '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {
        'key': SettingKeys.engineState,
        'value': 'idle',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// Puts failed contacts back in the pool for another attempt (spec 7, retry queue).
  /// Respects the max-attempts setting; returns how many were requeued.
  Future<int> retryFailed({int? batchId}) async {
    final maxAttempts = await getSettingInt(SettingKeys.maxAttempts, 2);
    final where = StringBuffer('status = ? AND attempts < ?');
    final args = <Object?>[ContactStatus.failed, maxAttempts];
    if (batchId != null) {
      where.write(' AND batch_id = ?');
      args.add(batchId);
    }
    return db.update(
      'contact',
      {'status': ContactStatus.notSent, 'last_error': null},
      where: where.toString(),
      whereArgs: args,
    );
  }

  Future<int> failedCount({int? batchId}) async {
    final maxAttempts = await getSettingInt(SettingKeys.maxAttempts, 2);
    final rows = batchId == null
        ? await db.rawQuery(
            'SELECT COUNT(*) FROM contact WHERE status = ? AND attempts < ?',
            [ContactStatus.failed, maxAttempts],
          )
        : await db.rawQuery(
            'SELECT COUNT(*) FROM contact WHERE status = ? AND attempts < ? AND batch_id = ?',
            [ContactStatus.failed, maxAttempts, batchId],
          );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ------------------------------------------------------------------ messages & threads

  /// Journals an outbound one-off message and returns its id, so native only has to
  /// touch the radio. Mirrors what the send service does for campaign messages.
  Future<int> journalOutbound({
    required int contactId,
    required String body,
    int? campaignId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final parts = countSegments(body).segments;
    final id = await db.insert('message', {
      'contact_id': contactId,
      'campaign_id': campaignId,
      'direction': 'outbound',
      'body': body,
      'segments': parts,
      'status': 'pending',
      'created_at': now,
      'parts_total': parts,
      'parts_ok': 0,
      'parts_failed': 0,
    });
    await _touchThread(contactId, body, now);
    // A personal message is talking; a campaign blast is not.
    if (campaignId == null) await touchContact(contactId, now);
    return id;
  }

  Future<void> _touchThread(int contactId, String snippet, int at) async {
    final kindRow = await db.query(
      'contact',
      columns: ['is_campaign'],
      where: 'id = ?',
      whereArgs: [contactId],
      limit: 1,
    );
    final kind =
        kindRow.isNotEmpty && (kindRow.first['is_campaign'] as int? ?? 1) == 1
        ? 'campaign'
        : 'other';
    final updated = await db.update(
      'thread',
      {'last_message_at': at, 'snippet': snippet, 'kind': kind},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
    if (updated == 0) {
      await db.insert('thread', {
        'contact_id': contactId,
        'kind': kind,
        'last_message_at': at,
        'unread_count': 0,
        'snippet': snippet,
      });
    }
  }

  /// [archived] false is the ordinary inbox; true is the archive drawer.
  /// Pinned conversations sort above everything, newest-first within each group.
  Future<List<ThreadSummary>> threads(
    String kind, {
    bool archived = false,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.contact_id, t.kind, t.last_message_at, t.unread_count, t.snippet,
             t.pinned, t.archived, t.draft,
             c.name, c.phone_local, c.phone_e164, c.status
      FROM thread t JOIN contact c ON c.id = t.contact_id
      WHERE t.kind = ? AND t.archived = ?
      ORDER BY t.pinned DESC, t.last_message_at DESC
    ''',
      [kind, archived ? 1 : 0],
    );
    return rows.map(ThreadSummary.fromRow).toList();
  }

  /// How many conversations are put away, so the inbox can offer the drawer
  /// only when there is something in it.
  Future<int> archivedCount(String kind) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM thread WHERE kind = ? AND archived = 1',
          [kind],
        ),
      ) ??
      0;

  Future<void> setPinned(int contactId, bool pinned) async {
    await db.update(
      'thread',
      {'pinned': pinned ? 1 : 0},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
  }

  /// Archiving also clears the badge: a conversation put away should not keep
  /// asking to be read from behind the drawer.
  Future<void> setArchived(int contactId, bool archived) async {
    await db.update(
      'thread',
      archived ? {'archived': 1, 'unread_count': 0} : {'archived': 0},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
  }

  /// The half-written reply. Saved against the thread row, which is created if
  /// this is the first thing to ever happen in the conversation — a draft to
  /// somebody you have never messaged is still worth keeping.
  Future<void> saveDraft(int contactId, String? text) async {
    final trimmed = text?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final updated = await db.update(
      'thread',
      {'draft': value},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
    if (updated == 0 && value != null) {
      await _touchThread(contactId, '', DateTime.now().millisecondsSinceEpoch);
      await db.update(
        'thread',
        {'draft': value},
        where: 'contact_id = ?',
        whereArgs: [contactId],
      );
    }
  }

  Future<String?> draftFor(int contactId) async {
    final rows = await db.query(
      'thread',
      columns: ['draft'],
      where: 'contact_id = ?',
      whereArgs: [contactId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['draft'] as String?;
  }

  /// Full-text-ish search across message bodies.
  ///
  /// LIKE rather than FTS5: the table holds thousands of rows, not millions,
  /// and an FTS virtual table would have to be built and kept in step by both
  /// the Dart and Kotlin writers — two engines, one index, every insert.
  Future<List<MessageHit>> searchMessages(
    String query, {
    int limit = 60,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final rows = await db.rawQuery(
      '''
      SELECT m.id, m.contact_id, m.body, m.direction, m.created_at,
             c.name, c.phone_local
      FROM message m JOIN contact c ON c.id = m.contact_id
      WHERE m.body LIKE ? ESCAPE '\\'
      ORDER BY m.created_at DESC
      LIMIT ?
    ''',
      ['%${_escapeLike(q)}%', limit],
    );
    return rows.map(MessageHit.fromRow).toList();
  }

  static String _escapeLike(String raw) => raw
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  /// Removes one message and leaves the conversation's summary honest — the
  /// snippet becomes whatever is now the last thing said.
  Future<void> deleteMessage(int messageId) async {
    final rows = await db.query(
      'message',
      columns: ['contact_id'],
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final contactId = rows.first['contact_id'] as int;
    await db.delete('message', where: 'id = ?', whereArgs: [messageId]);

    final last = await db.query(
      'message',
      columns: ['body', 'created_at'],
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    if (last.isEmpty) {
      await db.update(
        'thread',
        {'snippet': ''},
        where: 'contact_id = ?',
        whereArgs: [contactId],
      );
    } else {
      await db.update(
        'thread',
        {
          'snippet': last.first['body'],
          'last_message_at': last.first['created_at'],
        },
        where: 'contact_id = ?',
        whereArgs: [contactId],
      );
    }
  }

  // ------------------------------------------------- scheduled personal messages

  Future<int> scheduleMessage({
    required int contactId,
    required String body,
    required int sendAt,
  }) => db.insert('scheduled_message', {
    'contact_id': contactId,
    'body': body,
    'send_at': sendAt,
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });

  Future<List<ScheduledMessage>> scheduledMessagesFor(int contactId) async {
    final rows = await db.query(
      'scheduled_message',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'send_at ASC',
    );
    return rows.map(ScheduledMessage.fromRow).toList();
  }

  Future<void> cancelScheduledMessage(int id) =>
      db.delete('scheduled_message', where: 'id = ?', whereArgs: [id]);

  Future<List<Message>> messagesFor(int contactId) async {
    final rows = await db.query(
      'message',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(Message.fromRow).toList();
  }

  Future<void> markThreadRead(int contactId) async {
    await db.update(
      'thread',
      {'unread_count': 0},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
  }

  Future<int> unreadTotal() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COALESCE(SUM(unread_count), 0) FROM thread'),
      ) ??
      0;

  /// Unread split by tab, so the Inbox can say *where* the badge is coming from.
  /// A message read from the notification shade never opens a thread, so without
  /// this the count on the nav bar has no visible source.
  Future<Map<String, int>> unreadByKind() async {
    final rows = await db.rawQuery(
      'SELECT kind, COALESCE(SUM(unread_count), 0) AS n FROM thread GROUP BY kind',
    );
    return {
      for (final r in rows)
        (r['kind'] as String? ?? 'other'): (r['n'] as int? ?? 0),
    };
  }

  /// [kind] null clears every tab. Returns how many threads were carrying a badge.
  Future<int> markAllRead({String? kind}) async {
    final where = StringBuffer('unread_count > 0');
    final args = <Object?>[];
    if (kind != null) {
      where.write(' AND kind = ?');
      args.add(kind);
    }
    return db.update(
      'thread',
      {'unread_count': 0},
      where: where.toString(),
      whereArgs: args,
    );
  }

  /// Marking a thread unread again puts a single badge back on it — useful for
  /// "I will deal with this later", and the natural undo for a mis-tap.
  /// The contact row behind "write to this number" — the in-app new-message
  /// sheet and the sms: links the dialer hands over. Finds the existing row or
  /// creates an ad-hoc one exactly the way the inbound receiver does: never
  /// batchable, never part of a campaign. Returns null when [raw] has no
  /// digits to write to.
  Future<int?> contactForCompose(String raw) async {
    final trimmed = raw.trim();
    if (!trimmed.contains(RegExp(r'[0-9]'))) return null;
    // Short codes and international numbers are legitimate here, so a number
    // the Ethiopian normalizer rejects is kept under its raw form — the same
    // rule the receiver applies to inbound senders.
    final key = normalizePhone(trimmed) ?? trimmed;
    final existing = await db.query(
      'contact',
      columns: ['id'],
      where: 'phone_e164 = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('contact', {
      'phone_e164': key,
      'phone_local': key.startsWith('+251') ? localForm(key) : trimmed,
      'source': 'compose',
      'status': ContactStatus.doNotContact,
      'is_campaign': 0,
      'attempts': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Mute is how you "block" somebody who is not on the campaign list — their
  /// texts still land (a default SMS app may not drop messages) but silently.
  Future<void> setMuted(int contactId, bool muted) async {
    await db.update(
      'contact',
      {'muted': muted ? 1 : 0},
      where: 'id = ?',
      whereArgs: [contactId],
    );
  }

  /// Deletes a conversation — the messages and the thread row — but keeps the
  /// contact and their status.
  ///
  /// This is the difference from [deleteContact]: a replied contact whose
  /// conversation is cleared must stay `replied`, or the next batch rebuild
  /// would put someone who answered "stop texting me" straight back in the
  /// pool.
  Future<void> deleteThread(int contactId) => db.transaction((txn) async {
    await txn.delete(
      'message',
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
    await txn.delete('thread', where: 'contact_id = ?', whereArgs: [contactId]);
  });

  Future<void> setThreadUnread(int contactId, bool unread) async {
    await db.update(
      'thread',
      {'unread_count': unread ? 1 : 0},
      where: 'contact_id = ?',
      whereArgs: [contactId],
    );
  }

  // ------------------------------------------------------------------ contacts

  /// [statuses] is a set because the buckets people think in do not map one to
  /// one onto stored statuses — "sent" to a user means everything that left the
  /// phone, which is `sent` plus `delivered`.
  Future<List<Contact>> searchContacts({
    String query = '',
    List<String>? statuses,
    int limit = 300,
  }) async {
    final where = StringBuffer('is_campaign = 1');
    final args = <Object?>[];
    if (statuses != null && statuses.isNotEmpty) {
      where.write(
        ' AND status IN (${List.filled(statuses.length, '?').join(',')})',
      );
      args.addAll(statuses);
    }
    if (query.trim().isNotEmpty) {
      // Escaped, or a search for "%" matches every contact in the book and a
      // number written "09_1" matches numbers that have nothing in common
      // with it. ESCAPE has to be named for SQLite to honour the backslash.
      final q = '%${_escapeLike(query.trim())}%';
      where.write(
        " AND (name LIKE ? ESCAPE '\\' OR phone_e164 LIKE ? ESCAPE '\\' "
        "OR phone_local LIKE ? ESCAPE '\\')",
      );
      args.addAll([q, q, q]);
    }
    final rows = await db.query(
      'contact',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'id',
      limit: limit,
    );
    return rows.map(Contact.fromRow).toList();
  }

  Future<Contact?> contactById(int id) async {
    final rows = await db.query(
      'contact',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Contact.fromRow(rows.first);
  }

  Future<Contact?> contactByPhone(String e164) async {
    final rows = await db.query(
      'contact',
      where: 'phone_e164 = ?',
      whereArgs: [e164],
      limit: 1,
    );
    return rows.isEmpty ? null : Contact.fromRow(rows.first);
  }

  // ------------------------------------------------------------------ stats

  Future<Stats> stats() async {
    // The side figures run concurrently rather than one await after another.
    // This is the query behind the dashboard, so its latency is the app's.
    final results = await Future.wait<Object>([
      db.rawQuery('''
        SELECT
          COUNT(*) AS total,
          SUM(CASE WHEN status = 'not_sent' THEN 1 ELSE 0 END) AS not_sent,
          SUM(CASE WHEN status = 'sent' THEN 1 ELSE 0 END) AS sent,
          SUM(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS delivered,
          SUM(CASE WHEN status = 'replied' THEN 1 ELSE 0 END) AS replied,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS failed,
          SUM(CASE WHEN status = 'do_not_contact' THEN 1 ELSE 0 END) AS dnc
        FROM contact WHERE is_campaign = 1
      '''),
      sentToday(),
      segmentsSentToday(),
      getSettingInt(SettingKeys.capCountsSegments, 1),
      getSettingInt(SettingKeys.dailyCap, 100),
      needsReviewCount(),
      unreadTotal(),
    ]);
    final r = (results[0] as List<Map<String, Object?>>).first;
    return Stats(
      totalContacts: (r['total'] as int?) ?? 0,
      notSent: (r['not_sent'] as int?) ?? 0,
      sent: (r['sent'] as int?) ?? 0,
      delivered: (r['delivered'] as int?) ?? 0,
      replied: (r['replied'] as int?) ?? 0,
      failed: (r['failed'] as int?) ?? 0,
      doNotContact: (r['dnc'] as int?) ?? 0,
      sentToday: results[1] as int,
      segmentsToday: results[2] as int,
      capCountsSegments: results[3] as int == 1,
      dailyCap: results[4] as int,
      needsReview: results[5] as int,
      unread: results[6] as int,
    );
  }

  /// Must match `CampaignDb.sentToday` in Kotlin — the engine enforces the cap with
  /// the same query, this copy only drives the UI counter.
  Future<int> sentToday() => _today('COUNT(*)');

  /// The number the operator counted. A message is one row but one *or more* SMS:
  /// 160 Latin characters per segment, 70 in Amharic. See `CampaignDb.kt`.
  Future<int> segmentsSentToday() => _today('COALESCE(SUM(segments), 0)');

  Future<int> _today(String expression) async {
    final now = DateTime.now();
    final startOfDay = DateTime(
      now.year,
      now.month,
      now.day,
    ).millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      "SELECT $expression FROM message WHERE direction = 'outbound' "
      "AND status IN ('sent','delivered') AND sent_at >= ?",
      [startOfDay],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// The Dart half of `CampaignDb.sweepStalePending`: contacts left 'queued' by a
  /// send whose receipt never arrived would otherwise never appear in a batch or a
  /// retry queue again. Run on app start, so a stranded contact is recovered even
  /// if no further campaign is ever started.
  Future<int> sweepStalePending({
    Duration olderThan = const Duration(minutes: 10),
  }) async {
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    final stale = await db.rawQuery(
      "SELECT DISTINCT contact_id FROM message WHERE direction = 'outbound' "
      "AND status = 'pending' AND created_at < ?",
      [cutoff],
    );
    if (stale.isEmpty) return 0;
    await db.rawUpdate(
      "UPDATE message SET status = 'failed', error = 'No delivery receipt', "
      "parts_failed = parts_total WHERE direction = 'outbound' "
      "AND status = 'pending' AND created_at < ?",
      [cutoff],
    );
    for (final row in stale) {
      await db.rawUpdate(
        "UPDATE contact SET status = 'failed', last_error = 'No delivery receipt' "
        "WHERE id = ? AND status = 'queued'",
        [row['contact_id']],
      );
    }
    return stale.length;
  }

  /// The last [days] days, oldest first, always exactly [days] long — a day
  /// with nothing sent is a zero in the series rather than a gap in it, or the
  /// chart would draw a flat line through the quiet days.
  Future<Trend> trend({int days = 7}) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final from = start.millisecondsSinceEpoch;

    final sent = await db.rawQuery(
      "SELECT sent_at FROM message WHERE direction = 'outbound' "
      "AND status IN ('sent','delivered') AND sent_at >= ?",
      [from],
    );
    final replies = await db.rawQuery(
      "SELECT created_at FROM message WHERE direction = 'inbound' "
      'AND created_at >= ?',
      [from],
    );

    final messageCounts = List.filled(days, 0);
    final replyCounts = List.filled(days, 0);

    void bucket(List<int> into, Object? millis) {
      if (millis is! int) return;
      final at = DateTime.fromMillisecondsSinceEpoch(millis);
      final index = DateTime(
        at.year,
        at.month,
        at.day,
      ).difference(start).inDays;
      if (index >= 0 && index < into.length) into[index]++;
    }

    for (final r in sent) {
      bucket(messageCounts, r['sent_at']);
    }
    for (final r in replies) {
      bucket(replyCounts, r['created_at']);
    }

    return Trend([
      for (var i = 0; i < days; i++)
        DayCount(
          start.add(Duration(days: i)),
          messageCounts[i],
          replyCounts[i],
        ),
    ]);
  }

  /// Everything the usage screen shows, counted in one pass.
  ///
  /// The encoding is worked out from the body rather than stored, because it is
  /// a property of the text and the text is already here — a column would be a
  /// second copy of the same fact, free to drift. A few thousand rows is
  /// nothing to walk.
  Future<Usage> usage() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final weekAgo = startOfToday.subtract(const Duration(days: 6));
    final monthAgo = startOfToday.subtract(const Duration(days: 29));

    final rows = await db.rawQuery(
      "SELECT body, segments, sent_at FROM message WHERE direction = 'outbound' "
      "AND status IN ('sent','delivered')",
    );

    var messages = 0, segments = 0;
    var latinMessages = 0, latinSegments = 0;
    var amharicMessages = 0, amharicSegments = 0;
    var today = 0, week = 0, month = 0;

    for (final r in rows) {
      final cost = (r['segments'] as int?) ?? 1;
      messages++;
      segments += cost;

      final body = (r['body'] as String?) ?? '';
      if (countSegments(body).encoding == SmsEncoding.ucs2) {
        amharicMessages++;
        amharicSegments += cost;
      } else {
        latinMessages++;
        latinSegments += cost;
      }

      final at = r['sent_at'];
      if (at is int) {
        if (at >= startOfToday.millisecondsSinceEpoch) today += cost;
        if (at >= weekAgo.millisecondsSinceEpoch) week += cost;
        if (at >= monthAgo.millisecondsSinceEpoch) month += cost;
      }
    }

    return Usage(
      messages: messages,
      segments: segments,
      latinMessages: latinMessages,
      latinSegments: latinSegments,
      amharicMessages: amharicMessages,
      amharicSegments: amharicSegments,
      today: today,
      week: week,
      month: month,
      bundle: await getSettingInt(SettingKeys.bundleSize, 0),
    );
  }

  // ------------------------------------------------------------------- notes

  /// Pinned first, then most recently touched. [query] matches title or body.
  /// Pinned first, then newest.
  ///
  /// The id breaks ties: two notes saved inside the same millisecond — which
  /// happens the moment anything creates notes in a loop — otherwise came back
  /// in whatever order SQLite felt like, and the board reshuffled between two
  /// reads of the same data.
  /// The four columns a note is found by. Split out because the ESCAPE clause
  /// makes the line too long to read inside the query it belongs to.
  static const _noteSearchWhere =
      "WHERE n.title LIKE ? ESCAPE '\\' OR n.body LIKE ? ESCAPE '\\' "
      "OR c.name LIKE ? ESCAPE '\\' OR c.phone_local LIKE ? ESCAPE '\\'";

  Future<List<Note>> notes({String query = ''}) async {
    final q = query.trim();
    // The contact is joined in rather than looked up per card: a note about
    // somebody has to be able to say who, and one query per tile on a
    // scrolling board is the wrong way to find that out. Their name is
    // searchable too — "Dawit" should find the note about Dawit.
    final rows = await db.rawQuery('''
      SELECT n.*, c.name AS contact_name, c.phone_local AS contact_phone
      FROM note n LEFT JOIN contact c ON c.id = n.contact_id
      ${q.isEmpty ? '' : _noteSearchWhere}
      ORDER BY n.pinned DESC, n.updated_at DESC, n.id DESC
    ''', q.isEmpty ? const [] : List.filled(4, '%${_escapeLike(q)}%'));
    return rows.map(Note.fromRow).toList();
  }

  /// What has been written about one person. Kept separate from [notes] so a
  /// conversation can show its own notes without filtering the whole board.
  Future<List<Note>> notesForContact(int contactId) async {
    final rows = await db.rawQuery(
      '''
      SELECT n.*, c.name AS contact_name, c.phone_local AS contact_phone
      FROM note n LEFT JOIN contact c ON c.id = n.contact_id
      WHERE n.contact_id = ?
      ORDER BY n.pinned DESC, n.updated_at DESC, n.id DESC
    ''',
      [contactId],
    );
    return rows.map(Note.fromRow).toList();
  }

  Future<int> notesCountForContact(int contactId) async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM note WHERE contact_id = ?', [
          contactId,
        ]),
      ) ??
      0;

  Future<Note?> noteById(int id) async {
    final rows = await db.query(
      'note',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Note.fromRow(rows.first);
  }

  /// Returns the note's id, creating it when [id] is null.
  Future<int> saveNote({
    int? id,
    required String title,
    required String body,
    int tint = 0,
    bool pinned = false,
    int? contactId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      return db.insert('note', {
        'title': title,
        'body': body,
        'tint': tint,
        'pinned': pinned ? 1 : 0,
        'contact_id': contactId,
        'created_at': now,
        'updated_at': now,
      });
    }
    // contact_id is not in the update: who a note is about is set when it is
    // created and changed by [attachNote], never silently by a save.
    await db.update(
      'note',
      {
        'title': title,
        'body': body,
        'tint': tint,
        'pinned': pinned ? 1 : 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return id;
  }

  /// Ties an existing note to a person, or cuts it loose with null.
  Future<void> attachNote(int id, int? contactId) => db.update(
    'note',
    {'contact_id': contactId},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deleteNote(int id) =>
      db.delete('note', where: 'id = ?', whereArgs: [id]);

  Future<void> setNotePinned(int id, bool pinned) => db.update(
    'note',
    {
      'pinned': pinned ? 1 : 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Recolouring is not editing: the note says the same thing afterwards, so
  /// `updated_at` is left alone and the board does not reshuffle under the
  /// user's hand while they are picking a colour for several notes at once.
  Future<void> setNoteTint(int id, int tint) =>
      db.update('note', {'tint': tint}, where: 'id = ?', whereArgs: [id]);

  /// A copy of a note, placed at the top as the newest thing. Never pinned:
  /// two identical notes both stuck to the top is nobody's intention.
  Future<int?> duplicateNote(int id) async {
    final note = await noteById(id);
    if (note == null) return null;
    return saveNote(title: note.title, body: note.body, tint: note.tint);
  }

  /// Contacts for a set of normalized phone keys, in one query — the Calls
  /// screen matches a few hundred log rows without a query per row.
  Future<Map<String, Contact>> contactsByKeys(List<String> keys) async {
    if (keys.isEmpty) return const {};
    final placeholders = List.filled(keys.length, '?').join(',');
    final rows = await db.query(
      'contact',
      where: 'phone_e164 IN ($placeholders)',
      whereArgs: keys,
    );
    return {
      for (final r in rows) (r['phone_e164'] as String): Contact.fromRow(r),
    };
  }

  // ------------------------------------------------------------------ templates

  Future<List<Template>> templates() async {
    final rows = await db.query('template', orderBy: 'position, id');
    return rows.map(Template.fromRow).toList();
  }

  Future<int> saveTemplate({
    int? id,
    String label = '',
    required String body,
  }) async {
    final trimmed = body.trim();
    if (id != null) {
      await db.update(
        'template',
        {'label': label.trim(), 'body': trimmed},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    final last =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COALESCE(MAX(position), 0) FROM template'),
        ) ??
        0;
    return db.insert('template', {
      'label': label.trim(),
      'body': trimmed,
      'position': last + 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteTemplate(int id) =>
      db.delete('template', where: 'id = ?', whereArgs: [id]);

  /// Moves a template one place up (-1) or down (+1), by swapping positions
  /// with its neighbour — the same trick the batch list uses.
  Future<void> moveTemplate(int id, int delta) async {
    final all = await templates();
    final index = all.indexWhere((t) => t.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= all.length) return;
    await db.transaction((txn) async {
      await txn.update(
        'template',
        {'position': all[target].position},
        where: 'id = ?',
        whereArgs: [all[index].id],
      );
      await txn.update(
        'template',
        {'position': all[index].position},
        where: 'id = ?',
        whereArgs: [all[target].id],
      );
    });
  }

  // --------------------------------------------------------------- appointments

  /// Everything still to come, soonest first, then anything missed.
  ///
  /// Past appointments are not hidden: a viewing you did not mark done is
  /// exactly the thing you need to see.
  Future<List<Appointment>> appointments({bool includeDone = false}) async {
    final rows = await db.rawQuery('''
      SELECT a.*, c.name, c.phone_local
      FROM appointment a LEFT JOIN contact c ON c.id = a.contact_id
      ${includeDone ? '' : 'WHERE a.done = 0'}
      ORDER BY a.done, a.at
    ''');
    return rows.map(Appointment.fromRow).toList();
  }

  Future<List<Appointment>> appointmentsForContact(int contactId) async {
    final rows = await db.rawQuery(
      '''
      SELECT a.*, c.name, c.phone_local
      FROM appointment a LEFT JOIN contact c ON c.id = a.contact_id
      WHERE a.contact_id = ? AND a.done = 0
      ORDER BY a.at
    ''',
      [contactId],
    );
    return rows.map(Appointment.fromRow).toList();
  }

  /// The next thing due, for the dashboard. Null when the diary is clear.
  Future<Appointment?> nextAppointment() async {
    final rows = await db.rawQuery('''
      SELECT a.*, c.name, c.phone_local
      FROM appointment a LEFT JOIN contact c ON c.id = a.contact_id
      WHERE a.done = 0
      ORDER BY a.at LIMIT 1
    ''');
    return rows.isEmpty ? null : Appointment.fromRow(rows.first);
  }

  Future<int> saveAppointment({
    int? id,
    int? contactId,
    required String title,
    String? place,
    required int at,
    required int remindAt,
  }) async {
    final values = {
      'contact_id': contactId,
      'title': title.trim().isEmpty ? 'Reminder' : title.trim(),
      'place': (place == null || place.trim().isEmpty) ? null : place.trim(),
      'at': at,
      'remind_at': remindAt,
    };
    if (id != null) {
      await db.update('appointment', values, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('appointment', {
      ...values,
      'done': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setAppointmentDone(int id, bool done) => db.update(
    'appointment',
    {'done': done ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deleteAppointment(int id) =>
      db.delete('appointment', where: 'id = ?', whereArgs: [id]);

  // ---------------------------------------------------------------------- deals

  /// Every deal, the person joined in, open ones first and the freshest stage
  /// changes at the top of each group. The board groups by stage in Dart.
  Future<List<Deal>> deals() async {
    final rows = await db.rawQuery('''
      SELECT d.*, c.name AS contact_name, c.phone_local AS contact_phone
      FROM deal d JOIN contact c ON c.id = d.contact_id
      ORDER BY d.closed_at IS NOT NULL, d.stage_changed_at DESC, d.id DESC
    ''');
    return rows.map(Deal.fromRow).toList();
  }

  /// The deal to show on a person's profile: their open one, or failing that
  /// the one that closed most recently.
  Future<Deal?> dealForContact(int contactId) async {
    final rows = await db.rawQuery(
      '''
      SELECT d.*, c.name AS contact_name, c.phone_local AS contact_phone
      FROM deal d JOIN contact c ON c.id = d.contact_id
      WHERE d.contact_id = ?
      ORDER BY d.closed_at IS NOT NULL, d.stage_changed_at DESC, d.id DESC
      LIMIT 1
    ''',
      [contactId],
    );
    return rows.isEmpty ? null : Deal.fromRow(rows.first);
  }

  /// Creates or edits a deal's facts — the thing and the figure. Stage moves
  /// go through [setDealStage] so the stage clock cannot be reset by a rename.
  Future<int> saveDeal({
    int? id,
    required int contactId,
    String title = '',
    int? price,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id != null) {
      await db.update(
        'deal',
        {'title': title.trim(), 'price': price, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    }
    return db.insert('deal', {
      'contact_id': contactId,
      'title': title.trim(),
      'stage': DealStage.newLead,
      'price': price,
      'stage_changed_at': now,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Moves a deal to [stage], restarting the stage clock. Won and lost also
  /// stamp `closed_at`; moving back out of them clears it — a reopened deal
  /// is open, not "won but still being worked".
  Future<void> setDealStage(int id, String stage) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'deal',
      {
        'stage': stage,
        'stage_changed_at': now,
        'closed_at': DealStage.isOpen(stage) ? null : now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDeal(int id) =>
      db.delete('deal', where: 'id = ?', whereArgs: [id]);

  /// How many deals sit in each open stage — the dashboard's pipeline card.
  Future<Map<String, int>> pipelineCounts() async {
    final placeholders = List.filled(DealStage.open.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT stage, COUNT(*) AS n FROM deal '
      'WHERE stage IN ($placeholders) GROUP BY stage',
      DealStage.open,
    );
    return {
      for (final r in rows) (r['stage'] as String): (r['n'] as int?) ?? 0,
    };
  }

  /// People with a live deal who have gone quiet — no call or personal
  /// message either way in [days] days. Campaign blasts do not count as
  /// talking, which is the point: a blast is not a relationship.
  ///
  /// A contact the app has never seen a touch for is measured from when their
  /// deal last changed stage, so a fresh deal is not born cold.
  Future<List<ColdContact>> goingCold({int days = 7, int limit = 3}) async {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch -
        days * Duration.millisecondsPerDay;
    final placeholders = List.filled(DealStage.open.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT c.*,
             d.id AS deal_id, d.title AS deal_title, d.stage AS deal_stage,
             d.price AS deal_price,
             d.stage_changed_at AS deal_stage_changed_at,
             d.created_at AS deal_created_at,
             COALESCE(c.last_talked_at, d.stage_changed_at) AS quiet_since
      FROM deal d JOIN contact c ON c.id = d.contact_id
      WHERE d.stage IN ($placeholders)
        AND COALESCE(c.last_talked_at, d.stage_changed_at) <= ?
      ORDER BY quiet_since
    ''',
      [...DealStage.open, cutoff],
    );
    final seen = <int>{};
    final result = <ColdContact>[];
    for (final r in rows) {
      final contact = Contact.fromRow(r);
      if (!seen.add(contact.id)) continue;
      result.add(
        ColdContact(
          contact: contact,
          deal: Deal(
            id: r['deal_id'] as int,
            contactId: contact.id,
            title: (r['deal_title'] as String?) ?? '',
            stage: (r['deal_stage'] as String?) ?? DealStage.newLead,
            price: r['deal_price'] as int?,
            stageChangedAt: (r['deal_stage_changed_at'] as int?) ?? 0,
            closedAt: null,
            createdAt: (r['deal_created_at'] as int?) ?? 0,
            contactName: contact.name,
            contactPhone: contact.phoneLocal,
          ),
          lastTalkedAt: (r['quiet_since'] as int?) ?? 0,
        ),
      );
      if (result.length >= limit) break;
    }
    return result;
  }

  /// Records that we actually talked to this person — a call, or a personal
  /// message in either direction. Never moves the clock backwards.
  Future<void> touchContact(int contactId, [int? at]) async {
    final stamp = at ?? DateTime.now().millisecondsSinceEpoch;
    await db.rawUpdate(
      'UPDATE contact SET last_talked_at = ? '
      'WHERE id = ? AND (last_talked_at IS NULL OR last_talked_at < ?)',
      [stamp, contactId, stamp],
    );
  }

  // ------------------------------------------------------------------- listings

  /// The shelf: unsold listings newest first, or the sold pile when [sold].
  ///
  /// [query] searches the words and — the whole point — the code: "047",
  /// "lf047" and "#LF047" all find listing 47, because that code is what the
  /// broker reads off their own channel post.
  Future<List<Listing>> listings({bool sold = false, String query = ''}) async {
    final q = query.trim();
    final where = StringBuffer('listing.sold = ?');
    final args = <Object?>[sold ? 1 : 0];
    if (q.isNotEmpty) {
      // "#LF047", "lf047", "#TR047" from before a rename, or plain "047" —
      // anything code-shaped also tries the row id, ALONGSIDE the text search
      // rather than instead of it: "2018" is both a plausible code and a
      // plausible model year, and the searcher should not have to know which
      // the database thinks it is.
      final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
      final codeId =
          RegExp(r'^#?[a-z]{0,3}[- ]?\d+$', caseSensitive: false).hasMatch(q)
          ? int.tryParse(digits)
          : null;
      final clauses = <String>[
        "listing.title LIKE ? ESCAPE '\\'",
        "listing.body LIKE ? ESCAPE '\\'",
        "c.name LIKE ? ESCAPE '\\'",
        "listing.source_text LIKE ? ESCAPE '\\'",
      ];
      final like = '%${_escapeLike(q)}%';
      args.addAll([like, like, like, like]);
      if (codeId != null) {
        clauses.add('listing.id = ?');
        args.add(codeId);
      }
      where.write(' AND (${clauses.join(' OR ')})');
    }
    final rows = await db.rawQuery('''
      SELECT listing.*, c.name AS source_name, c.phone_local AS source_phone
      FROM listing LEFT JOIN contact c ON c.id = listing.source_contact_id
      WHERE $where
      ORDER BY listing.created_at DESC, listing.id DESC
    ''', args);
    return rows.map(Listing.fromRow).toList();
  }

  Future<Listing?> listingById(int id) async {
    final rows = await db.rawQuery(
      '''
      SELECT listing.*, c.name AS source_name, c.phone_local AS source_phone
      FROM listing LEFT JOIN contact c ON c.id = listing.source_contact_id
      WHERE listing.id = ?
    ''',
      [id],
    );
    return rows.isEmpty ? null : Listing.fromRow(rows.first);
  }

  /// Files a shared-in listing. Returns its id — which is its public code.
  Future<int> saveListing({
    int? id,
    required String title,
    String body = '',
    int? sourceContactId,
    String? sourceText,
    List<String> photos = const [],
  }) async {
    final values = {
      'title': title.trim(),
      'body': body.trim(),
      'source_contact_id': sourceContactId,
      'source_text': (sourceText == null || sourceText.trim().isEmpty)
          ? null
          : sourceText.trim(),
      'photos': jsonEncode(photos),
    };
    if (id != null) {
      await db.update('listing', values, where: 'id = ?', whereArgs: [id]);
      return id;
    }
    return db.insert('listing', {
      ...values,
      'sold': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> setListingSold(int id, bool sold) => db.update(
    'listing',
    {
      'sold': sold ? 1 : 0,
      'sold_at': sold ? DateTime.now().millisecondsSinceEpoch : null,
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  /// The row only; the caller owns deleting the photo files, because the
  /// repository has no business touching the filesystem.
  Future<void> deleteListing(int id) =>
      db.delete('listing', where: 'id = ?', whereArgs: [id]);

  /// A quick name/number lookup for "who sent this?" pickers.
  Future<List<Contact>> quickContactLookup(
    String query, {
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final like = '%${_escapeLike(q)}%';
    final rows = await db.query(
      'contact',
      where:
          "name LIKE ? ESCAPE '\\' OR phone_local LIKE ? ESCAPE '\\' "
          "OR phone_e164 LIKE ? ESCAPE '\\'",
      whereArgs: [like, like, like],
      orderBy: 'name IS NULL, name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(Contact.fromRow).toList();
  }

  // ----------------------------------------------------- other messengers

  /// The feed: what arrived in the watched messengers, newest first.
  Future<List<ChatMessage>> chatMessages({int limit = 300}) async {
    final rows = await db.rawQuery(
      '''
      SELECT m.*, c.name AS contact_name
      FROM chat_message m LEFT JOIN contact c ON c.id = m.contact_id
      ORDER BY m.at DESC, m.id DESC
      LIMIT ?
    ''',
      [limit],
    );
    return rows.map(ChatMessage.fromRow).toList();
  }

  Future<int> unseenChatCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM chat_message WHERE seen = 0'),
      ) ??
      0;

  /// The apps with something unseen, busiest first — the dashboard shows
  /// their icons rather than naming them.
  Future<List<String>> unseenChatApps() async {
    final rows = await db.rawQuery(
      'SELECT app, COUNT(*) AS n FROM chat_message WHERE seen = 0 '
      'GROUP BY app ORDER BY n DESC',
    );
    return rows.map((r) => r['app'] as String).toList();
  }

  Future<void> markChatsSeen() =>
      db.rawUpdate('UPDATE chat_message SET seen = 1 WHERE seen = 0');

  /// Teaches the app that a messenger name is a person it already knows, and
  /// applies it backwards over everything that name has already said — so a
  /// link made today does not leave yesterday's messages orphaned.
  Future<void> linkChatSender({
    required String app,
    required String sender,
    required int contactId,
  }) async {
    await db.rawInsert(
      'INSERT OR REPLACE INTO chat_link(app, sender, contact_id) '
      'VALUES(?, ?, ?)',
      [app, sender, contactId],
    );
    await db.update(
      'chat_message',
      {'contact_id': contactId},
      where: 'app = ? AND sender = ?',
      whereArgs: [app, sender],
    );
    // Their last message is as good a "we talked" stamp as any.
    final latest = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT MAX(at) FROM chat_message WHERE app = ? AND sender = ?',
        [app, sender],
      ),
    );
    if (latest != null && latest > 0) await touchContact(contactId, latest);
  }

  /// Forgets everything read from other apps. The privacy escape hatch: one
  /// tap and nothing captured remains.
  Future<void> clearChatMessages() => db.delete('chat_message');

  // ----------------------------------------------------------------------- tags

  /// Every tag, with how many people wear it.
  Future<List<Tag>> tags() async {
    final rows = await db.rawQuery('''
      SELECT t.id, t.name, COUNT(ct.contact_id) AS count
      FROM tag t LEFT JOIN contact_tag ct ON ct.tag_id = t.id
      GROUP BY t.id, t.name
      ORDER BY t.name COLLATE NOCASE
    ''');
    return rows.map(Tag.fromRow).toList();
  }

  /// Finds or creates a tag by name — "Buyer" and "buyer" are the same tag.
  /// Returns null for a blank name.
  Future<int?> ensureTag(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final existing = await db.query(
      'tag',
      columns: ['id'],
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [trimmed],
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return db.insert('tag', {
      'name': trimmed,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Deletes the tag itself and takes it off everyone wearing it.
  Future<void> deleteTag(int id) => db.transaction((txn) async {
    await txn.delete('contact_tag', where: 'tag_id = ?', whereArgs: [id]);
    await txn.delete('tag', where: 'id = ?', whereArgs: [id]);
  });

  Future<List<Tag>> tagsForContact(int contactId) async {
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.name, 0 AS count
      FROM contact_tag ct JOIN tag t ON t.id = ct.tag_id
      WHERE ct.contact_id = ?
      ORDER BY t.name COLLATE NOCASE
    ''',
      [contactId],
    );
    return rows.map(Tag.fromRow).toList();
  }

  Future<void> setContactTag(int contactId, int tagId, bool on) async {
    if (on) {
      await db.rawInsert(
        'INSERT OR IGNORE INTO contact_tag(contact_id, tag_id) VALUES(?, ?)',
        [contactId, tagId],
      );
    } else {
      await db.delete(
        'contact_tag',
        where: 'contact_id = ? AND tag_id = ?',
        whereArgs: [contactId, tagId],
      );
    }
  }

  /// The ids of everyone wearing [tagId] — a campaign audience.
  Future<List<int>> contactIdsWithTag(int tagId) async {
    final rows = await db.query(
      'contact_tag',
      columns: ['contact_id'],
      where: 'tag_id = ?',
      whereArgs: [tagId],
    );
    return rows.map((r) => r['contact_id'] as int).toList();
  }

  // -------------------------------------------------------------- licensing

  /// Where this installation stands: trial, active, or expired.
  ///
  /// Also does the bookkeeping a check needs anyway — mints the installation
  /// code on first call, starts the trial clock, and refuses to let the
  /// phone's clock run backwards (the stored "latest moment ever seen" wins,
  /// so winding the date back cannot resurrect an expired subscription).
  Future<LicenseStatus> licenseStatus() async {
    var install = await getSetting(SettingKeys.installCode, '');
    if (install.isEmpty) {
      install = License.newInstallCode();
      await setSetting(SettingKeys.installCode, install);
    }
    var firstRun = await getSettingInt(SettingKeys.firstRunAt, 0);
    if (firstRun == 0) {
      firstRun = DateTime.now().millisecondsSinceEpoch;
      await setSetting(SettingKeys.firstRunAt, firstRun.toString());
    }

    final lastSeen = await getSettingInt(SettingKeys.licenseLastSeen, 0);
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveNow = now > lastSeen ? now : lastSeen;
    if (effectiveNow != lastSeen) {
      await setSetting(SettingKeys.licenseLastSeen, effectiveNow.toString());
    }

    final expiresAt = await getSettingInt(SettingKeys.licenseExpiresAt, 0);
    final trialEnd = firstRun + Selling.trialDays * Duration.millisecondsPerDay;

    if (effectiveNow < expiresAt) {
      return LicenseStatus(
        phase: LicensePhase.active,
        installCode: install,
        until: expiresAt,
      );
    }
    if (expiresAt == 0 && effectiveNow < trialEnd) {
      return LicenseStatus(
        phase: LicensePhase.trial,
        installCode: install,
        until: trialEnd,
      );
    }
    return LicenseStatus(
      phase: LicensePhase.expired,
      installCode: install,
      until: 0,
    );
  }

  /// Redeems a pasted activation code. Returns null on success, or the
  /// sentence to show the user.
  Future<String?> redeemCode(String raw) async {
    if (raw.trim().isEmpty) return 'Paste the activation code first.';
    final install = await getSetting(SettingKeys.installCode, '');
    final parsed = License.verify(raw, install);
    if (parsed == null) {
      return 'That code is not valid for this phone. Check that you sent '
          'this phone\'s own code ($install) when you paid.';
    }
    final used = await db.query(
      'redeemed_code',
      where: 'nonce = ?',
      whereArgs: [parsed.nonce],
    );
    if (used.isNotEmpty) return 'That code has already been used.';

    final now = DateTime.now().millisecondsSinceEpoch;
    final current = await getSettingInt(SettingKeys.licenseExpiresAt, 0);
    // Renewing early must not waste the days already paid for.
    final base = current > now ? current : now;
    final newExpiry = base + parsed.days * Duration.millisecondsPerDay;

    await db.insert('redeemed_code', {
      'nonce': parsed.nonce,
      'days': parsed.days,
      'redeemed_at': now,
    });
    await setSetting(SettingKeys.licenseExpiresAt, newExpiry.toString());
    return null;
  }

  /// Seller side: remember a code that was issued, so renewals can be seen
  /// coming. Purely a notebook — the code itself is its own authority.
  Future<void> recordIssuedLicense({
    required String installCode,
    required int days,
    String? note,
  }) => db.insert('issued_license', {
    'install_code': License.normalize(installCode),
    'days': days,
    'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    'issued_at': DateTime.now().millisecondsSinceEpoch,
  });

  Future<List<Map<String, Object?>>> issuedLicenses() =>
      db.query('issued_license', orderBy: 'issued_at DESC');

  /// Fills a batch with everyone wearing a tag — "message all the car
  /// buyers" as one tap. Each person goes through [moveContactToBatch], so
  /// the usual rules hold: the already-reached stay where their story
  /// happened, and no one lands in a batch twice.
  Future<({int moved, int skipped})> addTagToBatch(
    int batchId,
    int tagId,
  ) async {
    var moved = 0;
    var skipped = 0;
    for (final id in await contactIdsWithTag(tagId)) {
      if (await moveContactToBatch(id, batchId)) {
        moved++;
      } else {
        skipped++;
      }
    }
    return (moved: moved, skipped: skipped);
  }

  /// Is this file actually one of our backups?
  ///
  /// Restore replaces the live database, so picking the wrong file in the
  /// document picker used to destroy every contact with no way back — and the
  /// app would not start afterwards, because what it opened was not a schema it
  /// recognised. Opening the candidate read-only first and looking for our own
  /// tables costs nothing and turns a catastrophe into a sentence.
  /// Folds the write-ahead log back into the database file.
  ///
  /// A backup copies that one file. SQLite keeps recent writes in a `-wal`
  /// sidecar, so without this the last few sends would be missing from the
  /// copy — silently, which is the worst way for a backup to be wrong.
  Future<void> checkpoint() async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode, or the checkpoint was blocked. The copy is still
      // usable; refusing to back up over this would be the worse trade.
    }
  }

  static Future<String?> describeBackup(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final resolved = factory ?? databaseFactory;
    Database? candidate;
    try {
      candidate = await resolved.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final tables = (await candidate.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name'] as String? ?? '').toSet();

      for (final required in ['contact', 'batch', 'message', 'settings']) {
        if (!tables.contains(required)) {
          return 'That file is not a LeadForce backup.';
        }
      }

      final contacts =
          Sqflite.firstIntValue(
            await candidate.rawQuery('SELECT COUNT(*) FROM contact'),
          ) ??
          0;
      final messages =
          Sqflite.firstIntValue(
            await candidate.rawQuery('SELECT COUNT(*) FROM message'),
          ) ??
          0;
      return 'ok:$contacts:$messages';
    } catch (_) {
      return 'That file could not be opened as a backup.';
    } finally {
      await candidate?.close();
    }
  }

  // ------------------------------------------------------------------ export

  /// One row per contact with its current status (spec 11).
  Future<String> contactsCsv() async {
    final rows = await db.rawQuery('''
      SELECT c.phone_e164, c.phone_local, c.name, c.source, c.status, c.attempts,
             c.last_sent_at, c.last_error, b.name AS batch_name
      FROM contact c LEFT JOIN batch b ON b.id = c.batch_id
      WHERE c.is_campaign = 1
      ORDER BY c.id
    ''');
    final buffer = StringBuffer()
      ..writeln(
        'phone_e164,phone_local,name,source,status,batch,attempts,last_sent_at,last_error',
      );
    for (final r in rows) {
      buffer.writeln(
        [
          r['phone_e164'],
          r['phone_local'],
          r['name'],
          r['source'],
          r['status'],
          r['batch_name'],
          r['attempts'],
          r['last_sent_at'] == null
              ? ''
              : DateTime.fromMillisecondsSinceEpoch(
                  r['last_sent_at'] as int,
                ).toIso8601String(),
          r['last_error'],
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  static String _csvCell(Object? value) {
    if (value == null) return '';
    final s = value.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
