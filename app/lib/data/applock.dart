import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The screen lock over the whole app.
///
/// This phone gets handed to customers — to look at a car photo, to read a
/// price, to dial a number. Everything in here is somebody's client book, their
/// SMS inbox and, if the chat feed is on, their WhatsApp and Telegram. A four
/// digit code in front of that is the difference between "they saw the photo"
/// and "they saw my list of buyers".
///
/// It is a local lock, not encryption: the database on disk is unchanged and
/// anyone who can root the phone or pull a backup can still read it. What it
/// stops is the person holding the unlocked phone, which is the threat that
/// actually happens.
///
/// The PIN is never stored. What is stored is a salted SHA-256 of it, so
/// somebody reading the settings table learns nothing they can type in.
class AppLock {
  /// A fresh random salt, hex encoded. New on every PIN change, so the same
  /// code set twice does not produce the same hash twice.
  static String newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// The stored form of a PIN. Iterated so that guessing all ten thousand
  /// four-digit codes off a stolen settings row costs real time rather than a
  /// tenth of a second — the codes are short, so the work has to make up for
  /// it.
  static String hash(String pin, String salt) {
    var digest = sha256.convert(
      utf8.encode('leadforce-lock|$salt|${pin.trim()}'),
    );
    for (var i = 0; i < 20000; i++) {
      digest = sha256.convert(utf8.encode('$salt|${digest.toString()}'));
    }
    return digest.toString();
  }

  /// Timing-safe check — a lock screen should not leak how much of a guess was
  /// right, even in principle.
  static bool verify(
    String pin, {
    required String salt,
    required String stored,
  }) {
    if (salt.isEmpty || stored.isEmpty) return false;
    final candidate = hash(pin, salt);
    if (candidate.length != stored.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ stored.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// A PIN has to be four to eight digits. Short enough to type one-handed at
  /// a car window, long enough not to be the first thing guessed.
  static bool looksValid(String pin) =>
      RegExp(r'^\d{4,8}$').hasMatch(pin.trim());

  /// How long a wrong-guess lockout lasts, given how many have been wrong in a
  /// row. Nothing for the first five — fingers slip — then a wait that grows,
  /// capped at five minutes so a locked-out owner is never locked out for the
  /// afternoon.
  static Duration cooldown(int wrongAttempts) {
    if (wrongAttempts < 5) return Duration.zero;
    final steps = wrongAttempts - 4;
    final seconds = min(300, 15 * (1 << min(steps - 1, 5)));
    return Duration(seconds: seconds);
  }
}
