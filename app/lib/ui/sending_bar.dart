import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../theme.dart';
import 'kit.dart';
import 'sending_screen.dart';

/// The now-sending bar: one dark glass line above the footer, on every tab,
/// for as long as a campaign is running.
///
/// Before this, the only live view was the Sending screen itself — leave it to
/// read a reply and the campaign went invisible. This is the music-player
/// pattern: the ongoing thing stays one glance and one tap away everywhere.
class SendingBar extends StatelessWidget {
  const SendingBar({super.key, required this.progress});

  final CampaignProgress progress;

  @override
  Widget build(BuildContext context) {
    final paused = progress.isPaused;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: AppColors.glassInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.card),
              side: const BorderSide(color: AppColors.glassEdgeInk),
            ),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      SendingScreen(campaignId: progress.campaignId),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 11, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      paused ? LucideIcons.pause : LucideIcons.radio,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            paused
                                ? 'Paused — ${progress.batchName}'
                                : 'Sending ${progress.batchName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 7),
                          ProgressTicks(
                            value: progress.fraction,
                            height: 14,
                            onDark: true,
                            showPercent: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${progress.processed} / ${progress.total}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onInkMuted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      LucideIcons.chevronRight,
                      size: 17,
                      color: AppColors.onInkMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
