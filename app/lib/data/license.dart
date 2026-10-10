import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'selling.dart';

/// The offline subscription machinery.
///
/// There is no server, so "has this person paid?" is answered by a signed
/// code instead: each install invents an installation code, the buyer sends
/// it with their payment screenshot, and the seller answers with an
/// activation code — an HMAC over (installation code, days, nonce) that only
/// verifies on the phone it was issued for. Sharing a code with a friend
/// does nothing; editing the duration breaks the signature; pasting the same
/// code twice is caught by the stored nonce.
///
/// Everything here is pure computation. Storage and policy live in the
/// repository, which is also what the tests drive.
class License {
  /// No I/L/O/0/1: these codes get read aloud over bad phone lines.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// A fresh installation code: `LF-XXXXX-XXXXX`.
  static String newInstallCode([Random? random]) {
    final rng = random ?? Random.secure();
    final chars = List.generate(
      10,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
    return 'LF-${chars.substring(0, 5)}-${chars.substring(5)}';
  }

  /// Uppercases and strips everything that is not part of the identity, so
  /// `lf 7k2m9 dq4xx` and `LF-7K2M9-DQ4XX` are the same code.
  static String normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z2-9]'), '');

  /// The seller side: mint an activation code for one installation.
  /// `LF2-<days>-<nonce>-<mac>`, e.g. `LF2-90-K7QM-ABCDEFGHJKMNPQRS`.
  static String issue({
    required String installCode,
    required int days,
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final nonce = List.generate(
      4,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
    final mac = _mac(installCode, days, nonce);
    return 'LF2-$days-$nonce-$mac';
  }

  /// The buyer side: does this code belong to this installation? Returns the
  /// granted days and the nonce (for replay protection), or null.
  static ({int days, String nonce})? verify(String raw, String installCode) {
    final parts = raw.trim().toUpperCase().split(RegExp(r'[^A-Z0-9]+'))
      ..removeWhere((p) => p.isEmpty);
    // TRV2 and AWJ2 are earlier names' prefixes, still honoured: a code
    // sitting in a chat from before a rename must not stop working because
    // the app changed its mind about what it is called.
    const known = {'LF2', 'TRV2', 'AWJ2'};
    if (parts.length != 4 || !known.contains(parts[0])) return null;
    final days = int.tryParse(parts[1]);
    final nonce = parts[2];
    final mac = parts[3];
    if (days == null || days <= 0 || days > 3660) return null;
    if (nonce.length != 4) return null;
    if (!_constantTimeEquals(mac, _mac(installCode, days, nonce))) return null;
    return (days: days, nonce: nonce);
  }

  static String _mac(String installCode, int days, String nonce) {
    final key = utf8.encode(Selling.licenseSecret);
    final message = utf8.encode(
      // Deliberately still the old name: this string is the signature's
      // domain separator, so changing it would invalidate every code ever
      // issued and every code in flight. Nobody sees it; the name on the
      // screen is what matters.
      'awaj-license|${normalize(installCode)}|$days|$nonce',
    );
    final digest = Hmac(sha256, key).convert(message).bytes;
    // 80 bits of MAC, printed in the code alphabet: comfortably unguessable,
    // short enough to survive being typed if pasting ever fails. The modulo
    // (the alphabet is 31 characters, a 5-bit group is 0..31) costs a
    // whisker of uniformity, which a MAC does not care about — it only has
    // to be deterministic and unguessable.
    final out = StringBuffer();
    var acc = 0;
    var bits = 0;
    for (final byte in digest.take(10)) {
      acc = (acc << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[((acc >> bits) & 31) % _alphabet.length]);
      }
    }
    return out.toString();
  }

  /// Timing-safe comparison — a code check should not leak how close a
  /// guess got, even in principle.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Is this passphrase the seller's? Checked against a baked-in hash, so
  /// the passphrase itself lives in exactly one head.
  static bool isSellerPass(String passphrase) =>
      sha256.convert(utf8.encode(passphrase.trim())).toString() ==
      Selling.sellerPassHash;
}

/// Where one installation stands, computed by the repository on demand.
enum LicensePhase { trial, active, expired }

class LicenseStatus {
  const LicenseStatus({
    required this.phase,
    required this.installCode,
    required this.until,
  });

  final LicensePhase phase;
  final String installCode;

  /// When the current phase runs out (trial end or subscription end).
  /// Meaningless for [LicensePhase.expired].
  final int until;

  bool get usable => phase != LicensePhase.expired;

  /// Whole days remaining, rounded up — "ends today" is day 0.
  int get daysLeft {
    final ms = until - DateTime.now().millisecondsSinceEpoch;
    if (ms <= 0) return 0;
    return (ms + Duration.millisecondsPerDay - 1) ~/
        Duration.millisecondsPerDay;
  }
}
