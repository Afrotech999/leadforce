import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'home_screen.dart' show groupDigits;
import 'kit.dart';

/// What your package has actually paid for.
///
/// The app counts people; the operator counts SMS, and the two are not the same
/// number. A message in Amharic is UCS-2, which fits 70 characters instead of
/// 160, so two lines of Amharic is three SMS where two lines of English is one.
/// Everything here is that gap, made visible — including what it costs you per
/// message, which is the figure that explains a bill.
class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(usageProvider);

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: usage.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingState(),
          error: (e, _) =>
              ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
          data: (u) => RefreshIndicator(
            onRefresh: () async => bumpRefresh(ref),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                ScreenHeader(
                  greeting: 'Counted by your operator',
                  title: 'SMS Used',
                  actions: [
                    RoundAction(
                      icon: LucideIcons.sliders,
                      label: 'Sending settings',
                      onPressed: () => _setBundle(context, ref, u.bundle),
                    ),
                  ],
                ),

                _Headline(usage: u),
                const SizedBox(height: 12),

                SectionCard(
                  title: 'Recently',
                  child: Row(
                    children: [
                      Expanded(
                        child: _Period(label: 'Today', value: u.today),
                      ),
                      Expanded(
                        child: _Period(label: '7 days', value: u.week),
                      ),
                      Expanded(
                        child: _Period(label: '30 days', value: u.month),
                      ),
                    ],
                  ),
                ),

                _LanguageCard(usage: u),

                SectionCard(
                  title: 'What this means',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Point(
                        text: u.messages == 0
                            ? 'Nothing has been sent yet, so there is nothing to '
                                  'count.'
                            : 'You have messaged ${groupDigits(u.messages)} '
                                  'people and it cost ${groupDigits(u.segments)} '
                                  'SMS — ${u.costPerMessage.toStringAsFixed(1)} '
                                  'each on average.',
                      ),
                      const _Point(
                        text:
                            'Latin text fits 160 characters in one SMS. '
                            'Amharic fits 70, because a single non-Latin '
                            'character forces the whole message to the wider '
                            'encoding.',
                      ),
                      if (u.amharicMessages > 0 && u.latinMessages > 0)
                        _Point(
                          text:
                              'Yours works out at '
                              '${u.amharicCost.toStringAsFixed(1)} SMS per '
                              'Amharic message against '
                              '${u.latinCost.toStringAsFixed(1)} for Latin.',
                          last: true,
                        )
                      else
                        const _Point(
                          text:
                              'Compose shows the cost of a message before you '
                              'send it, and the daily cap counts SMS rather '
                              'than messages so it means what your balance '
                              'means.',
                          last: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setBundle(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final controller = TextEditingController(
      text: current == 0 ? '' : '$current',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your package'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'How many SMS it holds',
            helperText: 'Leave empty if you are on pay as you go.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    final value = int.tryParse(result.trim()) ?? 0;
    await ref
        .read(repoProvider)
        .setSetting(SettingKeys.bundleSize, '${value < 0 ? 0 : value}');
    bumpRefresh(ref);
  }
}

/// The number, as big as it will go.
class _Headline extends StatelessWidget {
  const _Headline({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    final hasBundle = usage.bundle > 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasBundle ? 'Used from your package' : 'SMS sent, all time',
            style: const TextStyle(fontSize: 13, color: AppColors.onInkMuted),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  groupDigits(usage.segments),
                  style: const TextStyle(
                    fontSize: 68,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -3.4,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasBundle) ...[
                  const SizedBox(width: 10),
                  Text(
                    '/ ${groupDigits(usage.bundle)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -1,
                      color: AppColors.onInkMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (hasBundle) ...[
            ProgressTicks(value: usage.bundleUsed, height: 20, onDark: true),
            const SizedBox(height: 12),
            Text(
              '${groupDigits(usage.remaining)} left',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ] else
            Text(
              'from ${groupDigits(usage.messages)} messages. Tap the dial above '
              'to enter your package size and see what is left.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.onInkMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _Period extends StatelessWidget {
  const _Period({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        groupDigits(value),
        style: const TextStyle(
          fontSize: 26,
          height: 1.1,
          fontWeight: FontWeight.w500,
          letterSpacing: -1,
          color: AppColors.ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
      ),
    ],
  );
}

/// Amharic against Latin, which is the thing worth knowing.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.usage});

  final Usage usage;

  @override
  Widget build(BuildContext context) {
    if (usage.segments == 0) return const SizedBox.shrink();
    final amharic = usage.amharicShare;

    return SectionCard(
      title: 'Where it went',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  // Zero-width flex children are illegal, so a language with
                  // nothing sent simply drops out of the bar.
                  if (amharic > 0)
                    Expanded(
                      flex: (amharic * 1000).round().clamp(1, 1000),
                      child: Container(color: AppColors.ink),
                    ),
                  if (amharic < 1)
                    Expanded(
                      flex: ((1 - amharic) * 1000).round().clamp(1, 1000),
                      child: Container(color: AppColors.accent),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Legend(
            colour: AppColors.ink,
            language: 'Amharic',
            messages: usage.amharicMessages,
            segments: usage.amharicSegments,
            perMessage: usage.amharicCost,
          ),
          const SizedBox(height: 12),
          _Legend(
            colour: AppColors.accent,
            language: 'Latin',
            messages: usage.latinMessages,
            segments: usage.latinSegments,
            perMessage: usage.latinCost,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.colour,
    required this.language,
    required this.messages,
    required this.segments,
    required this.perMessage,
  });

  final Color colour;
  final String language;
  final int messages;
  final int segments;
  final double perMessage;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              language,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            Text(
              messages == 0
                  ? 'nothing sent'
                  : '${groupDigits(messages)} messages · '
                        '${perMessage.toStringAsFixed(1)} SMS each',
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Text(
        groupDigits(segments),
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: AppColors.ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.text, this.last = false});

  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: last ? 0 : 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: AppColors.inkMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.inkMuted,
            ),
          ),
        ),
      ],
    ),
  );
}
