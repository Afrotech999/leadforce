import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';

/// One quiet line on Home when replies would not reach this app (spec 9.2).
///
/// This used to be a card in either direction, and the loud one — "still your
/// default SMS app" — sat on the dashboard for as long as the role was held,
/// which is most of the time somebody is using this app. A warning that is
/// always there is furniture, not a warning.
///
/// So the dashboard now carries one thing: a small nudge when the app is *not*
/// the default and replies would go elsewhere. Switching back lives in Settings,
/// next to the state it changes, and the Sending screen still asks at the end of
/// a batch — which is the moment it actually matters.
class DefaultSmsBanner extends ConsumerWidget {
  const DefaultSmsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(defaultSmsProvider);

    return info.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (d) {
        if (d.isDefault) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: AppColors.infoSoft,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () async {
                  await SmsChannel.requestDefaultRole();
                  bumpRefresh(ref);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.messageSquare,
                        size: 18,
                        color: AppColors.info,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Replies will not arrive here yet',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: AppColors.info,
                          ),
                        ),
                      ),
                      Text(
                        'Switch',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.info,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: AppColors.info,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
