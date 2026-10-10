import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../native/sms_channel.dart';
import '../theme.dart';
import 'common.dart';

/// Message text with the useful parts made tappable — links, email addresses
/// and phone numbers.
///
/// Written by hand rather than pulled in with `flutter_linkify`: the whole job
/// is one regex and a span builder, and every plugin added to this project has
/// cost a build fight.
///
/// Stateful because a [TapGestureRecognizer] holds resources that must be
/// disposed. A stateless builder that made recognizers on every rebuild leaked
/// one per frame for as long as the conversation was on screen.
class LinkedText extends StatefulWidget {
  const LinkedText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor,
  });

  final String text;
  final TextStyle style;

  /// Defaults to the text colour, underlined — on an ink bubble a blue link
  /// would be the one thing in the app wearing a stock colour.
  final Color? linkColor;

  @override
  State<LinkedText> createState() => _LinkedTextState();
}

/// URLs, emails, and runs of digits long enough to dial. Ordered by greed:
/// an email inside a URL should not be found first.
final RegExp _pattern = RegExp(
  r'(https?://[^\s]+)'
  r'|(www\.[^\s]+)'
  r'|([\w.+-]+@[\w-]+\.[\w.-]+)'
  r'|(\+?\d[\d\-\s]{6,}\d)',
  caseSensitive: false,
);

class _LinkedTextState extends State<LinkedText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _open(String raw) async {
    final value = raw.trim();
    if (value.contains('@') && !value.startsWith('http')) {
      await SmsChannel.openExternal('mailto:$value');
      return;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      await SmsChannel.openExternal(value);
      return;
    }
    if (value.startsWith('www.')) {
      await SmsChannel.openExternal('https://$value');
      return;
    }
    if (mounted) await _phoneActions(value);
  }

  /// A number in a message could be worth calling, texting or keeping. Guessing
  /// which would be wrong a third of the time, so it asks.
  Future<void> _phoneActions(String number) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NumberSheet(number: number),
    );
    if (action == null) return;
    switch (action) {
      case 'call':
        await SmsChannel.openExternal('tel:$number');
      case 'sms':
        await SmsChannel.openExternal('sms:$number');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: number));
        if (mounted) showSnack(context, 'Number copied.');
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final spans = <InlineSpan>[];
    final linkStyle = widget.style.copyWith(
      color: widget.linkColor ?? widget.style.color,
      decoration: TextDecoration.underline,
      decorationColor: (widget.linkColor ?? widget.style.color)?.withValues(
        alpha: 0.5,
      ),
      fontWeight: FontWeight.w500,
    );

    var last = 0;
    for (final m in _pattern.allMatches(widget.text)) {
      // A "phone number" of three digits with spaces is a price, not a number
      // to dial; the regex floor is deliberately low so this can judge.
      final matched = m[0]!;
      final digits = matched.replaceAll(RegExp(r'\D'), '');
      final isPhone = m[4] != null;
      if (isPhone && digits.length < 9) continue;

      if (m.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, m.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(matched);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(text: matched, style: linkStyle, recognizer: recognizer),
      );
      last = m.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }

    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}

class _NumberSheet extends StatelessWidget {
  const _NumberSheet({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.glassCanvas,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
            child: Text(
              number.trim(),
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: AppColors.ink,
              ),
            ),
          ),
          _Row(
            icon: LucideIcons.phone,
            label: 'Call',
            onTap: () => Navigator.pop(context, 'call'),
          ),
          _Row(
            icon: LucideIcons.messageSquare,
            label: 'Send a message',
            onTap: () => Navigator.pop(context, 'sms'),
          ),
          _Row(
            icon: LucideIcons.copy,
            label: 'Copy number',
            onTap: () => Navigator.pop(context, 'copy'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.ink),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
          ),
        ],
      ),
    ),
  );
}
