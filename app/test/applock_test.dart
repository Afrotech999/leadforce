import 'package:campaign_sms/data/applock.dart';
import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The lock in front of the app.
///
/// The phone gets handed to customers, so this is the wall between "they saw
/// the car photo" and "they read my buyer list". Everything a wall has to do —
/// refuse a wrong code, not store the right one, slow down a guesser, and let
/// the owner back in — gets a test.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<Repo> repo() async {
    final db = await openCampaignDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    return Repo(db);
  }

  test('a PIN is never stored, and only the right one opens it', () async {
    final r = await repo();
    expect(await r.lockIsSet(), isFalse, reason: 'ships unlocked');

    await r.setLockPin('4821');
    expect(await r.lockIsSet(), isTrue);

    // What is on disk must not be the code, or the settings table is the
    // keyhole.
    final stored = await r.getSetting(SettingKeys.lockHash, '');
    expect(stored, isNotEmpty);
    expect(stored, isNot(contains('4821')));
    expect(await r.getSetting(SettingKeys.lockSalt, ''), isNotEmpty);

    expect(await r.checkLockPin('4821'), isTrue);
    expect(await r.checkLockPin('4822'), isFalse);
    expect(await r.checkLockPin(''), isFalse);
  });

  test('the same code set twice hashes differently', () async {
    final r = await repo();
    await r.setLockPin('1234');
    final first = await r.getSetting(SettingKeys.lockHash, '');
    await r.setLockPin('1234');
    final second = await r.getSetting(SettingKeys.lockHash, '');
    // A fresh salt each time, so two phones with the same code — or one phone
    // that reset to the same code — do not share a hash.
    expect(first, isNot(second));
    expect(await r.checkLockPin('1234'), isTrue);
  });

  test(
    'wrong guesses pile up into a wait, and the right one clears it',
    () async {
      final r = await repo();
      await r.setLockPin('4821');

      // The first few cost nothing: fingers slip on a keypad in the sun.
      for (var i = 0; i < 4; i++) {
        expect(await r.checkLockPin('0000'), isFalse);
      }
      expect(await r.lockCooldownLeft(), Duration.zero);

      // The fifth starts the wait.
      expect(await r.checkLockPin('0000'), isFalse);
      final wait = await r.lockCooldownLeft();
      expect(wait, greaterThan(Duration.zero));
      expect(wait, lessThanOrEqualTo(const Duration(minutes: 5)));

      // It grows.
      expect(await r.checkLockPin('0000'), isFalse);
      expect(await r.lockCooldownLeft(), greaterThan(wait));

      // And the owner getting in wipes it — the next wrong guess starts over.
      expect(await r.checkLockPin('4821'), isTrue);
      expect(await r.lockCooldownLeft(), Duration.zero);
      expect(await r.getSetting(SettingKeys.lockWrongCount, '?'), '0');
    },
  );

  test('a cooldown survives the app being killed, but is never absurd', () async {
    final r = await repo();
    await r.setLockPin('4821');
    for (var i = 0; i < 6; i++) {
      await r.checkLockPin('0000');
    }
    // Stored as a moment, not a running timer, so force-quitting does not
    // shorten it. Reading it again — as a fresh launch would — still waits.
    expect(await r.lockCooldownLeft(), greaterThan(Duration.zero));

    // A clock wound forward and back could leave a wait years long. Capped.
    await r.setSetting(
      SettingKeys.lockCooldownUntil,
      '${DateTime.now().millisecondsSinceEpoch + Duration.millisecondsPerDay * 400}',
    );
    expect(await r.lockCooldownLeft(), const Duration(minutes: 5));
  });

  test('turning the lock off needs the current code', () async {
    final r = await repo();
    await r.setLockPin('4821');

    expect(await r.clearLockPin('1111'), isFalse);
    expect(await r.lockIsSet(), isTrue, reason: 'a wrong code changes nothing');

    expect(await r.clearLockPin('4821'), isTrue);
    expect(await r.lockIsSet(), isFalse);
    // With no lock set, nothing opens it — not even an empty guess.
    expect(await r.checkLockPin(''), isFalse);
    expect(await r.checkLockPin('4821'), isFalse);
  });

  test('the keypad knows how many digits to draw', () async {
    final r = await repo();
    expect(await r.lockLength(), 4, reason: 'a sane default before any is set');
    await r.setLockPin('123456');
    expect(await r.lockLength(), 6);
    await r.setLockPin('12345678');
    expect(await r.lockLength(), 8);
  });

  test('only four to eight digits count as a code', () {
    expect(AppLock.looksValid('1234'), isTrue);
    expect(AppLock.looksValid('12345678'), isTrue);
    expect(AppLock.looksValid('123'), isFalse);
    expect(AppLock.looksValid('123456789'), isFalse);
    expect(AppLock.looksValid('12a4'), isFalse);
    expect(AppLock.looksValid(''), isFalse);
  });

  test('a backup stamp is what the dashboard reminder reads', () async {
    final r = await repo();
    expect(await r.lastBackupAt(), isNull, reason: 'never backed up');
    await r.markBackedUp();
    final at = await r.lastBackupAt();
    expect(at, isNotNull);
    expect(
      DateTime.now().difference(at!).inMinutes,
      lessThan(1),
      reason: 'stamped now',
    );
  });
}
