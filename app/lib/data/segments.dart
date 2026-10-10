/// SMS segment / cost counting (spec 2.4).
///
/// Any character outside the GSM 7-bit alphabet forces the whole message to UCS-2,
/// which drops a segment from 160 characters to 70. Amharic is entirely outside
/// GSM-7, so an Amharic campaign costs more than twice as many segments as the same
/// message in English. The compose screen has to say so before the user sends 6,783
/// of them.
library;

const String _gsm7Base =
    '@£\$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?'
    '¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';

/// Characters that exist in GSM-7 but cost two septets (escape + char).
const String _gsm7Extended = '^{}\\[~]|€';

final Set<int> _base = _gsm7Base.runes.toSet();
final Set<int> _extended = _gsm7Extended.runes.toSet();

enum SmsEncoding { gsm7, ucs2 }

class SegmentInfo {
  const SegmentInfo({
    required this.encoding,
    required this.units,
    required this.segments,
    required this.unitsPerSegment,
    required this.remainingInSegment,
    required this.nonGsmSample,
  });

  final SmsEncoding encoding;

  /// Septets for GSM-7, UTF-16 code units for UCS-2.
  final int units;
  final int segments;
  final int unitsPerSegment;
  final int remainingInSegment;

  /// First character that forced UCS-2, for the warning text. Empty when GSM-7.
  final String nonGsmSample;

  bool get isUnicode => encoding == SmsEncoding.ucs2;

  String get encodingLabel => isUnicode ? 'Unicode (UCS-2)' : 'GSM-7';
}

SegmentInfo countSegments(String body) {
  var septets = 0;
  var unicode = false;
  var sample = '';

  for (final rune in body.runes) {
    if (_base.contains(rune)) {
      septets += 1;
    } else if (_extended.contains(rune)) {
      septets += 2;
    } else {
      unicode = true;
      if (sample.isEmpty) sample = String.fromCharCode(rune);
      break;
    }
  }

  if (unicode) {
    // UCS-2 bills per UTF-16 code unit, so an emoji (surrogate pair) costs two.
    final units = body.length;
    const single = 70;
    const multi = 67;
    final segments = units <= single ? 1 : (units / multi).ceil();
    final perSegment = units <= single ? single : multi;
    return SegmentInfo(
      encoding: SmsEncoding.ucs2,
      units: units,
      segments: segments == 0 ? 1 : segments,
      unitsPerSegment: perSegment,
      remainingInSegment: (perSegment * (segments == 0 ? 1 : segments)) - units,
      nonGsmSample: sample,
    );
  }

  const single = 160;
  const multi = 153;
  final segments = septets <= single ? 1 : (septets / multi).ceil();
  final perSegment = septets <= single ? single : multi;
  return SegmentInfo(
    encoding: SmsEncoding.gsm7,
    units: septets,
    segments: segments == 0 ? 1 : segments,
    unitsPerSegment: perSegment,
    remainingInSegment: (perSegment * (segments == 0 ? 1 : segments)) - septets,
    nonGsmSample: '',
  );
}

/// Fills `{name}`, falling back for nameless contacts, then tidies the punctuation
/// a blank fallback would strand ("Hello ," -> "Hello,").
///
/// Must match `SendService.render` in Kotlin — that is the copy that actually sends.
String renderTemplate(String template, String? name, String fallback) {
  final value = (name == null || name.trim().isEmpty) ? fallback : name.trim();
  return template
      .replaceAll('{name}', value)
      .replaceAllMapped(RegExp(r'\s+([,.!?])'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
}
