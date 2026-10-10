import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';
import 'thread_screen.dart';

/// Live view of the running batch (spec 10.3).
///
/// The numbers come from the database, which the native foreground service
/// writes to as it goes — so this screen is accurate whether or not it has
/// been open, and closing it does not stop anything.
///
/// This was the last screen wearing stock Material — default AppBar, default
/// Card, default buttons — and it is the screen the user stares at for the
/// best part of an hour. It speaks the app's language now: glass card, accent
/// ring, ink and glass pills for the two controls.
class SendingScreen extends ConsumerWidget {
  const SendingScreen({super.key, required this.campaignId});

  final int campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignProvider(campaignId));

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(title: 'Sending'),
            Expanded(
              child: async.when(
                skipLoadingOnReload: true,
                loading: () => const LoadingState(),
                error: (e, _) => ErrorState(error: e),
                data: (progress) {
                  if (progress == null) {
                    return const EmptyState(
                      icon: LucideIcons.helpCircle,
                      title: 'Campaign not found',
                      message: 'It may have been removed.',
                    );
                  }
                  return _Body(progress: progress);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.progress});

  final CampaignProgress progress;

  bool get _finished =>
      progress.engineState == 'idle' && progress.remaining == 0;

  bool get _stoppedEarly =>
      progress.engineState == 'idle' && progress.remaining > 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassEdge),
          ),
          child: Column(
            children: [
              Text(
                progress.batchName,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _statusLine,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 22),
              _Ring(progress: progress),
              const SizedBox(height: 24),
              // Four tallies with four-figure numbers under them do not fit a
              // narrow phone in one row; the last pair wraps rather than
              // running off the card.
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 26,
                runSpacing: 14,
                children: [
                  _Tally(
                    label: 'Sent',
                    value: progress.sent,
                    color: AppColors.ink,
                  ),
                  _Tally(
                    label: 'Delivered',
                    value: progress.delivered,
                    color: AppColors.info,
                  ),
                  _Tally(
                    label: 'Failed',
                    value: progress.failed,
                    color: AppColors.danger,
                  ),
                  _Tally(
                    label: 'Replied',
                    value: progress.replied,
                    color: AppColors.ink,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (progress.engineState != 'idle') _Controls(progress: progress),
        if (_finished || _stoppedEarly) _FinishedCard(progress: progress),
        const SizedBox(height: 18),
        _LiveList(batchId: progress.batchId),
      ],
    );
  }

  String get _statusLine => switch (progress.engineState) {
    'running' => 'Sending — keep the phone on and in signal',
    'paused' => 'Paused',
    _ when _finished => 'Finished',
    _ when _stoppedEarly => 'Stopped — ${progress.remaining} still unsent',
    _ => 'Idle',
  };
}

/// The ring: ink arc on a ghost track, eased between polls, with the bold
/// count in the middle. The arc was the accent once — but with a periwinkle
/// accent on a periwinkle track, eleven of a hundred read as a ring that was
/// not moving at all. Progress needs the darkest colour the palette has.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final CampaignProgress progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          height: 150,
          width: 150,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress.fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 11,
              strokeCap: StrokeCap.round,
              color: AppColors.ink,
              backgroundColor: AppColors.ghost,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${progress.processed}',
              style: const TextStyle(
                fontSize: 44,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'of ${progress.total}',
              style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: TextStyle(
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
      ),
    ],
  );
}

/// A pill in the app's own two voices: ink for the primary, glass for the
/// quiet one. The stock tonal/outlined pair was the last of the default
/// button chrome anywhere in the app.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? AppColors.ink : AppColors.glass,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      side: BorderSide(
        color: primary ? Colors.transparent : AppColors.glassEdge,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: primary ? Colors.white : AppColors.ink),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: primary ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.progress});

  final CampaignProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _Pill(
            primary: true,
            icon: progress.isPaused ? LucideIcons.play : LucideIcons.pause,
            label: progress.isPaused ? 'Resume' : 'Pause',
            onTap: () async {
              if (progress.isPaused) {
                await SmsChannel.resumeCampaign();
              } else {
                await SmsChannel.pauseCampaign();
              }
              bumpRefresh(ref);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Pill(
            icon: LucideIcons.square,
            label: 'Stop',
            onTap: () => _confirmStop(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this batch?'),
        content: Text(
          '${progress.remaining} contacts have not been messaged yet. They stay unsent '
          'and will be picked up the next time you run this batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SmsChannel.stopCampaign();
    await ref
        .read(repoProvider)
        .markCampaignStopped(progress.campaignId, progress.batchId);
    bumpRefresh(ref);
  }
}

/// The unmissable end-of-campaign reminder (spec 9.2 step 4), and the two
/// things worth doing right after a batch: back it up, retry the failures.
class _FinishedCard extends ConsumerWidget {
  const _FinishedCard({required this.progress});

  final CampaignProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(defaultSmsProvider).valueOrNull;

    return Column(
      children: [
        if (info != null && info.isDefault) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 18,
                      color: AppColors.danger,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Switch your default SMS app back',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Until you do, every personal text and bank OTP arrives in '
                  'this app instead of ${info.previousLabel ?? 'your usual Messages app'}.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.danger,
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: () async {
                      await SmsChannel.restoreDefaultRole(info.previousPackage);
                      bumpRefresh(ref);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Center(
                        child: Text(
                          info.previousLabel == null
                              ? 'Switch back'
                              : 'Switch back to ${info.previousLabel}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassEdge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _ActionRow(
                icon: LucideIcons.uploadCloud,
                title: 'Back up now',
                hint: 'to Documents/LeadForce',
                onTap: () => _backup(context, ref),
              ),
              if (progress.failed > 0) ...[
                const Divider(height: 1, indent: 18, endIndent: 18),
                _ActionRow(
                  icon: LucideIcons.refreshCw,
                  title: 'Retry ${progress.failed} failed',
                  hint: 'puts them back in the batch for another attempt',
                  onTap: () async {
                    final n = await ref
                        .read(repoProvider)
                        .retryFailed(batchId: progress.batchId);
                    bumpRefresh(ref);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      n == 0
                          ? 'Nothing to retry — all failures have used up their attempts.'
                          : '$n contacts requeued.',
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(repoProvider);
      final csv = await repo.contactsCsv();
      await repo.checkpoint();
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final files = await SmsChannel.exportBackup(csv: csv, stamp: stamp);
      if (!context.mounted) return;
      showSnack(context, 'Saved to ${files.join(', ')}');
    } catch (e) {
      if (!context.mounted) return;
      showSnack(context, 'Backup failed: $e', error: true);
    }
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.ink),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 19,
            color: AppColors.inkMuted,
          ),
        ],
      ),
    ),
  );
}

/// Every contact in the batch, live, under the summary — so "72 of 84" has
/// names on it. Sorted by what deserves attention: the one being sent right
/// now, then failures (each with its own retry), then what has gone out,
/// newest first, then the queue still waiting.
class _LiveList extends ConsumerWidget {
  const _LiveList({required this.batchId});

  final int batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveBatchContactsProvider(batchId));
    final list = async.valueOrNull;
    if (list == null || list.isEmpty) return const SizedBox.shrink();

    int rank(Contact c) => switch (c.status) {
      ContactStatus.queued => 0,
      ContactStatus.failed => 1,
      ContactStatus.replied => 2,
      ContactStatus.delivered => 2,
      ContactStatus.sent => 2,
      ContactStatus.notSent => 3,
      _ => 4,
    };
    final sorted = [...list]
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        // Within "gone out", newest activity first; the waiting queue keeps
        // its sending order.
        if (rank(a) == 2) {
          return (b.lastSentAt ?? 0).compareTo(a.lastSentAt ?? 0);
        }
        return a.id.compareTo(b.id);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'In this batch',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                '${list.length} contacts',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.glassEdge),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < sorted.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
                _LiveRow(contact: sorted[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveRow extends ConsumerWidget {
  const _LiveRow({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = contact;
    final (icon, colour, label) = switch (c.status) {
      ContactStatus.queued => (
        LucideIcons.loader,
        AppColors.ink,
        'Sending now…',
      ),
      ContactStatus.sent => (LucideIcons.check, AppColors.inkMuted, 'Sent'),
      ContactStatus.delivered => (
        LucideIcons.checkCheck,
        AppColors.info,
        'Delivered',
      ),
      ContactStatus.replied => (
        LucideIcons.messageCircle,
        AppColors.info,
        'Replied',
      ),
      ContactStatus.failed => (
        LucideIcons.alertCircle,
        AppColors.danger,
        c.lastError ?? 'Failed',
      ),
      ContactStatus.doNotContact => (
        LucideIcons.ban,
        AppColors.inkMuted,
        'Blocked',
      ),
      _ => (LucideIcons.clock, AppColors.inkMuted, 'Waiting'),
    };
    final sending = c.status == ContactStatus.queued;

    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ThreadScreen(contactId: c.id))),
      child: Container(
        color: sending ? AppColors.accentSoft : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 11, 12, 11),
        child: Row(
          children: [
            Icon(icon, size: 17, color: colour),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: sending ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colour),
                  ),
                ],
              ),
            ),
            if (c.lastSentAt != null) ...[
              const SizedBox(width: 8),
              Text(
                formatTimestamp(c.lastSentAt!),
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
            ],
            if (c.status == ContactStatus.failed) ...[
              const SizedBox(width: 8),
              Material(
                color: AppColors.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
                    final ok = await ref.read(repoProvider).retryContact(c.id);
                    bumpRefresh(ref);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      ok
                          ? '${c.display} is back in the queue.'
                          : 'Already queued.',
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child: Icon(
                      LucideIcons.refreshCw,
                      size: 15,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
