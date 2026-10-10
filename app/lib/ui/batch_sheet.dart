import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'add_contact_sheet.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'pick_contacts_screen.dart';

/// What is actually inside a batch, on a sheet that comes up from the bottom.
///
/// Before this, tapping a batch went straight to Compose — you could send to a
/// hundred people without ever being shown who they were. The list is the point
/// of the sheet; sending is still one button, it just no longer happens sight
/// unseen.
Future<void> showBatchSheet(BuildContext context, int batchId) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BatchSheet(batchId: batchId),
    );

class _BatchSheet extends ConsumerWidget {
  const _BatchSheet({required this.batchId});

  final int batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batches = ref.watch(batchesProvider).valueOrNull ?? const <Batch>[];
    final index = batches.indexWhere((b) => b.id == batchId);
    final batch = index < 0 ? null : batches[index];
    final active = ref.watch(activeCampaignProvider).valueOrNull;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: AppColors.glassCanvas,
            child: batch == null
                ? const Center(child: Text('That batch is gone.'))
                : Column(
                    children: [
                      const _Grip(),
                      _Head(
                        batch: batch,
                        canMoveUp: index > 0,
                        canMoveDown: index < batches.length - 1,
                        onMove: (delta) async {
                          await ref
                              .read(repoProvider)
                              .moveBatch(batch.id, delta);
                          bumpRefresh(ref);
                        },
                        onRename: () => _rename(context, ref, batch),
                      ),
                      Expanded(
                        child: _People(
                          batchId: batchId,
                          controller: controller,
                        ),
                      ),
                      _Foot(batch: batch, locked: active != null),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, Batch batch) async {
    final controller = TextEditingController(text: batch.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename batch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || name.trim() == batch.name) {
      return;
    }
    await ref.read(repoProvider).renameBatch(batch.id, name);
    bumpRefresh(ref);
  }
}

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 4,
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    decoration: BoxDecoration(
      color: AppColors.hairline,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Name, what is left in it, and the two arrows that decide when it goes.
class _Head extends StatelessWidget {
  const _Head({
    required this.batch,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMove,
    required this.onRename,
  });

  final Batch batch;
  final bool canMoveUp;
  final bool canMoveDown;
  final ValueChanged<int> onMove;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final outstanding = batch.remaining + batch.failed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The name is the rename button. A separate edit icon earned
                // its keep nowhere; tapping the thing you want to change did.
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onRename,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          batch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w400,
                            letterSpacing: -0.8,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        LucideIcons.pencilLine,
                        size: 15,
                        color: AppColors.inkMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  outstanding == 0
                      ? '${batch.total} contacts · all done'
                      : '${batch.total} contacts · $outstanding to go',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          _Arrow(
            icon: LucideIcons.arrowUp,
            tip: 'Send this batch sooner',
            onTap: canMoveUp ? () => onMove(-1) : null,
          ),
          const SizedBox(width: 6),
          _Arrow(
            icon: LucideIcons.arrowDown,
            tip: 'Send this batch later',
            onTap: canMoveDown ? () => onMove(1) : null,
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tip, required this.onTap});

  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    // Semantics carries the label for screen readers; no Tooltip. A tooltip's
    // overlay can outlive the row or sheet that spawned it, which is the
    // '_dependents.isEmpty' crash the user hit on the device.
    return Semantics(
      label: tip,
      button: true,
      child: Material(
        color: on ? AppColors.glass : AppColors.glassSoft,
        shape: const CircleBorder(side: BorderSide(color: AppColors.glassEdge)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              icon,
              size: 19,
              color: on ? AppColors.ink : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _People extends ConsumerWidget {
  const _People({required this.batchId, required this.controller});

  final int batchId;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(batchContactsProvider(batchId));

    return people.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              'Nobody left in this batch.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          itemCount: list.length,
          itemBuilder: (_, i) => _Person(
            contact: list[i],
            onRemove: () => _remove(context, ref, list[i]),
            onMove: () => _move(context, ref, list[i]),
          ),
        );
      },
    );
  }

  /// Long-press on a person: send them to a different batch. Only people the
  /// engine has not reached can move — a sent contact's history belongs to the
  /// batch it happened in.
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    Contact contact,
  ) async {
    final movable =
        contact.status == ContactStatus.notSent ||
        contact.status == ContactStatus.failed;
    if (!movable) {
      showSnack(
        context,
        '${contact.display} has already been reached — they stay put.',
      );
      return;
    }
    final batches = ref.read(batchesProvider).valueOrNull ?? const <Batch>[];
    final others = batches.where((b) => b.id != batchId).toList();
    if (others.isEmpty) {
      showSnack(context, 'There is no other batch to move them to.');
      return;
    }
    final target = await showModalBottomSheet<Batch>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MoveTargetSheet(name: contact.display, others: others),
    );
    if (target == null || !context.mounted) return;
    final moved = await ref
        .read(repoProvider)
        .moveContactToBatch(contact.id, target.id);
    bumpRefresh(ref);
    if (!context.mounted) return;
    showSnack(
      context,
      moved
          ? '${contact.display} moved to ${target.name}.'
          : 'Could not move ${contact.display}.',
      error: !moved,
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    Contact contact,
  ) async {
    final messaged = contact.status != ContactStatus.notSent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${contact.display}?'),
        content: Text(
          messaged
              ? 'They come off this batch, and the messages already exchanged '
                    'with them are deleted too. This cannot be undone.'
              : 'They come off this batch and out of your contacts. Nothing has '
                    'been sent to them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(repoProvider).deleteContact(contact.id);
    bumpRefresh(ref);
    if (context.mounted) showSnack(context, '${contact.display} removed.');
  }
}

/// One person: who they are, what has happened to them, and the way out.
/// A long press picks them up and moves them to another batch.
class _Person extends StatelessWidget {
  const _Person({
    required this.contact,
    required this.onRemove,
    required this.onMove,
  });

  final Contact contact;
  final VoidCallback onRemove;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final named = contact.name != null && contact.name!.trim().isNotEmpty;

    return GestureDetector(
      onLongPress: onMove,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.glassEdge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    named ? contact.name!.trim() : contact.phoneLocal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    named
                        ? '${contact.phoneLocal} · ${ContactStatus.label(contact.status)}'
                        : ContactStatus.label(contact.status),
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
            IconButton(
              onPressed: onRemove,
              icon: const Icon(LucideIcons.x, size: 18),
              color: AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Where should they go — the other batches, one tap each.
class _MoveTargetSheet extends StatelessWidget {
  const _MoveTargetSheet({required this.name, required this.others});

  final String name;
  final List<Batch> others;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(AppRadius.sheet),
    ),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        color: AppColors.glassCanvas,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: _Grip()),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Text(
                  'Move $name to…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: others.length,
                  itemBuilder: (_, i) {
                    final b = others[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        onTap: () => Navigator.pop(context, b),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.arrowRightLeft,
                                size: 16,
                                color: AppColors.inkMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              Text(
                                '${b.total}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Add somebody, or send. The two things you came here to do.
class _Foot extends ConsumerWidget {
  const _Foot({required this.batch, required this.locked});

  final Batch batch;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sendable = !locked && (batch.remaining > 0 || batch.failed > 0);
    // The stuck state: everyone reachable has been reached, and the batch is
    // waiting on people whose sends failed. This is where it needs a way out
    // in both directions — try them again, or stop waiting for them.
    final onlyFailuresLeft = batch.remaining == 0 && batch.failed > 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onlyFailuresLeft)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => _writeOff(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.userX,
                          size: 15,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          batch.failed == 1
                              ? 'Give up on the 1 that failed'
                              : 'Give up on the ${batch.failed} that failed',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkMuted,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                _Arrow(
                  icon: LucideIcons.userPlus,
                  tip: 'Add somebody by hand',
                  onTap: () => showAddContactSheet(
                    context,
                    toBatchId: batch.id,
                    batchName: batch.name,
                  ),
                ),
                const SizedBox(width: 6),
                _Arrow(
                  icon: LucideIcons.bookUser,
                  tip: 'Add from your phone book',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PickContactsScreen(
                        batchId: batch.id,
                        batchName: batch.name,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _Arrow(
                  icon: LucideIcons.tag,
                  tip: 'Add everyone with a tag',
                  onTap: () => _addByTag(context, ref),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: sendable ? AppColors.accent : AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: sendable
                          ? () {
                              // Taken before the pop: afterwards this context is
                              // off the tree and cannot find a navigator.
                              final navigator = Navigator.of(context);
                              navigator.pop();
                              navigator.push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ComposeScreen(batchId: batch.id),
                                ),
                              );
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Center(
                          child: Text(
                            locked
                                ? 'A batch is already sending'
                                : !sendable
                                ? 'Nothing left to send'
                                // The stuck batch says what the button will
                                // actually do, which is retry — "Send" implied
                                // fresh contacts it does not have.
                                : onlyFailuresLeft
                                ? 'Retry ${batch.failed} failed'
                                : 'Send ${batch.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: sendable
                                  ? AppColors.ink
                                  : AppColors.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _writeOff(BuildContext context, WidgetRef ref) =>
      confirmWriteOff(context, ref, batch);

  /// "Everyone tagged car-buyer, into this batch." The tag audience meets
  /// the batch machinery here, so a campaign to a tag is just a normal send.
  Future<void> _addByTag(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repoProvider);
    final tags = await repo.tags();
    if (!context.mounted) return;
    if (tags.isEmpty) {
      showSnack(
        context,
        'No tags yet. Open somebody\'s profile and tag them first.',
      );
      return;
    }
    final picked = await showModalBottomSheet<Tag>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: AppColors.glassCanvas,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                    child: Text(
                      'Add whom to ${batch.name}?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  for (final t in tags)
                    InkWell(
                      onTap: () => Navigator.of(ctx).pop(t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.tag,
                              size: 16,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            Text(
                              '${t.count}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final result = await repo.addTagToBatch(batch.id, picked.id);
    bumpRefresh(ref);
    if (!context.mounted) return;
    final parts = <String>[
      if (result.moved > 0) '${result.moved} added',
      if (result.skipped > 0)
        '${result.skipped} stayed put — already reached or already here',
    ];
    showSnack(
      context,
      parts.isEmpty ? 'Nobody wears that tag yet.' : parts.join(' · '),
    );
  }
}

/// Stop waiting for the ones that failed, from wherever the stuck batch is
/// being looked at.
///
/// Confirmed first, and the dialog says exactly where they go — off this list,
/// not out of the app. One dead number should not hold ninety-nine delivered
/// messages in "to send" forever, but neither should giving up on it be silent.
Future<void> confirmWriteOff(
  BuildContext context,
  WidgetRef ref,
  Batch batch,
) async {
  final n = batch.failed;
  if (n == 0) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(n == 1 ? 'Give up on 1 contact?' : 'Give up on $n contacts?'),
      content: Text(
        'The ${n == 1 ? 'one' : '$n'} whose sends failed come off '
        '${batch.name}, so it can finish. They stay under Failed on the '
        'dashboard — nothing about them is forgotten, and you can still '
        'retry them from there later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep waiting'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Give up on them'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final removed = await ref.read(repoProvider).writeOffFailed(batch.id);
  bumpRefresh(ref);
  if (!context.mounted) return;
  showSnack(
    context,
    removed == 1
        ? '1 contact written off — ${batch.name} is done.'
        : '$removed contacts written off — ${batch.name} is done.',
  );
}
