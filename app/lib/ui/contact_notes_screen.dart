import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'deal_sheet.dart';
import 'kit.dart';
import 'notes_screen.dart';
import 'schedule_screen.dart';
import 'tag_sheet.dart';
import 'thread_screen.dart';

/// One person, whole: who they are, the tags they wear, the deal in motion,
/// the reminders booked with them and every note written about them.
///
/// This is the page a tap on a person lands on from anywhere — the CRM's hub.
/// "Wants three bedrooms, max 8M, has bank approval, viewing Saturday" is the
/// difference between a broker and someone with a phone full of numbers, and
/// here it is one screen instead of four.
class ContactProfileScreen extends ConsumerWidget {
  const ContactProfileScreen({super.key, required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes =
        ref.watch(contactNotesProvider(contact.id)).valueOrNull ??
        const <Note>[];
    final bookings =
        ref.watch(contactAppointmentsProvider(contact.id)).valueOrNull ??
        const <Appointment>[];
    final deal = ref.watch(contactDealProvider(contact.id)).valueOrNull;
    final tags =
        ref.watch(contactTagsProvider(contact.id)).valueOrNull ?? const <Tag>[];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: contact.display,
              subtitle: contact.phoneLocal,
              actions: [
                RoundAction(
                  icon: LucideIcons.phone,
                  label: 'Call',
                  onPressed: () async {
                    final error = await SmsChannel.openExternal(
                      'tel:${contact.phoneE164}',
                    );
                    if (error != null && context.mounted) {
                      showSnack(context, error, error: true);
                    }
                  },
                ),
                RoundAction(
                  icon: LucideIcons.messageSquare,
                  label: 'Message',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ThreadScreen(contactId: contact.id),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                children: [
                  // Tags first: the fastest read of who this person is.
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final t in tags) _WornTag(name: t.name),
                        _AddTag(
                          first: tags.isEmpty,
                          onTap: () =>
                              showTagSheet(context, ref, contactId: contact.id),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (deal == null)
                    _StartDeal(
                      onTap: () => showDealSheet(
                        context,
                        ref,
                        contactId: contact.id,
                        contactName: contact.display,
                      ),
                    )
                  else
                    _DealCard(
                      deal: deal,
                      onEdit: () => showDealSheet(
                        context,
                        ref,
                        contactId: contact.id,
                        contactName: contact.display,
                        existing: deal,
                      ),
                      onStage: () => showDealStageSheet(context, ref, deal),
                    ),
                  if (bookings.isNotEmpty) ...[
                    _SectionLabel(
                      'Reminders',
                      action: LucideIcons.plus,
                      onAction: () => showAppointmentSheet(
                        context,
                        ref,
                        contactId: contact.id,
                        contactName: contact.display,
                      ),
                    ),
                    for (final b in bookings) _BookingRow(booking: b),
                  ] else
                    _SectionLabel(
                      'Reminders — none yet',
                      action: LucideIcons.plus,
                      onAction: () => showAppointmentSheet(
                        context,
                        ref,
                        contactId: contact.id,
                        contactName: contact.display,
                      ),
                    ),
                  if (notes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                      child: Text(
                        'Nothing written about them yet. What they want, '
                        'what they can spend, what you promised.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.inkMuted.withValues(alpha: 0.9),
                        ),
                      ),
                    )
                  else ...[
                    const _SectionLabel('Notes'),
                    for (final n in notes)
                      _NoteStrip(
                        note: n,
                        onTap: () => _write(context, ref, note: n),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: FloatingActionButton(
          onPressed: () => _write(context, ref),
          backgroundColor: AppColors.action,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(LucideIcons.plus, size: 26),
        ),
      ),
    );
  }

  Future<void> _write(BuildContext context, WidgetRef ref, {Note? note}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(note: note, contactId: contact.id),
      ),
    );
    bumpRefresh(ref);
  }
}

class _WornTag extends StatelessWidget {
  const _WornTag({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Text(
      name,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
  );
}

class _AddTag extends StatelessWidget {
  const _AddTag({required this.first, required this.onTap});

  /// With no tags yet the chip explains itself; afterwards a plus is enough.
  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.glass,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.glassEdge),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.tag, size: 13, color: AppColors.inkMuted),
            const SizedBox(width: 5),
            // Flexible: the long first-time wording must shorten on a narrow
            // screen rather than burst the chip.
            Flexible(
              child: Text(
                first ? 'Tag them — buyer, car, hot…' : 'Tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The deal, front and centre: what, where it stands, and for how much.
class _DealCard extends StatelessWidget {
  const _DealCard({
    required this.deal,
    required this.onEdit,
    required this.onStage,
  });

  final Deal deal;
  final VoidCallback onEdit;
  final VoidCallback onStage;

  @override
  Widget build(BuildContext context) {
    final price = birr(deal.price);
    final days = deal.daysInStage;

    return Material(
      color: AppColors.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(
                LucideIcons.handshake,
                size: 19,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deal.what,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (price.isNotEmpty) price,
                        if (deal.isOpen)
                          days == 0
                              ? 'moved today'
                              : '$days day${days == 1 ? '' : 's'} in this stage',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StageChip(stage: deal.stage, onTap: onStage),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartDeal extends StatelessWidget {
  const _StartDeal({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.glass,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: const BorderSide(color: AppColors.glassEdge),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Icon(LucideIcons.handshake, size: 19, color: AppColors.inkMuted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Start a deal — what are they buying?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
            Icon(LucideIcons.plus, size: 17, color: AppColors.inkMuted),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.action, this.onAction});

  final String text;
  final IconData? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.inkMuted,
            ),
          ),
        ),
        if (action != null)
          Semantics(
            label: 'Add',
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(action, size: 15, color: AppColors.inkMuted),
              ),
            ),
          ),
      ],
    ),
  );
}

class _BookingRow extends ConsumerWidget {
  const _BookingRow({required this.booking});

  final Appointment booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
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
          onTap: () => showAppointmentSheet(context, ref, existing: b),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.calendarClock,
                  size: 16,
                  color: AppColors.inkMuted,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        scheduleLabel(b.at),
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
      ),
    );
  }
}

/// A note as a wide strip rather than a board tile: here they are read down a
/// column, not scanned across a wall.
class _NoteStrip extends StatelessWidget {
  const _NoteStrip({required this.note, required this.onTap});

  final Note note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = NoteTints.of(note.tint);
    final muted = fg == Colors.white
        ? Colors.white.withValues(alpha: 0.62)
        : AppColors.inkMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: note.tint == 0
                  ? Border.all(color: AppColors.glassEdge)
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.title.trim().isNotEmpty)
                  Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: fg,
                    ),
                  ),
                if (note.body.trim().isNotEmpty) ...[
                  if (note.title.trim().isNotEmpty) const SizedBox(height: 4),
                  Text(
                    note.body.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: note.title.trim().isEmpty ? fg : muted,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  formatTimestamp(note.updatedAt),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
