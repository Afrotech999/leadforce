import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/license.dart';
import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'add_contact_sheet.dart';
import 'batch_sheet.dart';
import 'listings_screen.dart';
import 'chats_screen.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'contacts_screen.dart';
import 'deals_screen.dart';
import 'default_sms_banner.dart';
import 'footer.dart';
import 'import_screen.dart';
import 'kit.dart';
import 'needs_review_screen.dart';
import 'new_message_sheet.dart';
import 'notes_screen.dart';
import 'schedule_screen.dart';
import 'sending_screen.dart';
import 'settings_screen.dart';
import 'subscribe_screen.dart';
import 'thread_screen.dart';

/// Home.
///
/// The broker's morning glance: shortcuts, today's sending in one compact
/// card, whatever needs attention, then the CRM — appointment, cooling leads,
/// pipeline. No stat row and no gauges: every figure the old dashboard put in
/// a box lives one tap away, and a screen that answers one question calmly
/// beats one that answers five at once.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider).valueOrNull;
    final active = ref.watch(activeCampaignProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => bumpRefresh(ref),
          // Slivers rather than a ListView so the reorderable batch list can
          // scroll the page while a batch is being dragged. Nested inside a
          // ListView it could only ever move within one screenful, which is
          // useless at twenty-three batches.
          child: CustomScrollView(
            slivers: [
              SliverList.list(
                children: [
                  // Three actions, not five. Schedule has the Remind shortcut
                  // below, and replies have their own footer tab with a badge —
                  // a bell up here said the same thing twice.
                  ScreenHeader(
                    title: 'Your Dashboard',
                    actions: [
                      RoundAction(
                        icon: LucideIcons.userPlus,
                        label: 'Add a contact',
                        onPressed: () => showAddContactSheet(context),
                      ),
                      RoundAction(
                        icon: LucideIcons.search,
                        label: 'Search contacts',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ContactsTab(),
                          ),
                        ),
                      ),
                      RoundAction(
                        icon: LucideIcons.settings,
                        label: 'Settings',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsTab(),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // No stat-pill band. "Reached / Remaining / Failed" repeated
                  // what the Today card and the queue line already say, and
                  // every one of those lists is still a tap away — the
                  // Contacts screen filters by exactly these statuses.
                  if (stats != null) ...[
                    const SizedBox(height: 16),
                    const _QuickActions(),
                    const SizedBox(height: 12),
                    _TodayCard(stats: stats, active: active),
                  ],

                  // What needs the user's attention, most urgent first.
                  const _PermissionsBanner(),
                  const _ScheduledBanner(),
                  const DefaultSmsBanner(),
                  if (stats != null && stats.needsReview > 0)
                    _ReviewCard(count: stats.needsReview),
                  const _LicenseBanner(),
                  const _BackupBanner(),

                  // The CRM's day: who to be with, who is drifting, where the
                  // deals stand, what arrived elsewhere. The batch queue is
                  // deliberately NOT a section here any more — a wall of batch
                  // cards made Home read as "the bulk SMS tool, with extras",
                  // and the queue is one line inside Today with the whole list
                  // a tap away.
                  const _NextAppointmentCard(),
                  const _GoingColdSection(),
                  const _PipelineCard(),
                  const _OtherAppsCard(),
                ],
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: footerClearance(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reorderable batch cards themselves, shared by the dashboard's short
/// list and the full Batches screen — one implementation, so drag, haptics
/// and the accent rule cannot drift apart.
List<Widget> batchListSlivers({
  required BuildContext context,
  required List<Batch> visible,
  required bool locked,
  required void Function(int from, int to) onReorder,
}) {
  if (visible.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
              'No batches in this state.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
    ];
  }
  return [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // Reorderable in place: priority is a property of this list, and
      // making the user open something to change it put a page between the
      // question and the answer.
      sliver: SliverReorderableList(
        itemCount: visible.length,
        onReorderItem: onReorder,
        // The lift is felt, not just seen — press-and-hold has no visual
        // cue of its own until the card starts moving.
        onReorderStart: (_) => HapticFeedback.mediumImpact(),
        // The default is a Material shadow, which this palette does not use
        // anywhere else. The card just lifts a shade.
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (_, _) => Transform.scale(
            scale: 1.02,
            child: Opacity(opacity: 0.94, child: child),
          ),
          child: child,
        ),
        itemBuilder: (context, i) => _BatchRow(
          key: ValueKey(visible[i].id),
          batch: visible[i],
          index: i,
          // The first batch you would actually send is the one wearing the
          // accent. Exactly one per screen.
          accent:
              i == 0 &&
              !locked &&
              (visible[i].remaining > 0 || visible[i].failed > 0),
        ),
      ),
    ),
  ];
}

/// A batch of the user's own making: named now, filled from the sheet that
/// opens the moment it exists.
Future<void> showNewBatchDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New batch'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Walk-in customers'),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || name.trim().isEmpty) return;
  final id = await ref.read(repoProvider).createBatch(name);
  bumpRefresh(ref);
  if (!context.mounted) return;
  await showBatchSheet(context, id);
}

/// No Partial tab. It filtered to `outstanding > 0 && outstanding < total`,
/// a strict subset of To send's `outstanding > 0` — every batch it could show
/// was already one tab to its left.
enum _Filter { toSend, done }

/// The batch queue, whole: the cards, drag-to-reorder, and the sheet on tap.
/// This is the queue's home now — the dashboard carries one line about it.
class BatchesScreen extends ConsumerStatefulWidget {
  const BatchesScreen({super.key});

  @override
  ConsumerState<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends ConsumerState<BatchesScreen> {
  _Filter _filter = _Filter.toSend;

  bool _matches(Batch b) {
    final outstanding = b.remaining + b.failed;
    return switch (_filter) {
      _Filter.toSend => outstanding > 0 || b.total == 0,
      _Filter.done => b.total > 0 && outstanding == 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final batches = ref.watch(batchesProvider).valueOrNull ?? const <Batch>[];
    final active = ref.watch(activeCampaignProvider).valueOrNull;
    final shown = batches.where(_matches).toList();

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageBar(
                    title: 'All Batches',
                    subtitle:
                        '${batches.length} in the queue · hold to reorder',
                    actions: [
                      RoundAction(
                        icon: LucideIcons.plus,
                        label: 'New batch',
                        onPressed: () => showNewBatchDialog(context, ref),
                      ),
                    ],
                  ),
                  PillTabs(
                    labels: const ['To send', 'Done'],
                    index: _Filter.values.indexOf(_filter),
                    onSelect: (i) =>
                        setState(() => _filter = _Filter.values[i]),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            // The dashboard used to carry the import empty state; now that the
            // queue lives here, so does the doorway in.
            if (batches.isEmpty)
              // hasScrollBody stays true: EmptyState scrolls itself, and
              // measuring its LayoutBuilder for intrinsics is not allowed.
              SliverFillRemaining(
                child: EmptyState(
                  icon: LucideIcons.inbox,
                  title: 'No batches yet',
                  message: 'Import a spreadsheet and the queue builds itself.',
                  action: EmptyAction(
                    label: 'Add contacts',
                    icon: LucideIcons.fileSpreadsheet,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ImportScreen()),
                    ),
                  ),
                ),
              )
            else ...[
              ...batchListSlivers(
                context: context,
                visible: shown,
                locked: active != null,
                onReorder: (from, to) async {
                  final ids = reorderedIds(
                    all: batches,
                    shown: shown,
                    from: from,
                    to: to,
                  );
                  if (ids == null) return;
                  await ref.read(repoProvider).saveBatchOrder(ids);
                  bumpRefresh(ref);
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Turns a drag inside the filtered list into one order for the whole list.
///
/// The list on screen is a filter of the real one, so index 2 there is rarely
/// index 2 underneath. The batch being moved is placed relative to the batch it
/// was dropped against, which is the only reading of the gesture that holds
/// when a tab is hiding half the batches.
///
/// [to] is already adjusted for the dragged item having left its old slot —
/// this is fed by `onReorderItem`, not the older `onReorder`. Returns null when
/// the drag cannot be made sense of.
List<int>? reorderedIds({
  required List<Batch> all,
  required List<Batch> shown,
  required int from,
  required int to,
}) {
  if (from < 0 || from >= shown.length || to < 0) return null;

  final moved = shown[from];
  final rest = [...shown]..removeAt(from);
  // One visible batch has nothing to be dropped against, so the drag says
  // nothing about where it belongs among the ones the filter is hiding.
  if (rest.isEmpty) return null;
  final ids = all.map((b) => b.id).toList()..remove(moved.id);
  if (ids.length == all.length) return null;

  final at = to >= rest.length
      ? ids.indexOf(rest.last.id) + 1
      : ids.indexOf(rest[to].id);
  return ids..insert(at, moved.id);
}

/// Groups a number with thin spaces rather than commas — what makes a long
/// figure read as one shape instead of three.
String groupDigits(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The four things done between calls, one tap from the top of the app:
/// text somebody, write something down, book a reminder, check the pipeline.
/// This is what makes the dashboard a place work starts, not just a report.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _QuickAction(
            icon: LucideIcons.messageSquarePlus,
            label: 'Text',
            onTap: () => showNewMessageSheet(context),
          ),
          const SizedBox(width: 8),
          _QuickAction(
            icon: LucideIcons.stickyNote,
            label: 'Note',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
              );
              bumpRefresh(ref);
            },
          ),
          const SizedBox(width: 8),
          _QuickAction(
            icon: LucideIcons.calendarClock,
            label: 'Remind',
            onTap: () => showAppointmentSheet(context, ref),
          ),
          const SizedBox(width: 8),
          _QuickAction(
            icon: LucideIcons.handshake,
            label: 'Deals',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DealsScreen())),
          ),
          const SizedBox(width: 8),
          _QuickAction(
            icon: LucideIcons.package,
            label: 'Listings',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ListingsScreen())),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// An outlined white tile, the shape of the Feed / Dashboards / Calls row at
  /// the top of HubSpot's home screen.
  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, size: 21, color: AppColors.ink),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// What is left of the cap, and the one button worth pressing.
///
/// Compact on purpose. The first version stacked a huge numeral, a caption
/// and a tick gauge that all said "you have sent 38 of 100" three different
/// ways — one quiet line says it once, and the block stops being the loudest
/// thing on the screen.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.stats, required this.active});

  final Stats stats;
  final CampaignProgress? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextPendingBatchProvider);
    final live = active != null;
    final left = (stats.dailyCap - stats.usedToday).clamp(0, stats.dailyCap);

    // No card and no "Today" heading around this any more — the caption
    // already says "today", and a box with a title made three quiet lines
    // read as a whole department. The send button carries the block.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stats.capHit
                ? 'The daily cap is used up — more tomorrow.'
                : stats.usedToday == 0
                ? '$left ${stats.capUnit} available today'
                : '${groupDigits(stats.usedToday)} sent · '
                      '$left of ${stats.dailyCap} ${stats.capUnit} left today',
            style: TextStyle(
              fontSize: 13,
              color: stats.capHit ? AppColors.danger : AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: live || next != null ? AppColors.ink : AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: live
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SendingScreen(campaignId: active!.campaignId),
                        ),
                      )
                    : next == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ComposeScreen(batchId: next.id),
                        ),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        live ? LucideIcons.radio : LucideIcons.send,
                        size: 17,
                        color: live || next != null
                            ? Colors.white
                            : AppColors.inkMuted,
                      ),
                      const SizedBox(width: 9),
                      Flexible(
                        child: Text(
                          live
                              ? 'Sending ${active!.batchName}'
                              : next == null
                              ? 'Nothing left to send'
                              : 'Send ${next.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: live || next != null
                                ? Colors.white
                                : AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The queue, as one line. This is all the dashboard says about
          // batches now: what is waiting and where the whole list lives.
          const SizedBox(height: 12),
          const Divider(height: 1),
          _QueueLine(),
        ],
      ),
    );
  }
}

/// "61 batches waiting · 5,801 people" with the queue one tap away — or, on a
/// fresh install, the door to importing the spreadsheet. The dashboard used to
/// carry the batch list itself, which made Home read as "the bulk SMS tool,
/// with extras"; the queue is campaign plumbing, and plumbing gets a line.
class _QueueLine extends ConsumerWidget {
  const _QueueLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(batchesProvider).valueOrNull;
    if (batches == null) return const SizedBox(height: 8);

    if (batches.isEmpty) {
      return InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const Icon(
                LucideIcons.fileSpreadsheet,
                size: 16,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'No contacts yet — import your spreadsheet',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ),
              const Text(
                'Import',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accentDark,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final waiting = batches
        .where((b) => b.remaining + b.failed > 0 || b.total == 0)
        .length;
    final people = batches.fold<int>(0, (n, b) => n + b.remaining + b.failed);

    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const BatchesScreen())),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            const Icon(LucideIcons.layers, size: 16, color: AppColors.inkMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                // Kept terse on purpose — the link on the right owns the tail
                // of the line, and "3 of 3 batches waiting" is three words of
                // redundancy an ellipsis would eat the people count for.
                waiting == 0
                    ? '${batches.length} batches, all sent'
                    : waiting == batches.length
                    ? '$waiting batches waiting · ${groupDigits(people)} people'
                    : '$waiting of ${batches.length} waiting · '
                          '${groupDigits(people)} people',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
            ),
            const Text(
              'All batches',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.accentDark,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: AppColors.accentDark,
            ),
          ],
        ),
      ),
    );
  }
}

/// The next thing you have to be somewhere for.
///
/// One line on the dashboard, because a viewing at three is not something to
/// go looking for — and the whole schedule is one tap behind it.
class _NextAppointmentCard extends ConsumerWidget {
  const _NextAppointmentCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextAppointmentProvider).valueOrNull;
    if (next == null) return const SizedBox.shrink();
    final missed = next.isPast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: missed ? AppColors.dangerSoft : AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ScheduleScreen())),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: missed ? Colors.transparent : AppColors.glassEdge,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.calendarClock,
                  size: 18,
                  color: missed ? AppColors.danger : AppColors.ink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: missed ? AppColors.danger : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (missed) 'Missed —',
                          scheduleLabel(next.at),
                          if (next.who != null) 'with ${next.who}',
                        ].join(' '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: missed ? AppColors.danger : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 19,
                  color: missed ? AppColors.danger : AppColors.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The clock on the subscription, only when it is worth saying: through the
/// whole free trial (a buyer deciding needs to see the countdown), and in
/// the last days of a paid period. A healthy subscription shows nothing.
/// "Back this up" — the one warning this app owes its user.
///
/// Everything here lives on one phone and nowhere else. That is the promise
/// (nothing is uploaded, no account, no server) and it is also the risk: a
/// stolen handset or a cracked screen takes six thousand contacts, every
/// conversation and every listing with it. A backup feature nobody
/// remembers to press is not a backup, so after a fortnight the dashboard says
/// so, with the button on the same row as the sentence.
///
/// It is not a dialog and it cannot nag: it sits in the flow of the page, and
/// taking a backup makes it go away for another fortnight.
/// A permission still off: what it is called, what it unlocks, how to fix it.
class _PermissionGap {
  const _PermissionGap(this.title, this.why, this.fix);

  final String title;
  final String why;
  final Future<void> Function() fix;
}

/// Every permission the app can use but does not hold right now. Re-checked on
/// each refresh tick, which fires on resume — so coming back from a system
/// dialog updates the list by itself.
final _permissionGapsProvider =
    FutureProvider.autoDispose<List<_PermissionGap>>((ref) async {
      ref.watch(refreshProvider);
      final gaps = <_PermissionGap>[];
      if (!await SmsChannel.hasSmsPermissions()) {
        gaps.add(
          _PermissionGap(
            'Send & receive SMS',
            'The heart of the app — nothing sends without it.',
            () async => SmsChannel.requestSmsPermissions(),
          ),
        );
      }
      if (!await SmsChannel.hasContactsPermission()) {
        gaps.add(
          _PermissionGap(
            'Read your contacts',
            'Pick people straight from the phone book.',
            () async => SmsChannel.requestContactsPermission(),
          ),
        );
      }
      if (!await SmsChannel.hasCallLogPermission()) {
        gaps.add(
          _PermissionGap(
            'See your call log',
            'The caller card and the after-call note need it.',
            () async => SmsChannel.requestCallLogPermission(),
          ),
        );
      }
      if (!await SmsChannel.hasOverlayPermission()) {
        gaps.add(
          _PermissionGap(
            'Display over other apps',
            'Float who is calling — and your notes — over the call.',
            SmsChannel.requestOverlayPermission,
          ),
        );
      }
      return gaps;
    });

/// Whatever is still left to tick, surfaced where it will be seen.
///
/// One line on the dashboard, however many are off; the sheet behind it lists
/// each with its own Grant button. The banner removes itself the day the last
/// one is on.
class _PermissionsBanner extends ConsumerWidget {
  const _PermissionsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaps = ref.watch(_permissionGapsProvider).valueOrNull ?? const [];
    if (gaps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _openSheet(context),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.shieldQuestionMark,
                  size: 17,
                  color: AppColors.ink,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gaps.length == 1
                            ? 'One permission still off'
                            : '${gaps.length} permissions still off',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        gaps.map((g) => g.title).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Fix',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final gaps =
              ref.watch(_permissionGapsProvider).valueOrNull ??
              const <_PermissionGap>[];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gaps.isEmpty ? 'All set' : 'Left to turn on',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    gaps.isEmpty
                        ? 'Every permission the app can use is on.'
                        : 'The app works without them — just with less. '
                              'Each one unlocks the feature named under it.',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final g in gaps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  g.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  g.why,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () async {
                              await g.fix();
                              if (context.mounted) bumpRefresh(ref);
                            },
                            child: const Text('Grant'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BackupBanner extends ConsumerWidget {
  const _BackupBanner();

  static const _nagAfter = Duration(days: 14);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const SizedBox.shrink();

    // Nothing to lose yet: a fresh install with no contacts does not need to
    // be told to protect them.
    final contacts = ref.watch(statsProvider).valueOrNull?.totalContacts ?? 0;
    if (contacts == 0) return const SizedBox.shrink();

    final last = int.tryParse(settings[SettingKeys.lastBackupAt] ?? '') ?? 0;
    final never = last <= 0;
    final age = never
        ? Duration.zero
        : Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - last);
    if (!never && age < _nagAfter) return const SizedBox.shrink();

    final text = never
        ? 'Nothing is backed up yet'
        : 'Last backup was ${age.inDays} days ago';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => _backUpNow(context, ref),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.shieldAlert,
                  size: 17,
                  color: AppColors.ink,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'If this phone goes, everything on it goes with it.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Back up',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The same path Settings uses: checkpoint the write-ahead log so the copy
  /// holds everything, then hand the file to whatever the user sends things
  /// with.
  Future<void> _backUpNow(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repoProvider);
    await repo.checkpoint();
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final error = await SmsChannel.shareBackup(stamp: stamp);
    if (error != null) {
      if (context.mounted) showSnack(context, error, error: true);
      return;
    }
    await repo.markBackedUp();
    bumpRefresh(ref);
  }
}

class _LicenseBanner extends ConsumerWidget {
  const _LicenseBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(licenseProvider).valueOrNull;
    if (license == null) return const SizedBox.shrink();
    final show =
        license.phase == LicensePhase.trial ||
        (license.phase == LicensePhase.active && license.daysLeft <= 5);
    if (!show) return const SizedBox.shrink();

    final days = license.daysLeft;
    final text = license.phase == LicensePhase.trial
        ? (days <= 0
              ? 'Free trial ends today'
              : 'Free trial — $days day${days == 1 ? '' : 's'} left')
        : 'Subscription ends in $days day${days == 1 ? '' : 's'}';
    final urgent = days <= 2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: urgent ? AppColors.dangerSoft : AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const SubscribeScreen())),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: urgent ? Colors.transparent : AppColors.glassEdge,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.ticket,
                  size: 17,
                  color: urgent ? AppColors.danger : AppColors.ink,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: urgent ? AppColors.danger : AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  'Subscribe',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: urgent ? AppColors.danger : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unread from the other messengers. Absent entirely until something has
/// actually arrived — a dashboard should never advertise an empty room.
class _OtherAppsCard extends ConsumerWidget {
  const _OtherAppsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenChatCountProvider).valueOrNull ?? 0;
    if (unseen == 0) return const SizedBox.shrink();
    // Whose logos to show: the apps actually waiting, busiest first.
    final apps =
        ref.watch(unseenChatAppsProvider).valueOrNull ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ChatsScreen()));
            if (context.mounted) bumpRefresh(ref);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                if (apps.isEmpty)
                  const Icon(
                    LucideIcons.messagesSquare,
                    size: 18,
                    color: AppColors.ink,
                  )
                else
                  for (final app in apps.take(3))
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AppIcon(package: app, size: 22),
                    ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    unseen == 1
                        ? '1 new message in another app'
                        : '$unseen new messages in other apps',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
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
        ),
      ),
    );
  }
}

/// The pipeline at a glance: how many deals sit in each open stage. Absent
/// entirely until the first deal exists — the dashboard should not lecture
/// about features that have never been used.
class _PipelineCard extends ConsumerWidget {
  const _PipelineCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(pipelineCountsProvider).valueOrNull ?? const {};
    final total = counts.values.fold(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();

    // Closest to money first — "2 negotiating" matters more than "5 new".
    final parts = [
      for (final stage in DealStage.open.reversed)
        if ((counts[stage] ?? 0) > 0)
          '${counts[stage]} ${DealStage.label(stage).toLowerCase()}',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const DealsScreen())),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.handshake,
                  size: 18,
                  color: AppColors.ink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total deal${total == 1 ? '' : 's'} in motion',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        parts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
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
        ),
      ),
    );
  }
}

/// Somebody with a live deal has gone quiet. Their face on the dashboard is
/// the whole feature: the app remembers who you forgot.
class _GoingColdSection extends ConsumerWidget {
  const _GoingColdSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cold =
        ref.watch(goingColdProvider).valueOrNull ?? const <ColdContact>[];
    if (cold.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              'GOING COLD',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: AppColors.inkMuted,
              ),
            ),
          ),
          for (final c in cold) _ColdRow(cold: c),
        ],
      ),
    );
  }
}

class _ColdRow extends ConsumerWidget {
  const _ColdRow({required this.cold});

  final ColdContact cold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = cold.daysQuiet;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadScreen(contactId: cold.contact.id),
              ),
            );
            bumpRefresh(ref);
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                ContactAvatar(
                  label: cold.contact.display,
                  radius: 19,
                  phone: cold.contact.phoneE164,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cold.contact.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (days >= 0) '$days days quiet',
                          cold.deal.what,
                          DealStage.label(cold.deal.stage).toLowerCase(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.messageSquare,
                  size: 17,
                  color: AppColors.inkMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The one campaign waiting on the clock, if there is one: what will go out,
/// when, and the X that calls it off.
class _ScheduledBanner extends ConsumerWidget {
  const _ScheduledBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduled = ref.watch(scheduledProvider).valueOrNull;
    if (scheduled == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.calendarClock,
              size: 18,
              color: AppColors.ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${scheduled.batchName} is scheduled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Goes out ${scheduleLabel(scheduled.at)}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _cancel(context, ref, scheduled),
              icon: const Icon(LucideIcons.x, size: 18),
              color: AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    ScheduledCampaign scheduled,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel the send to ${scheduled.batchName}?'),
        content: const Text('Nothing goes out; the batch stays as it is.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repoProvider).cancelScheduled(scheduled.campaignId);
    await SmsChannel.cancelAlarm(campaignId: scheduled.campaignId);
    bumpRefresh(ref);
    if (context.mounted) showSnack(context, 'Scheduled send cancelled.');
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: AppColors.infoSoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NeedsReviewScreen())),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              const Icon(
                LucideIcons.listFilter,
                size: 18,
                color: AppColors.info,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$count imported rows need review',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.info),
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                size: 19,
                color: AppColors.info,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BatchRow extends ConsumerWidget {
  const _BatchRow({
    super.key,
    required this.batch,
    required this.index,
    required this.accent,
  });

  final Batch batch;
  final int index;
  final bool accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = batch.remaining == 0 && batch.failed == 0;
    final outstanding = batch.remaining + batch.failed;
    final reached = batch.total - outstanding;
    final percent = batch.total == 0
        ? 0
        : (reached / batch.total * 100).round();

    // No queue-number gutter any more: the order IS the queue, the drag says
    // so, and the numbers mostly said "margin" at a glance.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Press-and-hold anywhere on the card lifts it for reordering — the
        // gesture every list app trains. The grip stays for the immediate
        // grab; the two recognizers settle it in the gesture arena: a quick
        // touch-and-move on the grip wins instantly, a held press anywhere
        // wins after the long-press delay, and a plain tap still opens the
        // sheet.
        Expanded(
          child: ReorderableDelayedDragStartListener(
            index: index,
            child: GhostRow(
              numeral: '${done ? batch.total : outstanding}',
              numeralCaption: done ? 'sent' : 'left',
              // The left column is the state of the batch, on one line. It
              // used to be a two-line label whose second line was the unit of
              // the numeral in the middle of the card, so a batch with one
              // failure announced itself as "Failed / left".
              leftTop: 'Status',
              leftBottom: done
                  ? 'Finished'
                  : batch.failed > 0 && batch.remaining == 0
                  ? 'Failed'
                  : batch.status == BatchStatus.partial
                  ? 'Partial'
                  : 'To send',
              rightTop: '${batch.total} contacts',
              rightBottom: batch.name,
              cornerLabel: 'Reached',
              cornerValue: '$percent%',
              tone: accent
                  ? GhostTone.accent
                  : done
                  ? GhostTone.muted
                  : GhostTone.plain,
              // Every batch opens, finished ones included. Sending is a button inside
              // the sheet rather than the whole row: nobody should be one tap away from
              // messaging a hundred people they have not been shown.
              onTap: () => showBatchSheet(context, batch.id),
              // The way out of the stuck state, on the row where the state is
              // visible. A batch whose sends all landed except one sits in
              // "to send" forever on the strength of that one number, and the
              // escape was a small grey underline at the bottom of a sheet
              // two taps away — which is the same as not having one.
              footer: batch.remaining == 0 && batch.failed > 0
                  ? _StuckFooter(batch: batch)
                  : null,
              // The grip is on the right, where a one-handed thumb is. The opaque box
              // around it is not decoration: the drag listener defers its hit test to
              // its child, and an icon glyph does not answer one reliably — without a
              // solid box behind it the finger lands on the card, not the handle.
              trailing: ReorderableDragStartListener(
                index: index,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 30,
                    height: 26,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Icon(
                        LucideIcons.gripVertical,
                        size: 16,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The strip along the bottom of a batch that is waiting on failures alone:
/// what is holding it up, and the two ways out.
class _StuckFooter extends ConsumerWidget {
  const _StuckFooter({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const Icon(LucideIcons.alertCircle, size: 14, color: AppColors.danger),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            batch.failed == 1 ? '1 failed' : '${batch.failed} failed',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ),
        _StuckAction(
          label: 'Try again',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ComposeScreen(batchId: batch.id)),
          ),
        ),
        const SizedBox(width: 4),
        // "Write off" rather than "Give up": it is the word for taking a loss
        // off the books, which is exactly what this does — the person stays,
        // the batch stops waiting.
        _StuckAction(
          label: 'Write off',
          onTap: () => confirmWriteOff(context, ref, batch),
        ),
      ],
    ),
  );
}

class _StuckAction extends StatelessWidget {
  const _StuckAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(AppRadius.card),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.accentDark,
          ),
        ),
      ),
    ),
  );
}
