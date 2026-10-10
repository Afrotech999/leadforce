import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/segments.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'contact_notes_screen.dart';
import 'forward_sheet.dart';
import 'kit.dart';
import 'linked_text.dart';
import 'notes_screen.dart';
import 'schedule_screen.dart';
import 'templates_sheet.dart';

/// One conversation (spec 10.5).
///
/// A reply sent from here goes through the same native sender as a campaign
/// message, with `campaign_id = null` so it never counts against campaign
/// statistics.
///
/// The chrome is the app's own, not the default AppBar: the earlier version
/// wore Material's stock colours here — grey status strip, green-ish default
/// bubbles — and stood out from every other screen for it. Bubbles are now ink
/// for what you sent and near-white for what came back, which is also the
/// highest-contrast reading of "mine" and "theirs" this palette has.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.contactId, this.initialText});

  final int contactId;

  /// Text the composer opens with — a forwarded message. Takes precedence over
  /// any saved draft, because it is the more recent intention.
  final String? initialText;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  Timer? _draftTimer;

  /// Held rather than read on demand: `dispose` saves the draft, and `ref` is
  /// already gone by the time dispose runs.
  late final Repo _repo = ref.read(repoProvider);

  /// The draft is only written after typing stops. Saving on every keystroke
  /// put a database write between the user and the next character.
  static const _draftDebounce = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    // Opening the thread clears its badge.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(repoProvider).markThreadRead(widget.contactId);
      if (mounted) bumpRefresh(ref);
    });
    _controller.addListener(_onChanged);
    _restore();
  }

  Future<void> _restore() async {
    final forwarded = widget.initialText?.trim();
    if (forwarded != null && forwarded.isNotEmpty) {
      _controller.text = forwarded;
      return;
    }
    final draft = await _repo.draftFor(widget.contactId);
    if (mounted && draft != null && _controller.text.isEmpty) {
      _controller.text = draft;
    }
  }

  void _onChanged() {
    setState(() {});
    _draftTimer?.cancel();
    _draftTimer = Timer(_draftDebounce, _saveDraft);
  }

  Future<void> _saveDraft() async {
    if (_sending) return;
    await _repo.saveDraft(widget.contactId, _controller.text);
    if (mounted) bumpRefresh(ref);
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    // Leaving the screen is the commonest way a draft is abandoned, and the
    // one moment the debounce would otherwise miss. Fire-and-forget: the
    // widget is going away and there is nothing left to await it.
    final text = _controller.text;
    if (!_sending) {
      _repo.saveDraft(widget.contactId, text).ignore();
    }
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = ref.watch(contactProvider(widget.contactId));
    final messages = ref.watch(messagesProvider(widget.contactId));
    final c = contact.valueOrNull;
    // Calls between the bubbles. Without the permission this is simply empty,
    // and the strip below the header offers to change that.
    final calls = c == null
        ? const <CallEntry>[]
        : ref.watch(callsForProvider(c.phoneE164)).valueOrNull ??
              const <CallEntry>[];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              contact: c,
              onBack: () => Navigator.of(context).pop(),
              onCall: c == null ? null : () => _call(c),
              onMore: c == null
                  ? null
                  : () => showThreadActions(context, ref, c),
              onProfile: c == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ContactProfileScreen(contact: c),
                        ),
                      );
                      if (mounted) bumpRefresh(ref);
                    },
            ),
            if (c != null &&
                c.isCampaign &&
                c.status == ContactStatus.doNotContact)
              const _QuietStrip(
                icon: LucideIcons.ban,
                text: 'Blocked — campaigns will never message them.',
              )
            else if (c != null && c.muted)
              const _QuietStrip(
                icon: LucideIcons.bellOff,
                text: 'Muted — their texts arrive silently.',
              ),
            if (c != null) _CallsOffer(),
            Expanded(
              child: messages.when(
                skipLoadingOnReload: true,
                loading: () => const LoadingState(),
                error: (e, _) => ErrorState(error: e),
                data: (list) {
                  final timeline = threadTimeline(list, calls);
                  if (timeline.isEmpty) {
                    return const EmptyState(
                      icon: LucideIcons.messageCircle,
                      title: 'No messages',
                      message:
                          'Nothing has been sent to or received from this contact yet.',
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                    itemCount: timeline.length,
                    itemBuilder: (context, i) {
                      final index = timeline.length - 1 - i;
                      final item = timeline[index];
                      // The separator belongs above the first item of each
                      // day; in a reversed list that is the one whose
                      // predecessor fell on a different date.
                      final previous = index == 0 ? null : timeline[index - 1];
                      final newDay =
                          previous == null || !_sameDay(previous.at, item.at);
                      return Column(
                        children: [
                          if (newDay) _DayDivider(millis: item.at),
                          if (item.message != null)
                            _Bubble(
                              message: item.message!,
                              onActions: () => showMessageActions(
                                context,
                                ref,
                                item.message!,
                              ),
                            )
                          else
                            _CallMarker(
                              call: item.call!,
                              onNote: c == null
                                  ? null
                                  : () => _noteAboutCall(c, item.call!),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (c != null) _ScheduledStrip(contactId: c.id),
            _Composer(
              controller: _controller,
              sending: _sending,
              onSend: () => _send(c),
              onSchedule: c == null ? null : () => _schedule(c),
              onTemplates: () => _templates(c),
            ),
          ],
        ),
      ),
    );
  }

  /// A saved sentence, dropped into the composer rather than sent outright —
  /// most of them get a word changed before they go.
  Future<void> _templates(Contact? c) async {
    final chosen = await showTemplatesSheet(
      context,
      name: c?.name,
      fillName: true,
      currentText: _controller.text,
    );
    if (chosen == null || !mounted) return;
    final existing = _controller.text.trimRight();
    _controller.text = existing.isEmpty ? chosen : '$existing\n$chosen';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _call(Contact c) async {
    final error = await SmsChannel.openExternal('tel:${c.phoneE164}');
    if (error != null && mounted) showSnack(context, error, error: true);
  }

  /// A note about one particular call, however old — the same editor the
  /// after-call nudge opens, with that call's facts as the first line.
  Future<void> _noteAboutCall(Contact c, CallEntry call) async {
    final line = [
      call.isMissed ? 'Missed call' : 'Call',
      scheduleLabel(call.date),
      if (call.length.isNotEmpty) call.length,
    ].join(' · ');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            NoteEditorScreen(contactId: c.id, initialBody: '$line\n'),
      ),
    );
    if (mounted) bumpRefresh(ref);
  }

  /// Send this one, later. The row in `scheduled_message` is the schedule; the
  /// alarm is only the wake-up call, so a reboot loses nothing.
  Future<void> _schedule(Contact c) async {
    final body = _controller.text.trim();
    if (body.isEmpty) {
      showSnack(context, 'Write the message first.');
      return;
    }
    final granted = await SmsChannel.requestSmsPermissions();
    if (!mounted) return;
    if (!granted) {
      showSnack(context, 'SMS permission is required to send.', error: true);
      return;
    }

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Day to send',
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: 'Time to send',
    );
    if (!mounted || time == null) return;

    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (at.isBefore(now.add(const Duration(minutes: 2)))) {
      showSnack(
        context,
        'Pick a time at least a couple of minutes away — or just send it.',
        error: true,
      );
      return;
    }

    final repo = ref.read(repoProvider);
    final id = await repo.scheduleMessage(
      contactId: c.id,
      body: body,
      sendAt: at.millisecondsSinceEpoch,
    );
    await SmsChannel.scheduleMessageAlarm(
      id: id,
      atMillis: at.millisecondsSinceEpoch,
    );
    _draftTimer?.cancel();
    _controller.clear();
    await repo.saveDraft(c.id, null);
    bumpRefresh(ref);
    if (!mounted) return;
    showSnack(
      context,
      'Will send ${scheduleLabel(at.millisecondsSinceEpoch)}.',
    );
  }

  Future<void> _send(Contact? contact) async {
    final body = _controller.text.trim();
    if (contact == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);

    try {
      final repo = ref.read(repoProvider);
      final subId = int.tryParse(
        await repo.getSetting(SettingKeys.simSubscriptionId, ''),
      );
      // Journal first, exactly like the campaign engine does.
      final messageId = await repo.journalOutbound(
        contactId: contact.id,
        body: body,
      );
      final error = await SmsChannel.sendOneOff(
        messageId: messageId,
        phone: contact.phoneE164,
        body: body,
        subId: subId,
      );
      // The draft became a message; clearing the box must clear the saved one
      // too or it comes back the next time the thread opens.
      _draftTimer?.cancel();
      _controller.clear();
      await repo.saveDraft(contact.id, null);
      bumpRefresh(ref);
      if (error != null && mounted) {
        showSnack(context, 'Could not send: $error', error: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

/// One row of the conversation: a message bubble or a call marker, in time
/// order. A tiny union rather than a class hierarchy — there are two cases
/// and they will stay two.
class ThreadItem {
  const ThreadItem.message(Message this.message) : call = null;
  const ThreadItem.call(CallEntry this.call) : message = null;

  final Message? message;
  final CallEntry? call;

  int get at => message?.createdAt ?? call!.date;
}

/// Messages and calls, merged oldest-first.
///
/// Pure and top-level so a test can hand it two lists and check the weave.
/// Both inputs arrive sorted (messages ASC, calls DESC from the log), so this
/// is one linear merge rather than a concatenate-and-sort.
List<ThreadItem> threadTimeline(List<Message> messages, List<CallEntry> calls) {
  final sortedCalls = calls.toList()..sort((a, b) => a.date.compareTo(b.date));
  final out = <ThreadItem>[];
  var m = 0, c = 0;
  while (m < messages.length || c < sortedCalls.length) {
    final takeMessage =
        c >= sortedCalls.length ||
        (m < messages.length && messages[m].createdAt <= sortedCalls[c].date);
    if (takeMessage) {
      out.add(ThreadItem.message(messages[m++]));
    } else {
      out.add(ThreadItem.call(sortedCalls[c++]));
    }
  }
  return out;
}

/// Everything you can do to a conversation, in one sheet.
///
/// Shared with the inbox's long-press so the two places offer the same verbs.
/// The old popup menu had exactly one item and hid it behind a three-dot
/// button; call, copy, unread, block and delete were simply missing.
Future<void> showThreadActions(
  BuildContext context,
  WidgetRef ref,
  Contact contact, {
  bool fromInbox = false,
}) async {
  final repo = ref.read(repoProvider);
  final blocked = contact.status == ContactStatus.doNotContact;

  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GlassSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Row(
              children: [
                ContactAvatar(label: contact.display, radius: 19),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        contact.phoneLocal,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          _SheetRow(
            icon: LucideIcons.phone,
            label: 'Call',
            onTap: () => Navigator.pop(ctx, 'call'),
          ),
          _SheetRow(
            icon: LucideIcons.copy,
            label: 'Copy number',
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          // The hub: their deal, tags, notes and reminders in one place.
          _SheetRow(
            icon: LucideIcons.user,
            label: 'Their profile — deal, notes, tags',
            onTap: () => Navigator.pop(ctx, 'notes'),
          ),
          _SheetRow(
            icon: LucideIcons.calendarClock,
            label: 'Remind me — viewing, call back…',
            onTap: () => Navigator.pop(ctx, 'book'),
          ),
          if (fromInbox)
            _SheetRow(
              icon: LucideIcons.mailOpen,
              label: 'Mark unread',
              onTap: () => Navigator.pop(ctx, 'unread'),
            ),
          if (contact.isCampaign)
            _SheetRow(
              icon: blocked ? LucideIcons.undo2 : LucideIcons.ban,
              label: blocked
                  ? 'Put back in the pool'
                  : 'Block — do not contact',
              onTap: () => Navigator.pop(ctx, blocked ? 'unblock' : 'block'),
            )
          else
            _SheetRow(
              icon: contact.muted ? LucideIcons.bell : LucideIcons.bellOff,
              label: contact.muted ? 'Unmute' : 'Mute — no notifications',
              onTap: () =>
                  Navigator.pop(ctx, contact.muted ? 'unmute' : 'mute'),
            ),
          _SheetRow(
            icon: LucideIcons.trash2,
            label: 'Delete conversation',
            danger: true,
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'call':
      final error = await SmsChannel.openExternal('tel:${contact.phoneE164}');
      if (error != null && context.mounted) {
        showSnack(context, error, error: true);
      }
    case 'copy':
      await Clipboard.setData(ClipboardData(text: contact.phoneE164));
      if (context.mounted) showSnack(context, 'Number copied.');
    case 'notes':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContactProfileScreen(contact: contact),
        ),
      );
      bumpRefresh(ref);
    case 'book':
      await showAppointmentSheet(
        context,
        ref,
        contactId: contact.id,
        contactName: contact.display,
      );
    case 'unread':
      await repo.setThreadUnread(contact.id, true);
      bumpRefresh(ref);
    case 'block':
      await repo.markDoNotContact(contact.id);
      bumpRefresh(ref);
      if (context.mounted) {
        showSnack(context, '${contact.display} will never be messaged again.');
      }
    case 'mute':
      await repo.setMuted(contact.id, true);
      bumpRefresh(ref);
      if (context.mounted) {
        showSnack(context, 'Muted. Their texts arrive without a sound.');
      }
    case 'unmute':
      await repo.setMuted(contact.id, false);
      bumpRefresh(ref);
      if (context.mounted) showSnack(context, 'Unmuted.');
    case 'unblock':
      await repo.reinstate(contact.id);
      await repo.generateBatches();
      bumpRefresh(ref);
      if (context.mounted) showSnack(context, 'Back in the pool.');
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this conversation?'),
          content: Text(
            'Every message with ${contact.display} is deleted from this app. '
            '${contact.isCampaign ? 'They stay on your list with their current status.' : ''}',
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
      await repo.deleteThread(contact.id);
      bumpRefresh(ref);
      if (!context.mounted) return;
      // From inside the thread there is nothing left to look at.
      if (!fromInbox) {
        Navigator.of(context).pop();
      }
      showSnack(context, 'Conversation deleted.');
  }
}

/// The sheet chrome the actions come up in: translucent canvas over a blur, so
/// the conversation stays faintly visible behind the choices about it.
class _GlassSheet extends StatelessWidget {
  const _GlassSheet({required this.child});

  final Widget child;

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
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
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
                letterSpacing: -0.2,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.contact,
    required this.onBack,
    required this.onCall,
    required this.onMore,
    this.onProfile,
  });

  final Contact? contact;
  final VoidCallback onBack;
  final VoidCallback? onCall;
  final VoidCallback? onMore;

  /// Tapping the person themselves — avatar or name — opens their profile,
  /// the way every messaging app does it.
  final VoidCallback? onProfile;

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          RoundAction(
            icon: LucideIcons.arrowLeft,
            label: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: onProfile,
              child: Row(
                children: [
                  ContactAvatar(
                    label: c?.display ?? '?',
                    status: (c?.isCampaign ?? false) ? c?.status : null,
                    radius: 21,
                    phone: c?.phoneE164,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c?.display ?? 'Conversation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: AppColors.ink,
                          ),
                        ),
                        if (c != null)
                          Text(
                            // Just the number. The campaign status used to sit
                            // beside it, and where every messaging app puts
                            // presence, "Not sent" read as "your message did
                            // not send" — the worst thing a chat header can
                            // appear to say. The status lives on the profile
                            // and in Contacts, where it means what it says.
                            c.phoneLocal,
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
                ],
              ),
            ),
          ),
          if (onCall != null) ...[
            const SizedBox(width: 8),
            RoundAction(
              icon: LucideIcons.phone,
              label: 'Call',
              onPressed: onCall!,
            ),
          ],
          if (onMore != null) ...[
            const SizedBox(width: 8),
            RoundAction(
              icon: LucideIcons.ellipsis,
              label: 'More',
              onPressed: onMore!,
            ),
          ],
        ],
      ),
    );
  }
}

/// A call, between the bubbles: small, centred, grey — punctuation in the
/// conversation, not a message pretending to be one.
class _CallMarker extends StatelessWidget {
  const _CallMarker({required this.call, this.onNote});

  final CallEntry call;

  /// Tap the pill to write a note about that call — the same note the
  /// after-call nudge offers, reachable for any call however old.
  final VoidCallback? onNote;

  @override
  Widget build(BuildContext context) {
    final icon = call.isMissed
        ? LucideIcons.phoneMissed
        : call.isOutgoing
        ? LucideIcons.phoneOutgoing
        : LucideIcons.phoneIncoming;
    final colour = call.isMissed ? AppColors.danger : AppColors.inkMuted;
    final text = [
      call.label,
      if (call.length.isNotEmpty) call.length,
      formatTimestamp(call.date),
    ].join(' · ');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Material(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onNote,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.glassEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: colour),
                  const SizedBox(width: 7),
                  Text(text, style: TextStyle(fontSize: 11.5, color: colour)),
                  if (onNote != null) ...[
                    const SizedBox(width: 7),
                    // The affordance: this pill does something.
                    Icon(
                      LucideIcons.stickyNote,
                      size: 11,
                      color: colour.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-time offer under the header: let LeadForce show your calls with this
/// person inside the conversation. Gone once granted, gone forever if closed.
class _CallsOffer extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final granted = ref.watch(callLogPermissionProvider).valueOrNull ?? true;
    if (granted) return const SizedBox.shrink();
    final dismissed =
        (ref.watch(settingsProvider).valueOrNull ??
            const {})[SettingKeys.callLogPromptDismissed] ==
        '1';
    if (dismissed) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.glassEdge),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.phoneIncoming,
            size: 15,
            color: AppColors.inkMuted,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Show your calls with them here?',
              style: TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
          TextButton(
            onPressed: () async {
              final ok = await SmsChannel.requestCallLogPermission();
              if (!ok && context.mounted) {
                // Two denials in and Android stops asking; settings is the
                // only door left. Same pattern as the phone book.
                showSnack(
                  context,
                  'Android is blocking the prompt — allow Call logs in the '
                  'settings page that just opened.',
                );
                await SmsChannel.openAppSettings();
              }
              bumpRefresh(ref);
            },
            child: const Text('Allow'),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await ref
                  .read(repoProvider)
                  .setSetting(SettingKeys.callLogPromptDismissed, '1');
              bumpRefresh(ref);
            },
            icon: const Icon(LucideIcons.x, size: 15),
            color: AppColors.inkMuted,
          ),
        ],
      ),
    );
  }
}

/// One thin line for a state worth interrupting the conversation for —
/// blocked, or muted.
class _QuietStrip extends StatelessWidget {
  const _QuietStrip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.danger),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
}

/// Chat text is deliberately not Poppins. Message bodies are the one place
/// the user reads other people's words at length, and WhatsApp trained every
/// eye in the market to read chats in Roboto at 16 — so that is what these
/// bubbles use. Roboto ships with Android; the Ethiopic fallback stays so an
/// Amharic reply renders in the right script, not in boxes.
const _chatFont = 'Roboto';
const _chatFallback = <String>[
  'Noto Sans Ethiopic',
  'Abyssinica SIL',
  'sans-serif',
];

/// Everything you can do to one message.
///
/// A long press used to copy the whole body and nothing else. Copy is still
/// the first row, because it is what the gesture was trained to do, but the
/// other four are what the gesture is actually for.
Future<void> showMessageActions(
  BuildContext context,
  WidgetRef ref,
  Message message,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GlassSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ),
          _SheetRow(
            icon: LucideIcons.copy,
            label: 'Copy text',
            onTap: () => Navigator.pop(ctx, 'copy'),
          ),
          _SheetRow(
            icon: LucideIcons.textCursorInput,
            label: 'Select text',
            onTap: () => Navigator.pop(ctx, 'select'),
          ),
          _SheetRow(
            icon: LucideIcons.forward,
            label: 'Forward',
            onTap: () => Navigator.pop(ctx, 'forward'),
          ),
          _SheetRow(
            icon: LucideIcons.info,
            label: 'Details',
            onTap: () => Navigator.pop(ctx, 'details'),
          ),
          _SheetRow(
            icon: LucideIcons.trash2,
            label: 'Delete message',
            danger: true,
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: message.body));
      if (context.mounted) showSnack(context, 'Message copied.');
    case 'select':
      if (context.mounted) await _showSelectable(context, message.body);
    case 'forward':
      if (context.mounted) await showForwardSheet(context, ref, message.body);
    case 'details':
      if (context.mounted) await _showDetails(context, message);
    case 'delete':
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this message?'),
          content: const Text(
            'It goes from this conversation only. The rest of the '
            'conversation stays.',
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
      await ref.read(repoProvider).deleteMessage(message.id);
      bumpRefresh(ref);
      if (context.mounted) showSnack(context, 'Message deleted.');
  }
}

/// Drag-to-select, on its own sheet.
///
/// Making the bubble itself selectable would fight the long press: the text
/// selection gesture and the actions gesture are the same gesture, and
/// whichever wins, the other becomes unreachable.
Future<void> _showSelectable(BuildContext context, String body) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hold a word, then drag',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    body,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.35,
                      color: AppColors.ink,
                      fontFamily: _chatFont,
                      fontFamilyFallback: _chatFallback,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// What actually happened to one message: when it left, when it landed, and
/// what it cost. Every number here is one the operator also counted.
Future<void> _showDetails(BuildContext context, Message message) {
  final rows = <(String, String)>[
    ('Direction', message.isInbound ? 'Received' : 'Sent'),
    ('Status', _statusLabel(message.status)),
    (
      message.isInbound ? 'Received' : 'Composed',
      formatDateTime(message.createdAt),
    ),
    if (!message.isInbound && message.sentAt != null)
      ('Left the phone', formatDateTime(message.sentAt!)),
    if (message.deliveredAt != null)
      ('Delivered', formatDateTime(message.deliveredAt!)),
    (
      'Billed as',
      '${message.segments} SMS segment${message.segments == 1 ? '' : 's'}',
    ),
    (
      'Part of',
      message.campaignId == null ? 'A personal message' : 'A campaign',
    ),
    if (message.error != null) ('Error', message.error!),
  ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _GlassSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'Message details',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: AppColors.ink,
                ),
              ),
            ),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: AppColors.ink,
                        ),
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

String _statusLabel(String status) => switch (status) {
  'pending' => 'Waiting for the network',
  'sent' => 'Sent',
  'delivered' => 'Delivered to the phone',
  'failed' => 'Failed',
  _ => status,
};

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onActions});

  final Message message;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final inbound = message.isInbound;
    final failed = message.status == 'failed';
    // Ink for what you sent, near-white for what came back — the same two
    // ends of the palette the rest of the app is built between. A failed send
    // drops to the danger tint so it does not pass as delivered.
    final bg = inbound
        ? AppColors.cardHigh
        : failed
        ? AppColors.dangerSoft
        : AppColors.ink;
    final fg = inbound || failed ? AppColors.ink : AppColors.onInk;
    final quiet = inbound || failed ? AppColors.inkMuted : AppColors.onInkMuted;

    return Align(
      alignment: inbound ? Alignment.centerLeft : Alignment.centerRight,
      // Hold a bubble for everything you can do with it — copy, select,
      // forward, details, delete.
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onActions();
        },
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(inbound ? 6 : 20),
              bottomRight: Radius.circular(inbound ? 20 : 6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LinkedText(
                text: message.body,
                style: TextStyle(
                  color: fg,
                  height: 1.32,
                  fontSize: 16,
                  fontFamily: _chatFont,
                  fontFamilyFallback: _chatFallback,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTimestamp(message.createdAt),
                    style: TextStyle(fontSize: 10.5, color: quiet),
                  ),
                  if (!inbound) ...[
                    const SizedBox(width: 4),
                    Icon(_icon(message.status), size: 12, color: quiet),
                  ],
                ],
              ),
              if (message.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    message.error!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.danger,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(String status) => switch (status) {
    'pending' => LucideIcons.clock,
    'sent' => LucideIcons.check,
    'delivered' => LucideIcons.checkCheck,
    'failed' => LucideIcons.alertCircle,
    _ => LucideIcons.helpCircle,
  };
}

/// Messages waiting on the clock, above the composer where they cannot be
/// forgotten — a scheduled message you cannot see is a scheduled message you
/// will be surprised by.
class _ScheduledStrip extends ConsumerWidget {
  const _ScheduledStrip({required this.contactId});

  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(scheduledMessagesProvider(contactId)).valueOrNull ??
        const <ScheduledMessage>[];
    if (pending.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in pending)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            padding: const EdgeInsets.fromLTRB(14, 9, 4, 9),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: AppColors.glassEdge),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.calendarClock,
                  size: 15,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        'Sends ${scheduleLabel(m.sendAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await ref.read(repoProvider).cancelScheduledMessage(m.id);
                    await SmsChannel.cancelMessageAlarm(id: m.id);
                    bumpRefresh(ref);
                    if (context.mounted) {
                      showSnack(context, 'Scheduled message cancelled.');
                    }
                  },
                  icon: const Icon(LucideIcons.x, size: 16),
                  color: AppColors.inkMuted,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The compose bar: glass over the conversation, a borderless field, and a
/// send button that turns accent the moment there is something to send.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onTemplates,
    this.onSchedule,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onTemplates;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final info = countSegments(controller.text);
    final hasText = controller.text.trim().isNotEmpty;
    final ready = hasText && !sending;

    // An opaque white strip with a hairline on top — the same furniture as the
    // app bar and the footer, not a blur. The glass composer was the last
    // translucent surface left after the re-skin, and it read as a leftover.
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5, right: 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${info.encodingLabel} · ${info.units}/${info.unitsPerSegment} · '
                      '${info.segments} SMS',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The sentences you send every day. First in the row
                  // because it is reached before typing, not after.
                  RoundAction(
                    icon: LucideIcons.zap,
                    label: 'Quick messages',
                    onPressed: onTemplates,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.canvas,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: TextField(
                        controller: controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.ink,
                          fontFamily: _chatFont,
                          fontFamilyFallback: _chatFallback,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                          hintStyle: TextStyle(
                            fontSize: 16,
                            color: AppColors.inkMuted,
                            fontFamily: _chatFont,
                            fontFamilyFallback: _chatFallback,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Send later, next to send. Only offered once there is
                  // something to schedule.
                  if (onSchedule != null && hasText) ...[
                    const SizedBox(width: 6),
                    RoundAction(
                      icon: LucideIcons.calendarClock,
                      label: 'Send this later',
                      onPressed: sending ? () {} : onSchedule!,
                    ),
                  ],
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'Send',
                    button: true,
                    child: Material(
                      color: ready ? AppColors.ink : AppColors.canvas,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: ready ? onSend : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  LucideIcons.arrowUp,
                                  size: 20,
                                  color: ready
                                      ? Colors.white
                                      : AppColors.inkMuted,
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
      ),
    );
  }
}

bool _sameDay(int a, int b) {
  final x = DateTime.fromMillisecondsSinceEpoch(a);
  final y = DateTime.fromMillisecondsSinceEpoch(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "Today" / "Yesterday" / a date, centred between the days of a conversation.
/// Plain quiet text — a tinted pill for every day made a calendar of a chat.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.millis});

  final int millis;

  String get _label {
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    if (_sameDay(millis, now.millisecondsSinceEpoch)) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (_sameDay(millis, yesterday.millisecondsSinceEpoch)) return 'Yesterday';
    return '${at.day}/${at.month}/${at.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        _label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: AppColors.inkMuted,
        ),
      ),
    ),
  );
}
