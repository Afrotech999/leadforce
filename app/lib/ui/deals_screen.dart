import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'contact_notes_screen.dart';
import 'deal_sheet.dart';
import 'kit.dart';

/// The pipeline: every deal, grouped by where it stands.
///
/// Open the app, see the state of the business — who is new, who is booked
/// for a viewing, who is negotiating, and how long each has sat there. Tap
/// the stage chip to move a deal; tap the row to open the person.
class DealsScreen extends ConsumerWidget {
  const DealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(dealsProvider).valueOrNull ?? const <Deal>[];
    final open = [
      for (final d in all)
        if (d.isOpen) d,
    ];
    final closed = [
      for (final d in all)
        if (!d.isOpen) d,
    ];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Your Pipeline',
              subtitle:
                  'Tap the stage to move a deal · tap the row for the person',
            ),
            Expanded(
              child: all.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.handshake,
                      title: 'No deals yet',
                      message:
                          'Open somebody\'s profile — from a conversation or '
                          'a call — and tap "Start a deal". It shows up here, '
                          'moving through stages until it is won.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      children: [
                        for (final stage in DealStage.open)
                          if (open.any((d) => d.stage == stage)) ...[
                            _StageLabel(stage: stage),
                            for (final d in open)
                              if (d.stage == stage) _DealRow(deal: d),
                          ],
                        if (closed.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                            child: Text(
                              'Closed',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                          for (final d in closed.take(20)) _DealRow(deal: d),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel({required this.stage});

  final String stage;

  @override
  Widget build(BuildContext context) {
    final (bg, _) = stageTint(stage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: stage == DealStage.newLead ? AppColors.muted : bg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            DealStage.label(stage),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DealRow extends ConsumerWidget {
  const _DealRow({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = deal;
    final price = birr(d.price);
    final days = d.daysInStage;
    final stuck = d.isOpen && days >= 14;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.glassEdge),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              children: [
                ContactAvatar(label: d.who, radius: 19),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          d.what,
                          if (price.isNotEmpty) price,
                          if (d.isOpen && days > 0)
                            '$days day${days == 1 ? '' : 's'}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          // A fortnight without moving is worth a red tint —
                          // that deal is the one to ring about today.
                          color: stuck ? AppColors.danger : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StageChip(
                  stage: d.stage,
                  onTap: () => showDealStageSheet(context, ref, d),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final c = await ref.read(repoProvider).contactById(deal.contactId);
    if (c == null || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ContactProfileScreen(contact: c)));
    bumpRefresh(ref);
  }
}
