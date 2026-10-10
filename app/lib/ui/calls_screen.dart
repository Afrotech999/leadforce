import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/phone.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'contact_notes_screen.dart';
import 'footer.dart';
import 'kit.dart';
import 'notes_screen.dart';
import 'thread_screen.dart';

/// The phone's call log, inside LeadForce — styled the way a phone app's Recents
/// screen is read: days as headings, one row per burst of calls with a
/// direction arrow per call, "40 min ago" instead of arithmetic, and a call
/// button on every row. The colours are LeadForce's own.
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
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
    final granted = ref.watch(callLogPermissionProvider).valueOrNull;
    final rows =
        ref.watch(recentCallsProvider).valueOrNull ??
        const <({RecentCall call, Contact? contact})>[];

    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? rows
        : rows
              .where(
                (r) =>
                    (r.contact?.display ?? '').toLowerCase().contains(q) ||
                    r.call.number.replaceAll(' ', '').contains(q),
              )
              .toList();
    final sections = _sectionsOf(matches);

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Your Calls',
              subtitle: 'Everyone who rang, and everyone you rang',
              showBack: Navigator.of(context).canPop(),
            ),
            if (granted == true)
              SearchField(
                controller: _search,
                hint: 'Search calls',
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
            Expanded(
              child: granted == false
                  ? _Gate(onChanged: () => bumpRefresh(ref))
                  : rows.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.phoneIncoming,
                      title: 'No calls yet',
                      message: 'Calls made and received show up here.',
                    )
                  : matches.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.searchX,
                      title: 'Nobody matches',
                      message: 'Try fewer letters.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async => bumpRefresh(ref),
                      child: ListView.builder(
                        // Clears the glass footer the tab lives above.
                        padding: EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          footerClearance(context),
                        ),
                        itemCount: sections.fold<int>(
                          0,
                          (n, s) => n + 1 + s.groups.length,
                        ),
                        itemBuilder: (context, i) {
                          var at = i;
                          for (final section in sections) {
                            if (at == 0) return _DayLabel(section.label);
                            at -= 1;
                            if (at < section.groups.length) {
                              return _Row(group: section.groups[at]);
                            }
                            at -= section.groups.length;
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One day's worth of call bursts.
class _Section {
  _Section(this.label);

  final String label;
  final groups = <_Group>[];
}

/// Consecutive calls with the same number on the same day, folded into one
/// row — three tries in a row is one story, not three rows of it.
class _Group {
  _Group({required this.number, required this.contact});

  final String number;
  final Contact? contact;
  final entries = <CallEntry>[];

  CallEntry get latest => entries.first;
}

String _dayLabel(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(dt, now)) return 'Today';
  if (sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return '${dt.day}/${dt.month}/${dt.year % 100}';
}

List<_Section> _sectionsOf(List<({RecentCall call, Contact? contact})> rows) {
  final sections = <_Section>[];
  for (final r in rows) {
    final day = _dayLabel(r.call.entry.date);
    if (sections.isEmpty || sections.last.label != day) {
      sections.add(_Section(day));
    }
    final section = sections.last;
    final key = normalizePhone(r.call.number) ?? r.call.number.trim();
    final last = section.groups.isEmpty ? null : section.groups.last;
    if (last != null &&
        (normalizePhone(last.number) ?? last.number.trim()) == key) {
      last.entries.add(r.call.entry);
    } else {
      section.groups.add(
        _Group(number: r.call.number, contact: r.contact)
          ..entries.add(r.call.entry),
      );
    }
  }
  return sections;
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 7),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

/// The permission ask, said plainly — this screen cannot pretend to work
/// without it.
class _Gate extends StatefulWidget {
  const _Gate({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool _blockedBySystem = false;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: LucideIcons.phoneIncoming,
    title: _blockedBySystem
        ? 'Android is blocking the prompt'
        : 'Your calls stay on this phone',
    message: _blockedBySystem
        ? 'The permission dialog was refused before, so Android will not '
              'show it again. In the settings page that just opened, tap '
              'Permissions → Call logs → Allow, then come back.'
        : 'LeadForce reads the call log on this phone only — to show your calls '
              'here and inside conversations. Nothing leaves the device.',
    action: EmptyAction(
      label: _blockedBySystem ? 'Open phone settings' : 'Allow call log',
      icon: _blockedBySystem ? LucideIcons.settings2 : LucideIcons.check,
      onTap: () async {
        if (_blockedBySystem) {
          await SmsChannel.openAppSettings();
          return;
        }
        final ok = await SmsChannel.requestCallLogPermission();
        if (!ok && mounted) {
          setState(() => _blockedBySystem = true);
          await SmsChannel.openAppSettings();
        }
        widget.onChanged();
      },
    ),
  );
}

class _Row extends ConsumerWidget {
  const _Row({required this.group});

  final _Group group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = group.latest;
    final who = group.contact?.display ?? group.number.trim();
    final missed = latest.isMissed;

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
            padding: const EdgeInsets.fromLTRB(14, 11, 6, 11),
            child: Row(
              children: [
                // The face is the person; tapping it opens their profile.
                // Tapping the rest of the row still opens the conversation.
                Semantics(
                  label: 'Open their profile',
                  button: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _profile(context, ref),
                    child: ContactAvatar(
                      label: who,
                      radius: 20,
                      phone: group.number,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.entries.length > 1
                            ? '$who (${group.entries.length})'
                            : who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: missed ? AppColors.danger : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          // One arrow per call in the burst, newest first —
                          // ↙ came in, ↗ went out, red never connected.
                          for (final e in group.entries.take(3)) ...[
                            Icon(
                              e.isOutgoing
                                  ? LucideIcons.arrowUpRight
                                  : LucideIcons.arrowDownLeft,
                              size: 13,
                              color: e.isMissed
                                  ? AppColors.danger
                                  : AppColors.inkMuted,
                            ),
                            const SizedBox(width: 2),
                          ],
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              [
                                timeAgoLabel(latest.date),
                                if (latest.length.isNotEmpty) latest.length,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: missed
                                    ? AppColors.danger
                                    : AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Accent, like every button that does the main thing — this
                // row exists to be written on.
                Semantics(
                  label: 'Write a note about this call',
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Material(
                      color: AppColors.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _note(context, ref),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            LucideIcons.stickyNote,
                            size: 16,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // And the reference's own verb: ring them back, right here.
                Semantics(
                  label: 'Call $who',
                  button: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () async {
                          final error = await SmsChannel.openExternal(
                            'tel:${group.number.trim()}',
                          );
                          if (error != null && context.mounted) {
                            showSnack(context, error, error: true);
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(
                            LucideIcons.phone,
                            size: 18,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The contact this burst belongs to — found, or created ad-hoc the same
  /// way composing to a new number does. Null when the "number" has no
  /// digits (some carriers log withheld callers as text).
  Future<int?> _contactId(WidgetRef ref) async {
    if (group.contact != null) return group.contact!.id;
    return ref.read(repoProvider).contactForCompose(group.number);
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final id = await _contactId(ref);
    if (id == null) {
      if (context.mounted) {
        showSnack(context, 'That caller has no number to open.');
      }
      return;
    }
    bumpRefresh(ref);
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ThreadScreen(contactId: id)));
  }

  Future<void> _profile(BuildContext context, WidgetRef ref) async {
    final id = await _contactId(ref);
    if (id == null) {
      if (context.mounted) {
        showSnack(context, 'That caller has no number to open.');
      }
      return;
    }
    final c = await ref.read(repoProvider).contactById(id);
    if (c == null || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ContactProfileScreen(contact: c)));
    bumpRefresh(ref);
  }

  Future<void> _note(BuildContext context, WidgetRef ref) async {
    final id = await _contactId(ref);
    if (id == null) {
      if (context.mounted) {
        showSnack(context, 'That caller has no number to attach a note to.');
      }
      return;
    }
    final e = group.latest;
    final line = [
      e.isMissed ? 'Missed call' : 'Call',
      scheduleLabel(e.date),
      if (e.length.isNotEmpty) e.length,
    ].join(' · ');
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(contactId: id, initialBody: '$line\n'),
      ),
    );
    bumpRefresh(ref);
  }
}
