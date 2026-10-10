import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'chats_screen.dart';
import 'common.dart';
import 'footer.dart';
import 'kit.dart';
import 'new_message_sheet.dart';
import 'thread_screen.dart';

/// Campaign replies (spec 8). Personal texts live in [PersonalInboxTab] on
/// their own footer tab — keeping them apart is the whole point, and a tab bar
/// inside one screen was not far enough apart: a bank OTP two swipes from a
/// lead is still in the same room as it.
class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadByKindProvider).valueOrNull ?? const {};
    return _InboxScaffold(
      greeting: 'From your list',
      title: 'Campaign Replies',
      kind: 'campaign',
      unread: unread['campaign'] ?? 0,
    );
  }
}

/// Everything that arrived while this app held the default-SMS role and did not
/// match a contact on the list: personal texts, OTPs, the bank.
class PersonalInboxTab extends ConsumerStatefulWidget {
  const PersonalInboxTab({super.key});

  @override
  ConsumerState<PersonalInboxTab> createState() => _PersonalInboxTabState();
}

class _PersonalInboxTabState extends ConsumerState<PersonalInboxTab> {
  @override
  void initState() {
    super.initState();
    // Threads that arrived before the contacts permission existed are bare
    // numbers; if the permission is there now, name them.
    Future.microtask(() => fillThreadNames(ref));
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadByKindProvider).valueOrNull ?? const {};
    return _InboxScaffold(
      greeting: 'Everything else that arrives',
      title: 'Personal Messages',
      kind: 'other',
      unread: unread['other'] ?? 0,
      canCompose: true,
    );
  }
}

/// The archive drawer: the same list, for conversations put away.
class ArchivedScreen extends ConsumerWidget {
  const ArchivedScreen({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final threads =
        ref.watch(archivedThreadsProvider(kind)).valueOrNull ??
        const <ThreadSummary>[];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(title: 'Archived', subtitle: 'Swipe one to bring it back'),
            Expanded(
              child: threads.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.archive,
                      title: 'Nothing archived',
                      message:
                          'Swipe a conversation left to put it away without '
                          'deleting it.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                      itemCount: threads.length,
                      // A swipe in either direction puts it back in the inbox
                      // — the same gesture that put it away, inverted. Without
                      // this, archiving was a one-way door once the Undo snack
                      // expired.
                      itemBuilder: (context, i) => Dismissible(
                        key: ValueKey('unarchive-${threads[i].contactId}'),
                        background: const _SwipeBackground(
                          icon: LucideIcons.archiveRestore,
                          label: 'Bring back',
                          alignment: Alignment.centerLeft,
                        ),
                        secondaryBackground: const _SwipeBackground(
                          icon: LucideIcons.archiveRestore,
                          label: 'Bring back',
                          alignment: Alignment.centerRight,
                        ),
                        confirmDismiss: (_) async {
                          await ref
                              .read(repoProvider)
                              .setArchived(threads[i].contactId, false);
                          bumpRefresh(ref);
                          if (context.mounted) {
                            showSnack(
                              context,
                              '${threads[i].display} is back in the inbox.',
                            );
                          }
                          return true;
                        },
                        child: _ThreadTile(
                          thread: threads[i],
                          selected: false,
                          selecting: false,
                          onSelect: null,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxScaffold extends ConsumerStatefulWidget {
  const _InboxScaffold({
    required this.greeting,
    required this.title,
    required this.kind,
    required this.unread,
    this.canCompose = false,
  });

  final String greeting;
  final String title;
  final String kind;
  final int unread;

  /// Personal messages can start a conversation; campaign replies cannot —
  /// speaking first to the list is what campaigns are for.
  final bool canCompose;

  @override
  ConsumerState<_InboxScaffold> createState() => _InboxScaffoldState();
}

class _InboxScaffoldState extends ConsumerState<_InboxScaffold> {
  /// Conversations ticked for a bulk action. Empty means ordinary browsing;
  /// non-empty puts the whole screen into selection mode.
  final _selected = <int>{};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(int contactId) {
    setState(() {
      if (!_selected.remove(contactId)) _selected.add(contactId);
    });
  }

  void _clear() => setState(_selected.clear);

  @override
  Widget build(BuildContext context) {
    final archived =
        ref.watch(archivedCountProvider(widget.kind)).valueOrNull ?? 0;

    return PopScope(
      // Leaving selection mode is what Back means while anything is ticked.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clear();
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (_selecting)
                _SelectionBar(
                  count: _selected.length,
                  onClose: _clear,
                  onAction: _bulk,
                )
              else
                ScreenHeader(
                  greeting: widget.greeting,
                  title: widget.title,
                  actions: [
                    if (widget.canCompose)
                      RoundAction(
                        icon: LucideIcons.squarePen,
                        label: 'New message',
                        onPressed: () => showNewMessageSheet(context),
                      ),
                    // What came in everywhere else. Only on the personal
                    // inbox: campaign replies are SMS by definition.
                    if (widget.canCompose)
                      RoundAction(
                        icon: LucideIcons.messagesSquare,
                        label: 'Message search',
                        dot:
                            (ref.watch(unseenChatCountProvider).valueOrNull ??
                                0) >
                            0,
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ChatsScreen(),
                            ),
                          );
                          if (context.mounted) bumpRefresh(ref);
                        },
                      ),
                    if (archived > 0)
                      RoundAction(
                        icon: LucideIcons.archive,
                        label: 'Archived conversations',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArchivedScreen(kind: widget.kind),
                          ),
                        ),
                      ),
                    if (widget.unread > 0)
                      RoundAction(
                        icon: LucideIcons.checkCheck,
                        label: 'Mark all read',
                        onPressed: () async {
                          final n = await ref
                              .read(repoProvider)
                              .markAllRead(kind: widget.kind);
                          bumpRefresh(ref);
                          if (!context.mounted) return;
                          showSnack(
                            context,
                            n == 0
                                ? 'Nothing unread here.'
                                : '$n conversation${n == 1 ? '' : 's'} marked read.',
                          );
                        },
                      ),
                  ],
                ),
              Expanded(
                child: _ThreadList(
                  kind: widget.kind,
                  selected: _selected,
                  onSelect: _toggle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One verb, applied to everything ticked.
  Future<void> _bulk(String action) async {
    final repo = ref.read(repoProvider);
    final ids = _selected.toList();
    if (ids.isEmpty) return;

    switch (action) {
      case 'pin':
      case 'unpin':
        for (final id in ids) {
          await repo.setPinned(id, action == 'pin');
        }
      case 'archive':
        for (final id in ids) {
          await repo.setArchived(id, true);
        }
      case 'read':
        for (final id in ids) {
          await repo.markThreadRead(id);
        }
      case 'unread':
        for (final id in ids) {
          await repo.setThreadUnread(id, true);
        }
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              ids.length == 1
                  ? 'Delete this conversation?'
                  : 'Delete ${ids.length} conversations?',
            ),
            content: const Text(
              'Every message in them is deleted from this app. Contacts stay '
              'on your list with their current status.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        for (final id in ids) {
          await repo.deleteThread(id);
        }
      case 'more':
        // Exactly one is ticked: the full per-conversation sheet — call,
        // block, mute — which has no sensible meaning across a selection.
        final contact = await repo.contactById(ids.first);
        if (contact == null || !mounted) return;
        _clear();
        if (context.mounted) {
          await showThreadActions(context, ref, contact, fromInbox: true);
        }
        return;
    }

    bumpRefresh(ref);
    _clear();
    if (!mounted) return;
    final word = switch (action) {
      'pin' => 'pinned',
      'unpin' => 'unpinned',
      'archive' => 'archived',
      'read' => 'marked read',
      'unread' => 'marked unread',
      _ => 'deleted',
    };
    showSnack(
      context,
      '${ids.length} conversation${ids.length == 1 ? '' : 's'} $word.',
    );
  }
}

/// The header while conversations are ticked: what is selected, and the verbs
/// that apply to all of it.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onClose,
    required this.onAction,
  });

  final int count;
  final VoidCallback onClose;
  final ValueChanged<String> onAction;

  /// The same white bar as the header it replaces, status-bar inset included
  /// — as a bare row it sat under the clock. See _NoteSelectionBar.
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    padding: EdgeInsets.fromLTRB(
      12,
      MediaQuery.paddingOf(context).top + 4,
      12,
      8,
    ),
    child: Row(
      children: [
        RoundAction(
          icon: LucideIcons.x,
          label: 'Cancel selection',
          onPressed: onClose,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '$count selected',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
        ),
        _Act(icon: LucideIcons.pin, label: 'Pin', onTap: () => onAction('pin')),
        const SizedBox(width: 6),
        _Act(
          icon: LucideIcons.archive,
          label: 'Archive',
          onTap: () => onAction('archive'),
        ),
        const SizedBox(width: 6),
        _Act(
          icon: LucideIcons.checkCheck,
          label: 'Mark read',
          onTap: () => onAction('read'),
        ),
        const SizedBox(width: 6),
        _Act(
          icon: LucideIcons.ellipsis,
          label: 'More',
          onTap: () => _more(context),
        ),
      ],
    ),
  );

  Future<void> _more(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
              const SizedBox(height: 14),
              _MoreRow(
                icon: LucideIcons.pinOff,
                label: 'Unpin',
                onTap: () => Navigator.pop(ctx, 'unpin'),
              ),
              _MoreRow(
                icon: LucideIcons.mailOpen,
                label: 'Mark unread',
                onTap: () => Navigator.pop(ctx, 'unread'),
              ),
              if (count == 1)
                _MoreRow(
                  icon: LucideIcons.settings2,
                  label: 'Call, block, mute…',
                  onTap: () => Navigator.pop(ctx, 'more'),
                ),
              _MoreRow(
                icon: LucideIcons.trash2,
                label: 'Delete',
                danger: true,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (choice != null) onAction(choice);
  }
}

class _Act extends StatelessWidget {
  const _Act({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: RoundAction(icon: icon, onPressed: onTap),
  );
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colour = danger ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: colour),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadList extends ConsumerStatefulWidget {
  const _ThreadList({
    required this.kind,
    required this.selected,
    required this.onSelect,
  });

  final String kind;
  final Set<int> selected;
  final ValueChanged<int> onSelect;

  @override
  ConsumerState<_ThreadList> createState() => _ThreadListState();
}

class _ThreadListState extends ConsumerState<_ThreadList> {
  final _search = TextEditingController();
  final _typing = Debouncer();
  String _query = '';

  @override
  void dispose() {
    _typing.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final async = ref.watch(threadsProvider(kind));

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
      data: (threads) {
        // A thread exists as soon as we send, so an unanswered campaign thread would
        // clutter the replies tab. Only show conversations that came back to us —
        // unless there is a draft, which is the user's own unfinished business.
        final relevant = kind == 'campaign'
            ? threads
                  .where(
                    (t) =>
                        t.contactStatus == ContactStatus.replied ||
                        t.contactStatus == ContactStatus.doNotContact ||
                        t.unreadCount > 0 ||
                        t.hasDraft,
                  )
                  .toList()
            : threads;

        final q = _query.trim().toLowerCase();
        final visible = q.isEmpty
            ? relevant
            : relevant
                  .where(
                    (t) =>
                        t.display.toLowerCase().contains(q) ||
                        t.snippet.toLowerCase().contains(q),
                  )
                  .toList();

        return Column(
          children: [
            // Six thousand contacts means the reply list gets long; a name is
            // faster to type than it is to scroll to.
            if (relevant.length > 6 || q.isNotEmpty)
              _SearchField(
                controller: _search,
                onChanged: (v) => _typing.run(() {
                  if (mounted) setState(() => _query = v);
                }),
              ),
            Expanded(
              child: (visible.isEmpty && q.isEmpty)
                  ? _empty(context, kind, q)
                  : RefreshIndicator(
                      onRefresh: () async => bumpRefresh(ref),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          6,
                          16,
                          footerClearance(context),
                        ),
                        children: [
                          for (final t in visible)
                            _ThreadTile(
                              key: ValueKey(t.contactId),
                              thread: t,
                              selected: widget.selected.contains(t.contactId),
                              selecting: widget.selected.isNotEmpty,
                              onSelect: widget.onSelect,
                            ),
                          // The same question, asked of message bodies. A
                          // search that finds no conversation almost always
                          // means the words are *inside* one.
                          if (q.length >= 2) _MessageHits(query: q),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context, String kind, String query) {
    if (query.isNotEmpty) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nothing matches',
        message: 'No conversation here mentions "$query".',
      );
    }
    return EmptyState(
      icon: kind == 'campaign'
          ? LucideIcons.messageCircleDashed
          : LucideIcons.messageSquareDashed,
      title: kind == 'campaign' ? 'No replies yet' : 'Nothing here',
      message: kind == 'campaign'
          ? 'A reply lands here, and drops that contact from future batches.'
          : 'Personal texts and OTPs land here while this app is your default.',
    );
  }
}

/// Matches found inside message bodies, under the conversation matches.
class _MessageHits extends ConsumerWidget {
  const _MessageHits({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hits =
        ref.watch(messageSearchProvider(query)).valueOrNull ??
        const <MessageHit>[];
    if (hits.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
          child: Text(
            'In messages · ${hits.length}',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.inkMuted,
            ),
          ),
        ),
        for (final hit in hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: AppColors.glass,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: const BorderSide(color: AppColors.glassEdge),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ThreadScreen(contactId: hit.contactId),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            hit.isInbound
                                ? LucideIcons.cornerDownLeft
                                : LucideIcons.cornerUpRight,
                            size: 13,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              hit.display,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Text(
                            formatTimestamp(hit.createdAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _Excerpt(body: hit.body, query: query),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The matched words in bold, with just enough either side to recognise them.
class _Excerpt extends StatelessWidget {
  const _Excerpt({required this.body, required this.query});

  final String body;
  final String query;

  @override
  Widget build(BuildContext context) {
    final at = body.toLowerCase().indexOf(query.toLowerCase());
    if (at < 0) {
      return Text(
        body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
      );
    }
    final from = at > 28 ? at - 24 : 0;
    final lead = from > 0 ? '…' : '';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: lead + body.substring(from, at)),
          TextSpan(
            text: body.substring(at, at + query.length),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          TextSpan(text: body.substring(at + query.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12.5,
        height: 1.3,
        color: AppColors.inkMuted,
      ),
    );
  }
}

/// Same quiet pill the add-contact fields use — the outlined Material box the
/// old one wore was the last of the stock chrome in this section.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.glassEdge),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14.5, color: AppColors.ink),
              decoration: const InputDecoration(
                hintText: 'Search names and messages',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 13),
                hintStyle: TextStyle(fontSize: 14.5, color: AppColors.inkMuted),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: const Icon(
                LucideIcons.x,
                size: 17,
                color: AppColors.inkMuted,
              ),
            ),
        ],
      ),
    ),
  );
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({
    super.key,
    required this.thread,
    required this.selected,
    required this.selecting,
    required this.onSelect,
  });

  final ThreadSummary thread;
  final bool selected;
  final bool selecting;

  /// Null in the archive, where selection would need a second set of verbs.
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = thread.unreadCount > 0;

    final tile = Material(
      // Each conversation is its own card; an unread one lifts by tone, and a
      // ticked one wears the accent outright.
      color: selected
          ? AppColors.accent
          : unread
          ? AppColors.accentSoft
          : AppColors.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: (unread || selected)
              ? Colors.transparent
              : AppColors.glassEdge,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () {
          if (selecting && onSelect != null) {
            onSelect!(thread.contactId);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadScreen(contactId: thread.contactId),
            ),
          );
        },
        // Holding a conversation starts a selection — the gesture every
        // messaging app uses for "this one, and these others too".
        onLongPress: onSelect == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onSelect!(thread.contactId);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            children: [
              selected
                  ? const CircleAvatar(
                      radius: 23,
                      backgroundColor: AppColors.ink,
                      child: Icon(
                        LucideIcons.check,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    )
                  : ContactAvatar(
                      label: thread.display,
                      // An ad-hoc inbound contact is stored do_not_contact only
                      // to keep it unbatchable; painting that dot on every
                      // personal sender would read as "blocked".
                      status: thread.kind == 'campaign'
                          ? thread.contactStatus
                          : null,
                      radius: 23,
                      phone: thread.phoneE164,
                    ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (thread.pinned) ...[
                          const Icon(
                            LucideIcons.pin,
                            size: 13,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            thread.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: -0.2,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatTimestamp(thread.lastMessageAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: unread ? AppColors.ink : AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          // A draft outranks the last message: it is the thing
                          // this conversation is waiting on.
                          child: thread.hasDraft && !unread
                              ? Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Draft: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.danger,
                                        ),
                                      ),
                                      TextSpan(text: thread.draft!),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: AppColors.inkMuted,
                                  ),
                                )
                              : Text(
                                  thread.snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    fontWeight: unread
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                    color: unread
                                        ? AppColors.inkSoft
                                        : AppColors.inkMuted,
                                  ),
                                ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 10),
                          Container(
                            constraints: const BoxConstraints(minWidth: 21),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2.5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              thread.unreadCount > 99
                                  ? '99+'
                                  : '${thread.unreadCount}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // No swiping while selecting: the drag would fight the tick, and the
    // selection bar already carries both verbs.
    if (selecting || onSelect == null) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: tile);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('swipe-${thread.contactId}'),
        background: _SwipeBackground(
          icon: unread ? LucideIcons.checkCheck : LucideIcons.mailOpen,
          label: unread ? 'Mark read' : 'Mark unread',
          alignment: Alignment.centerLeft,
        ),
        secondaryBackground: const _SwipeBackground(
          icon: LucideIcons.archive,
          label: 'Archive',
          alignment: Alignment.centerRight,
        ),
        confirmDismiss: (direction) async {
          final repo = ref.read(repoProvider);
          if (direction == DismissDirection.startToEnd) {
            // Read/unread is a toggle, so the row stays where it is.
            if (unread) {
              await repo.markThreadRead(thread.contactId);
            } else {
              await repo.setThreadUnread(thread.contactId, true);
            }
            bumpRefresh(ref);
            return false;
          }
          await repo.setArchived(thread.contactId, true);
          bumpRefresh(ref);
          if (context.mounted) {
            showSnackAction(
              context,
              '${thread.display} archived.',
              actionLabel: 'Undo',
              onAction: () async {
                await repo.setArchived(thread.contactId, false);
                bumpRefresh(ref);
              },
            );
          }
          return true;
        },
        child: tile,
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 22),
    alignment: alignment,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppColors.ink),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}
