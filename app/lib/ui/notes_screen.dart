import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'footer.dart';
import 'kit.dart';
import 'thread_screen.dart';

/// Notes, as a two-column board of cards or a list of compact rows.
///
/// A note here is a plain title and body. A line beginning `- ` is an open item
/// and `x ` a done one, so a checklist lives in the text rather than in the
/// schema — it survives being copied into a message, exported, or read straight
/// out of the database, and there is no second table to keep in step.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _search = TextEditingController();
  final _typing = Debouncer();
  String _query = '';

  /// Notes ticked for a bulk action. Empty means ordinary browsing; anything
  /// in it turns the header into an action bar and the cards into targets.
  final _selected = <int>{};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _typing.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(BuildContext context, Note? note) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)));
    if (mounted) bumpRefresh(ref);
  }

  void _toggle(Note note) {
    setState(() {
      if (!_selected.remove(note.id)) _selected.add(note.id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Board (two columns) or list (one) — a stored preference, not per-visit.
  bool get _grid =>
      (ref.watch(settingsProvider).valueOrNull?['notes_view'] ?? 'grid') !=
      'list';

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider(_query));
    final all = notes.valueOrNull ?? const <Note>[];
    final picked = all.where((n) => _selected.contains(n.id)).toList();

    return PopScope(
      // While notes are ticked, Back means "never mind" rather than "leave".
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (_selecting)
                _NoteSelectionBar(
                  count: picked.length,
                  allPinned: picked.isNotEmpty && picked.every((n) => n.pinned),
                  onClose: _clearSelection,
                  onAction: (a) => _bulk(a, picked),
                  onSelectAll: () =>
                      setState(() => _selected.addAll(all.map((n) => n.id))),
                )
              else ...[
                ScreenHeader(
                  greeting: 'Kept on this phone',
                  title: 'Your Notes',
                  actions: [
                    // Board or column — some people scan a wall, some read a
                    // list. Remembered, so the choice only has to be made once.
                    RoundAction(
                      icon: _grid ? LucideIcons.rows3 : LucideIcons.layoutGrid,
                      label: _grid ? 'Show as a list' : 'Show as a board',
                      onPressed: () async {
                        await ref
                            .read(repoProvider)
                            .setSetting('notes_view', _grid ? 'list' : 'grid');
                        bumpRefresh(ref);
                      },
                    ),
                  ],
                ),
                SearchField(
                  controller: _search,
                  hint: 'Search your notes',
                  onChanged: (v) => _typing.run(() {
                    if (mounted) setState(() => _query = v);
                  }),
                  onClear: _query.isEmpty
                      ? null
                      : () {
                          _search.clear();
                          _typing.flush(() => setState(() => _query = ''));
                        },
                ),
              ],
              Expanded(
                child: notes.when(
                  skipLoadingOnReload: true,
                  loading: () => const LoadingState(),
                  error: (e, _) =>
                      ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
                  data: (list) {
                    if (list.isEmpty) {
                      return EmptyState(
                        icon: _query.isEmpty
                            ? LucideIcons.stickyNote
                            : LucideIcons.searchX,
                        title: _query.isEmpty
                            ? 'No notes yet'
                            : 'Nothing matches',
                        message: _query.isEmpty
                            ? 'Anything you would write on the back of your hand.'
                            : 'No note mentions "$_query".',
                        action: _query.isNotEmpty
                            ? null
                            : EmptyAction(
                                label: 'Write one',
                                icon: LucideIcons.plus,
                                onTap: () => _open(context, null),
                              ),
                      );
                    }
                    return _Board(
                      notes: list,
                      grid: _grid,
                      selected: _selected,
                      selecting: _selecting,
                      onTap: (n) => _selecting ? _toggle(n) : _open(context, n),
                      onLongPress: (n) {
                        HapticFeedback.selectionClick();
                        _toggle(n);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Lifted by the footer's height: since the body extends under the glass
        // footer, a FAB anchored to the raw bottom sat behind it, invisible.
        // Hidden while selecting — writing a new note is not one of the verbs
        // that applies to the ones already ticked.
        floatingActionButton: _selecting
            ? null
            : Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: FloatingActionButton(
                  onPressed: () => _open(context, null),
                  backgroundColor: AppColors.action,
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  child: const Icon(LucideIcons.plus, size: 26),
                ),
              ),
      ),
    );
  }

  /// One verb, applied to every ticked note.
  Future<void> _bulk(String action, List<Note> picked) async {
    if (picked.isEmpty) return;
    final repo = ref.read(repoProvider);

    switch (action) {
      case 'pin':
      case 'unpin':
        for (final n in picked) {
          await repo.setNotePinned(n.id, action == 'pin');
        }
      case 'colour':
        final tint = await _pickTint(picked.first.tint);
        if (tint == null) return;
        for (final n in picked) {
          await repo.setNoteTint(n.id, tint);
        }
        // The colour sheet is the one action worth staying in selection for:
        // seeing the result and picking again is the whole point.
        bumpRefresh(ref);
        return;
      case 'copy':
        for (final n in picked) {
          await repo.duplicateNote(n.id);
        }
      case 'text':
        final text = picked
            .map(
              (n) => [
                if (n.title.trim().isNotEmpty) n.title.trim(),
                n.body.trim(),
              ].where((s) => s.isNotEmpty).join('\n'),
            )
            .join('\n\n');
        await Clipboard.setData(ClipboardData(text: text));
        _clearSelection();
        if (mounted) showSnack(context, 'Copied.');
        return;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              picked.length == 1
                  ? 'Delete this note?'
                  : 'Delete ${picked.length} notes?',
            ),
            content: const Text('They cannot be brought back.'),
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
        for (final n in picked) {
          await repo.deleteNote(n.id);
        }
    }

    bumpRefresh(ref);
    _clearSelection();
    if (!mounted) return;
    final word = switch (action) {
      'pin' => 'pinned',
      'unpin' => 'unpinned',
      'copy' => 'copied',
      _ => 'deleted',
    };
    showSnack(
      context,
      '${picked.length} note${picked.length == 1 ? '' : 's'} $word.',
    );
  }

  Future<int?> _pickTint(int current) => showModalBottomSheet<int>(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Text(
                'Colour',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: AppColors.ink,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
              child: Row(
                children: [
                  for (var i = 0; i < NoteTints.swatches.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _Swatch(
                        index: i,
                        selected: current == i,
                        onTap: () => Navigator.pop(ctx, i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The header while notes are ticked: how many, and what can be done to them.
class _NoteSelectionBar extends StatelessWidget {
  const _NoteSelectionBar({
    required this.count,
    required this.allPinned,
    required this.onClose,
    required this.onAction,
    required this.onSelectAll,
  });

  final int count;

  /// Pin is a toggle, so the button shows the move that is left to make.
  final bool allPinned;
  final VoidCallback onClose;
  final ValueChanged<String> onAction;
  final VoidCallback onSelectAll;

  /// The same white bar as the header it replaces, status-bar inset included.
  /// As a bare row it was drawn under the clock and the battery — the ordinary
  /// header takes that inset itself, and swapping it out swapped the inset out
  /// with it.
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
        const SizedBox(width: 14),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: AppColors.ink,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const Spacer(),
        Semantics(
          label: allPinned ? 'Unpin' : 'Pin to the top',
          button: true,
          child: RoundAction(
            icon: allPinned ? LucideIcons.pinOff : LucideIcons.pin,
            onPressed: () => onAction(allPinned ? 'unpin' : 'pin'),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: 'Change colour',
          button: true,
          child: RoundAction(
            icon: LucideIcons.palette,
            onPressed: () => onAction('colour'),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: 'Delete',
          button: true,
          child: RoundAction(
            icon: LucideIcons.trash2,
            onPressed: () => onAction('delete'),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: 'More',
          button: true,
          child: RoundAction(
            icon: LucideIcons.ellipsisVertical,
            onPressed: () => _more(context),
          ),
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
                icon: LucideIcons.copy,
                label: count == 1 ? 'Make a copy' : 'Make copies',
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              _MoreRow(
                icon: LucideIcons.clipboardCopy,
                label: 'Copy text',
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
              _MoreRow(
                icon: LucideIcons.listChecks,
                label: 'Select all',
                onTap: () => Navigator.pop(ctx, 'all'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    if (choice == 'all') {
      onSelectAll();
      return;
    }
    onAction(choice);
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.ink),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The notes, either as a wall of cards or as a list of compact rows.
///
/// The wall is a fixed two-column grid: every note holds the same tile whatever
/// is in it. Sizing cards to their content balanced nicely with long notes and
/// collapsed a nearly-empty one to a lozenge that drifted around as its
/// neighbours changed; on the wall a note keeps its place and its size, and the
/// content fills what fits.
///
/// The list is not that grid with one column — that made every note as tall as
/// the tallest one needs to be, so "Celario buyer" took a third of the screen
/// with nothing in the middle of it. A list is for scanning, so each note gets
/// one line of heading and one of everything else, and nothing more.
class _Board extends StatelessWidget {
  const _Board({
    required this.notes,
    required this.grid,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final List<Note> notes;

  /// Two columns of cards (the wall) or a run of compact rows (the list).
  final bool grid;

  final Set<int> selected;
  final bool selecting;
  final ValueChanged<Note> onTap;
  final ValueChanged<Note> onLongPress;

  @override
  Widget build(BuildContext context) {
    final pinned = notes.where((n) => n.pinned).toList();
    final rest = notes.where((n) => !n.pinned).toList();

    Widget sliverOf(List<Note> list) => grid
        ? SliverToBoxAdapter(
            child: _Masonry(
              notes: list,
              selected: selected,
              selecting: selecting,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
          )
        : SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _NoteRow(
              note: list[i],
              selected: selected.contains(list[i].id),
              selecting: selecting,
              onTap: () => onTap(list[i]),
              onLongPress: () => onLongPress(list[i]),
            ),
          );

    // Headings only once something is pinned — otherwise "Others" would be
    // the label on a board with nothing to be other than.
    return CustomScrollView(
      slivers: [
        if (pinned.isNotEmpty) ...[
          const SliverToBoxAdapter(child: _BoardLabel('Pinned')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: sliverOf(pinned),
          ),
          if (rest.isNotEmpty)
            const SliverToBoxAdapter(child: _BoardLabel('Others')),
        ],
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            pinned.isEmpty ? 4 : 0,
            16,
            footerClearance(context) + 72,
          ),
          sliver: sliverOf(rest),
        ),
      ],
    );
  }
}

/// Two columns of cards that hug their content, the way Keep lays a wall.
///
/// The first board was a fixed-aspect grid, which handed every note the same
/// tall box — a two-word note was four-fifths air, and the whole screen read
/// as emptiness with headings. Here each card is as tall as what is written
/// on it, and notes go to whichever column is currently shorter (estimated
/// from their line count), so the two columns stay level without measuring.
class _Masonry extends StatelessWidget {
  const _Masonry({
    required this.notes,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final List<Note> notes;
  final Set<int> selected;
  final bool selecting;
  final ValueChanged<Note> onTap;
  final ValueChanged<Note> onLongPress;

  /// Rough card height in "lines": title, body lines (capped like the card
  /// caps them), the footer. Only the balance matters, not the unit.
  int _weight(Note n) {
    final body = n.body
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .length
        .clamp(0, 8);
    return 2 + (n.title.trim().isEmpty ? 0 : 2) + body;
  }

  @override
  Widget build(BuildContext context) {
    final left = <Note>[];
    final right = <Note>[];
    var leftWeight = 0;
    var rightWeight = 0;
    for (final n in notes) {
      if (leftWeight <= rightWeight) {
        left.add(n);
        leftWeight += _weight(n);
      } else {
        right.add(n);
        rightWeight += _weight(n);
      }
    }

    Widget column(List<Note> list) => Expanded(
      child: Column(
        children: [
          for (final n in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NoteCard(
                note: n,
                selected: selected.contains(n.id),
                selecting: selecting,
                onTap: () => onTap(n),
                onLongPress: () => onLongPress(n),
              ),
            ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [column(left), const SizedBox(width: 10), column(right)],
    );
  }
}

class _BoardLabel extends StatelessWidget {
  const _BoardLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

/// The tints a note can carry — the Keep palette the user asked for: soft
/// pastels across the whole wheel, plus the app's own glass default and one
/// dark card. Ink text sits on all of the pastels, so any note stays legible
/// whatever colour it wears.
class NoteTints {
  static const swatches = <(Color background, Color foreground)>[
    // Opaque near-white, not the translucent glass: the editor paints a
    // whole screen with this, and alpha over a bare route composites on
    // black — the "why is my note grey" bug.
    (AppColors.cardHigh, AppColors.ink),
    (Color(0xFFF6B0A8), AppColors.ink), // coral
    (Color(0xFFF2A76C), AppColors.ink), // orange
    (Color(0xFFFBF1A9), AppColors.ink), // yellow
    (Color(0xFFDFF0C8), AppColors.ink), // green
    (Color(0xFFBBDED4), AppColors.ink), // teal
    (Color(0xFFD3E4EE), AppColors.ink), // pale blue
    (Color(0xFFAFCBDE), AppColors.ink), // blue
    (Color(0xFFD5C0DE), AppColors.ink), // lilac
    (Color(0xFFF7E1DC), AppColors.ink), // blush
    (Color(0xFFE9E3D3), AppColors.ink), // sand
    (AppColors.ink, Colors.white), // dark
  ];

  static (Color, Color) of(int index) =>
      swatches[index.clamp(0, swatches.length - 1)];
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = NoteTints.of(note.tint);
    final muted = fg == Colors.white
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.inkMuted;
    final lines = note.body
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map(NoteLine.parse)
        .take(8)
        .toList();

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            // A ticked note wears a heavy ink outline — the card keeps its own
            // colour, which is what makes a mixed selection readable.
            border: selected
                ? Border.all(color: AppColors.ink, width: 2.5)
                : note.tint == 0
                ? Border.all(color: AppColors.glassEdge)
                : null,
          ),
          padding: EdgeInsets.fromLTRB(
            selected ? 14 : 16,
            selected ? 13 : 15,
            selected ? 14 : 16,
            selected ? 13 : 15,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.title.trim().isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        note.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: fg,
                        ),
                      ),
                    ),
                    if (note.pinned)
                      Icon(LucideIcons.pin, size: 15, color: muted),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // The card hugs its lines — the first eight of them, each capped
              // at a few rows — so a two-word note is a small card, not a tall
              // box of air with two words at the top.
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: line.checkable
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              line.done
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.circle,
                              size: 15,
                              color: line.done ? fg : muted,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                line.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: line.done ? muted : fg,
                                  decoration: line.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: muted,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          line.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: note.title.trim().isEmpty ? fg : muted,
                          ),
                        ),
                ),
              if (lines.isNotEmpty) const SizedBox(height: 8),
              Row(
                children: [
                  // A note about somebody names them. A bare person glyph
                  // said "this belongs to someone" and left you to guess
                  // which, which is worse than saying nothing.
                  if (note.about != null) ...[
                    Icon(LucideIcons.user, size: 11, color: muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        note.about!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      formatTimestamp(note.updatedAt),
                      textAlign: note.about != null
                          ? TextAlign.right
                          : TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  // While a selection is running, every card shows its state:
                  // a filled tick or the empty ring it would become.
                  if (selecting)
                    Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: selected ? fg : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? fg : muted,
                          width: 1.4,
                        ),
                      ),
                      child: selected
                          ? Icon(LucideIcons.check, size: 12, color: bg)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One note as a single compact row: a heading, and a line under it holding
/// whatever else is worth knowing at a glance.
///
/// The row is as tall as its two lines and no taller, so a one-word note takes
/// one row's worth of screen. Everything the card shows is still here, folded
/// onto the second line — the body preview, who it is about, how long ago, and
/// how much of a checklist is left.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = NoteTints.of(note.tint);
    final muted = fg == Colors.white
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.inkMuted;

    final lines = note.body
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map(NoteLine.parse)
        .toList();

    // A note without a title borrows its first line as one, rather than
    // leading with an empty space where the heading would be.
    final titled = note.title.trim().isNotEmpty;
    final heading = titled
        ? note.title.trim()
        : lines.isEmpty
        ? 'Untitled'
        : lines.first.text;
    final body = titled ? lines : lines.skip(1).toList();

    // A checklist reduces to how much of it is left; the items themselves are
    // one tap away and would not fit on a line anyway.
    final items = body.where((l) => l.checkable).toList();
    final done = items.where((l) => l.done).length;
    final preview = body
        .where((l) => !l.checkable)
        .map((l) => l.text)
        .join('  ·  ');

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: selected
                ? Border.all(color: AppColors.ink, width: 2.5)
                : note.tint == 0
                ? Border.all(color: AppColors.glassEdge)
                : null,
          ),
          padding: EdgeInsets.fromLTRB(
            selected ? 12.5 : 14,
            selected ? 10.5 : 12,
            selected ? 12.5 : 14,
            selected ? 10.5 : 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: fg,
                            ),
                          ),
                        ),
                        if (note.pinned) ...[
                          const SizedBox(width: 6),
                          Icon(LucideIcons.pin, size: 13, color: muted),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          formatTimestamp(note.updatedAt),
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                    // Nothing under the heading for a note that is only a
                    // heading — an empty second line is the bulk we came here
                    // to get rid of.
                    if (note.about != null ||
                        items.isNotEmpty ||
                        preview.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (note.about != null) ...[
                            Icon(LucideIcons.user, size: 11, color: muted),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                note.about!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: fg,
                                ),
                              ),
                            ),
                            if (items.isNotEmpty || preview.isNotEmpty)
                              Text(
                                '  ·  ',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                          ],
                          if (items.isNotEmpty) ...[
                            Icon(
                              done == items.length
                                  ? LucideIcons.checkCircle
                                  : LucideIcons.circle,
                              size: 11,
                              color: muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$done/${items.length}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (preview.isNotEmpty)
                              Text(
                                '  ·  ',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                          ],
                          if (preview.isNotEmpty)
                            Expanded(
                              child: Text(
                                preview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: muted),
                              ),
                            )
                          else
                            const Spacer(),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (selecting) ...[
                const SizedBox(width: 12),
                Container(
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: selected ? fg : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? fg : muted,
                      width: 1.4,
                    ),
                  ),
                  child: selected
                      ? Icon(LucideIcons.check, size: 12, color: bg)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Write or edit one note. Saves on the way out — a note app that loses what
/// you typed because you pressed back is not a note app.
class NoteEditorScreen extends ConsumerStatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.note,
    this.contactId,
    this.initialBody,
  });

  final Note? note;

  /// Who this note is about, when it is being written from inside a
  /// conversation. Only used when creating; an existing note keeps whoever it
  /// already belongs to.
  final int? contactId;

  /// A first line handed in from outside — the after-call nudge starts the
  /// note with "Call · 14:32 · 4 min" so only the substance needs typing.
  final String? initialBody;

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late int _tint;
  late bool _pinned;
  int? _id;
  bool _deleted = false;

  /// Who the note is about — from the note when editing one, from the caller
  /// when writing a new one inside a conversation.
  int? get _contactId => widget.note?.contactId ?? widget.contactId;

  @override
  void initState() {
    super.initState();
    _id = widget.note?.id;
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(
      text: widget.note?.body ?? widget.initialBody ?? '',
    );
    _tint = widget.note?.tint ?? 0;
    _pinned = widget.note?.pinned ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_deleted) return;
    final title = _title.text.trim();
    final body = _body.text.trimRight();
    if (title.isEmpty && body.trim().isEmpty) {
      // Nothing was written. An empty note is not worth a row, and deleting one
      // the user never filled in is not a loss.
      if (_id != null) await ref.read(repoProvider).deleteNote(_id!);
      return;
    }
    _id = await ref
        .read(repoProvider)
        .saveNote(
          id: _id,
          title: title,
          body: body,
          tint: _tint,
          pinned: _pinned,
          contactId: widget.note?.contactId ?? widget.contactId,
        );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this note?'),
        content: const Text('It cannot be brought back.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _deleted = true;
    if (_id != null) await ref.read(repoProvider).deleteNote(_id!);
    if (mounted) Navigator.of(context).pop();
  }

  /// Adds a checklist item at the cursor, so a list can be started without
  /// knowing that "- " is what makes one.
  /// The checklist button, on whichever line the cursor is on.
  ///
  /// Plain line becomes an item, open item becomes done, done item becomes
  /// plain again. It used to only ever insert "- ", which meant marking
  /// something done required knowing that "x " is what does that — a piece of
  /// syntax the editor had to explain in a paragraph of hint text nobody
  /// should have to read to tick a box.
  void _toggleItem() {
    final text = _body.text;
    final at = _body.selection.isValid
        ? _body.selection.end.clamp(0, text.length)
        : text.length;

    final lineStart = text.lastIndexOf('\n', at == 0 ? 0 : at - 1) + 1;
    final nextBreak = text.indexOf('\n', at);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    final line = text.substring(lineStart, lineEnd);
    final parsed = NoteLine.parse(line);

    final String replacement;
    if (!parsed.checkable) {
      replacement = '- $line';
    } else if (!parsed.done) {
      replacement = 'x ${parsed.text}';
    } else {
      replacement = parsed.text;
    }

    final moved = replacement.length - line.length;
    _body.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, replacement),
      selection: TextSelection.collapsed(
        offset: (at + moved).clamp(lineStart, lineStart + replacement.length),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = NoteTints.of(_tint);
    final dark = fg == Colors.white;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: fg,
          iconTheme: IconThemeData(color: fg),
          title: Text(
            widget.note == null ? 'New note' : 'Note',
            style: TextStyle(color: fg),
          ),
          actions: [
            IconButton(
              tooltip: _pinned ? 'Unpin' : 'Pin to the top',
              icon: Icon(
                _pinned ? LucideIcons.pin : LucideIcons.pin,
                color: fg,
              ),
              onPressed: () => setState(() => _pinned = !_pinned),
            ),
            if (widget.note != null)
              IconButton(
                icon: Icon(LucideIcons.trash2, color: fg),
                onPressed: _delete,
              ),
          ],
        ),
        body: Column(
          children: [
            // Who this note is about, with the two things you would want to do
            // next. A note that knows the person but cannot reach them is a
            // dead end, and the number itself is half of what gets written
            // down anyway.
            if (_contactId != null) _AboutStrip(contactId: _contactId!, fg: fg),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: fg,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: fg.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _body,
                      maxLines: null,
                      minLines: 12,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(fontSize: 15, height: 1.5, color: fg),
                      decoration: InputDecoration(
                        hintText: 'Write anything.',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: fg.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.12)
                          : AppColors.hairline,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(LucideIcons.listChecks, color: fg),
                      onPressed: _toggleItem,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < NoteTints.swatches.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _Swatch(
                                  index: i,
                                  selected: _tint == i,
                                  onTap: () => setState(() => _tint = i),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The person a note is about, across the top of the editor: their name,
/// their number, and the two buttons that do something about it.
class _AboutStrip extends ConsumerWidget {
  const _AboutStrip({required this.contactId, required this.fg});

  final int contactId;

  /// The note's own foreground, so the strip reads on any tint including the
  /// dark one.
  final Color fg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactProvider(contactId)).valueOrNull;
    if (contact == null) return const SizedBox.shrink();
    final muted = fg == Colors.white
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.inkMuted;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          // Tapping the person opens the conversation — the note usually
          // exists because of something said in it.
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ThreadScreen(contactId: contactId),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.user, size: 15, color: muted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            contact.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: fg,
                            ),
                          ),
                          // The number in full. It is half of what gets
                          // written on a note about somebody anyway.
                          Text(
                            contact.phoneLocal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _Act(
            icon: LucideIcons.phone,
            label: 'Call ${contact.display}',
            colour: fg,
            onTap: () async {
              final error = await SmsChannel.openExternal(
                'tel:${contact.phoneE164}',
              );
              if (error != null && context.mounted) {
                showSnack(context, error, error: true);
              }
            },
          ),
          _Act(
            icon: LucideIcons.messageSquare,
            label: 'Message ${contact.display}',
            colour: fg,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ThreadScreen(contactId: contactId),
              ),
            ),
          ),
          _Act(
            icon: LucideIcons.copy,
            label: 'Copy number',
            colour: fg,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: contact.phoneE164));
              if (context.mounted) showSnack(context, 'Number copied.');
            },
          ),
        ],
      ),
    );
  }
}

class _Act extends StatelessWidget {
  const _Act({
    required this.icon,
    required this.label,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      color: colour,
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = NoteTints.of(index);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? fg : AppColors.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected ? Icon(LucideIcons.check, size: 16, color: fg) : null,
      ),
    );
  }
}
