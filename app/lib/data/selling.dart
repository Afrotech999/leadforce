/// Everything about selling LeadForce, in one file, so changing a price or a
/// payment number is a one-line edit and a rebuild.
///
/// These are BAKED INTO THE APK on purpose: a buyer's phone has no server to
/// ask, so whatever is written here is what their Subscribe screen shows.
/// Changing anything below only reaches buyers through the next APK.
class Selling {
  /// Days of full app, free, from first open. Long enough to feel the CRM
  /// working, short enough that "I'll decide later" arrives this month.
  static const trialDays = 7;

  /// The offer. Label, days granted, price line as it should be printed.
  // PLACEHOLDER PRICES — replace with the real ones and rebuild.
  static const plans = <(String label, int days, String price)>[
    ('1 month', 30, '800 birr'),
    ('3 months', 90, '2,000 birr'),
    ('6 months', 180, '3,500 birr'),
    ('1 year', 365, '6,000 birr'),
  ];

  /// Where the money goes. Shown with copy buttons on the Subscribe screen.
  // PLACEHOLDERS — replace with the real accounts and rebuild.
  static const telebirr = '09xx xxx xxx';
  static const cbeAccount = '1000 xxx xxx xxxx';
  static const accountName = 'Loom Solutions';

  /// Where the payment screenshot and installation code get sent.
  // PLACEHOLDER — the seller's own number.
  static const sellerPhone = '+2519xxxxxxxx';

  /// Signs and verifies activation codes. An offline scheme cannot survive a
  /// determined reverse-engineer (who would simply patch the check out of the
  /// APK, whatever the cryptography); this exists to make codes unforgeable
  /// and unshareable for everyone else, which is the realistic goal.
  static const licenseSecret =
      '8916a4a49ada6432b2a8c257a97ea84dde842ff9bb071313bd82e7ea456f02b5';

  /// SHA-256 of the seller passphrase. The passphrase itself is never stored;
  /// typing it is what opens the seller screen on any install — so it guards
  /// the door, while [licenseSecret] guards the codes.
  static const sellerPassHash =
      '74d4be1fd0669205c4267fc3eeb197e19c5eff816cf4fe20194915ba945a318d';
}
