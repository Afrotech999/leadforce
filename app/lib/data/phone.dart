/// Ethiopian phone normalization.
///
/// Mirrored in `android/.../Phone.kt`, which needs the same rules in a broadcast
/// receiver where no Dart is running. Keep the two in step.
library;

/// Normalizes to E.164 (`+2519XXXXXXXX` / `+2517XXXXXXXX`).
///
/// Strips everything that is not a digit, drops a leading `00251`, `251` or `0`,
/// then requires exactly 9 digits starting with 9 (mobile) or 7 (mobile).
/// Returns null when the input cannot be a valid Ethiopian mobile number.
String? normalizePhone(String? raw) {
  if (raw == null) return null;
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;

  if (digits.startsWith('00251')) {
    digits = digits.substring(5);
  } else if (digits.startsWith('251')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0')) {
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
  }

  if (digits.length != 9) return null;
  final first = digits[0];
  if (first != '9' && first != '7') return null;
  return '+251$digits';
}

/// Why a row could not be normalized — shown on the Needs review screen.
String rejectionReason(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'No phone number';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return 'No digits in "$raw"';

  var core = digits;
  if (core.startsWith('00251')) {
    core = core.substring(5);
  } else if (core.startsWith('251')) {
    core = core.substring(3);
  } else if (core.startsWith('0')) {
    core = core.replaceFirst(RegExp(r'^0+'), '');
  }

  if (core.length != 9) {
    return 'Expected 9 digits after the country code, found ${core.length}';
  }
  return 'Ethiopian mobile numbers start with 9 or 7, this one starts with ${core[0]}';
}

/// Display form: `09XXXXXXXX`.
String localForm(String e164) {
  if (e164.startsWith('+251') && e164.length == 13) {
    return '0${e164.substring(4)}';
  }
  return e164;
}
