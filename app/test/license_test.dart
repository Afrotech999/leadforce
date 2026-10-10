import 'dart:math';

import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/license.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:campaign_sms/data/selling.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The subscription machinery. Money changes hands over these codes, so every
/// way a code could be wrong — forged, edited, borrowed, replayed — gets a
/// test that proves it is refused, and the honest path gets one that proves
/// it is not.
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

  test('an activation code verifies only as issued', () {
    final install = License.newInstallCode(Random(7));
    final code = License.issue(
      installCode: install,
      days: 90,
      random: Random(8),
    );

    // The honest path, including sloppy pasting.
    expect(License.verify(code, install)?.days, 90);
    expect(License.verify(' ${code.toLowerCase()} ', install)?.days, 90);
    // Loose formatting of the install code half too.
    expect(
      License.verify(code, install.toLowerCase().replaceAll('-', ' ')),
      isNotNull,
    );

    // A friend's phone: same code, different installation.
    final other = License.newInstallCode(Random(9));
    expect(License.verify(code, other), isNull);

    // Editing the duration breaks the signature.
    expect(License.verify(code.replaceFirst('-90-', '-365-'), install), isNull);

    // Garbage is garbage.
    expect(License.verify('AWJ2-90-XXXX-NOTAREALMAC1234', install), isNull);
    expect(License.verify('hello', install), isNull);
    expect(License.verify('', install), isNull);
  });

  test('the seller passphrase opens only for the right words', () {
    expect(License.isSellerPass('kanya-awaj-2118'), isTrue);
    expect(License.isSellerPass('  kanya-awaj-2118  '), isTrue);
    expect(License.isSellerPass('wrong'), isFalse);
    expect(License.isSellerPass(''), isFalse);
  });

  test(
    'trial, activation, stacking and replay behave over a real database',
    () async {
      final r = await repo();

      // First call mints the identity and starts the trial.
      final first = await r.licenseStatus();
      expect(first.phase, LicensePhase.trial);
      expect(first.installCode, startsWith('LF-'));
      expect(first.daysLeft, Selling.trialDays);
      // The identity is stable.
      expect((await r.licenseStatus()).installCode, first.installCode);

      // A real code activates.
      final code = License.issue(installCode: first.installCode, days: 30);
      expect(await r.redeemCode(code), isNull);
      var status = await r.licenseStatus();
      expect(status.phase, LicensePhase.active);
      expect(status.daysLeft, 30);

      // The same code again is refused — paid days cannot be minted twice.
      expect(await r.redeemCode(code), contains('already been used'));

      // A second code stacks on the remaining time instead of replacing it.
      final more = License.issue(installCode: first.installCode, days: 30);
      expect(await r.redeemCode(more), isNull);
      status = await r.licenseStatus();
      expect(status.daysLeft, 60);

      // A code for some other phone is refused with the reason.
      final foreign = License.issue(
        installCode: License.newInstallCode(Random(3)),
        days: 365,
      );
      expect(await r.redeemCode(foreign), contains('not valid for this phone'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'an ended subscription expires, and winding the clock back does not help',
    () async {
      final r = await repo();
      final status = await r.licenseStatus();

      // Time travel: trial started long ago, subscription ended yesterday.
      final now = DateTime.now().millisecondsSinceEpoch;
      await r.setSetting(
        SettingKeys.firstRunAt,
        (now - 40 * Duration.millisecondsPerDay).toString(),
      );
      await r.setSetting(
        SettingKeys.licenseExpiresAt,
        (now - Duration.millisecondsPerDay).toString(),
      );
      expect((await r.licenseStatus()).phase, LicensePhase.expired);

      // The rollback guard: the app has "seen" the future, so a wound-back
      // phone clock cannot resurrect the licence.
      await r.setSetting(
        SettingKeys.licenseLastSeen,
        (now + 400 * Duration.millisecondsPerDay).toString(),
      );
      await r.setSetting(
        SettingKeys.licenseExpiresAt,
        (now + 30 * Duration.millisecondsPerDay).toString(),
      );
      expect(
        (await r.licenseStatus()).phase,
        LicensePhase.expired,
        reason: 'the stored latest-seen moment outranks the phone clock',
      );

      // Renewing from expired starts from today, not from the old expiry.
      await r.setSetting(SettingKeys.licenseLastSeen, '0');
      await r.setSetting(
        SettingKeys.licenseExpiresAt,
        (now - Duration.millisecondsPerDay).toString(),
      );
      final code = License.issue(installCode: status.installCode, days: 30);
      expect(await r.redeemCode(code), isNull);
      expect((await r.licenseStatus()).daysLeft, 30);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
