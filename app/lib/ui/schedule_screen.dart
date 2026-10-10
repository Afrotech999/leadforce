import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';
import 'month_calendar.dart';
import 'thread_screen.dart';

/// The diary: viewings, meetings, call-backs.
///
/// A broker's actual job is being somewhere at three o'clock and remembering
/// to ring somebody back on Thursday. Everything here is local and alarm-backed
/// — the same machinery as a scheduled message, except it raises a notification
/// instead of sending anything.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// The month on show, and the day whose list is under it. Both start at
  /// today, because "what have I got on today" is the question this screen is
  /// opened to answer nine times in ten.
  DateTime _month = DateUtils.dateOnly(DateTime.now());
  DateTime? _day = DateUtils.dateOnly(DateTime.now());

  /// Month grid or the plain list of everything ahead. A calendar answers
  /// "when am I free?"; a list answers "what is next?". Both are worth having
  /// and neither replaces the other.
  bool _calendar = true;

  @override
  Widget build(BuildContext context) {
    final list =
        ref.watch(appointmentsProvider).valueOrNull ?? const <Appointment>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final overdue = list.where((a) => a.at < now).toList();
    final ahead = list.where((a) => a.at >= now).toList();

    // One pass over the diary builds both marks the calendar needs.
    final counts = <int, int>{};
    final missed = <int>{};
    for (final a in list) {
      final key = MonthCalendar.dayKey(
        DateTime.fromMillisecondsSinceEpoch(a.at),
      );
      counts[key] = (counts[key] ?? 0) + 1;
      if (a.at < now) missed.add(key);
    }

    final onDay = _day == null
        ? const <Appointment>[]
        : (list
              .where(
                (a) => DateUtils.isSameDay(
                  DateTime.fromMillisecondsSinceEpoch(a.at),
                  _day,
                ),
              )
              .toList()
            ..sort((x, y) => x.at.compareTo(y.at)));

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Your Schedule',
              actions: [
                RoundAction(
                  icon: _calendar ? LucideIcons.list : LucideIcons.calendarDays,
                  label: _calendar ? 'Show as a list' : 'Show the month',
                  onPressed: () => setState(() => _calendar = !_calendar),
                ),
              ],
            ),
            if (_calendar)
              MonthCalendar(
                month: _month,
                selected: _day,
                counts: counts,
                missed: missed,
                onSelect: (d) => setState(() => _day = d),
                onMonth: (delta) => setState(() {
                  _month = DateTime(_month.year, _month.month + delta);
                  // Moving the month clears the picked day rather than
                  // dragging it along: the 6th of one month has nothing to do
                  // with the 6th of the next, and a stale selection would show
                  // a list belonging to a month no longer on screen.
                  _day = null;
                }),
              ),
            Expanded(
              child: list.isEmpty && _calendar
                  ? _Quiet(
                      icon: LucideIcons.calendarCheck,
                      line: 'Nothing in the diary yet.',
                      action: () =>
                          showAppointmentSheet(context, ref, initialDay: _day),
                    )
                  : list.isEmpty
                  ? EmptyState(
                      icon: LucideIcons.calendarClock,
                      title: 'Nothing to remember',
                      message:
                          'Viewings, meetings, call-backs — anything you '
                          'want this phone to tap you on the shoulder about.',
                      action: EmptyAction(
                        label: 'Add one',
                        icon: LucideIcons.plus,
                        onTap: () => showAppointmentSheet(context, ref),
                      ),
                    )
                  : _calendar
                  ? _DayList(
                      day: _day,
                      appointments: onDay,
                      onAdd: () =>
                          showAppointmentSheet(context, ref, initialDay: _day),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      children: [
                        if (overdue.isNotEmpty) ...[
                          const _Label('Missed'),
                          for (final a in overdue) _Row(appointment: a),
                        ],
                        if (ahead.isNotEmpty) ...[
                          if (overdue.isNotEmpty) const _Label('Coming up'),
                          for (final a in ahead) _Row(appointment: a),
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
          // From the calendar, a new one starts on the day being looked at —
          // tapping the 14th and then + should mean "something on the 14th".
          onPressed: () => showAppointmentSheet(
            context,
            ref,
            initialDay: _calendar ? _day : null,
          ),
          backgroundColor: AppColors.action,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(LucideIcons.plus, size: 26),
        ),
      ),
    );
  }
}

/// What is on the picked day, under the month.
class _DayList extends StatelessWidget {
  const _DayList({
    required this.day,
    required this.appointments,
    required this.onAdd,
  });

  final DateTime? day;
  final List<Appointment> appointments;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    if (day == null) {
      return const _Quiet(
        icon: LucideIcons.calendarDays,
        line: 'Pick a day to see what is on it.',
      );
    }
    if (appointments.isEmpty) {
      return _Quiet(
        icon: LucideIcons.calendarCheck,
        line: '${dayLabel(day!)} is clear.',
        action: onAdd,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      children: [
        _Label(dayLabel(day!)),
        for (final a in appointments) _Row(appointment: a),
      ],
    );
  }
}

/// "Today", "Tomorrow", or "Thu 14 Aug" — how a day is said out loud.
String dayLabel(DateTime day) {
  final today = DateUtils.dateOnly(DateTime.now());
  final d = DateUtils.dateOnly(day);
  if (d == today) return 'Today';
  if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// A day with nothing on it. Quieter than the screen's empty state, because
/// an empty Tuesday is not an empty diary.
class _Quiet extends StatelessWidget {
  const _Quiet({required this.icon, required this.line, this.action});

  final IconData icon;
  final String line;
  final VoidCallback? action;

  /// Scrollable and centred, the same as [EmptyState] and for the same reason:
  /// with a month grid above it there are only a couple of hundred pixels left
  /// on a small phone, and a Column in that space overflows rather than gives.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: box.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 46, color: AppColors.muted),
                const SizedBox(height: 14),
                Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkMuted,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  EmptyAction(
                    label: 'Add one',
                    icon: LucideIcons.plus,
                    onTap: action!,
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
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

class _Row extends ConsumerWidget {
  const _Row({required this.appointment});

  final Appointment appointment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = appointment;
    final missed = a.isPast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: missed ? AppColors.dangerSoft : AppColors.glass,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: missed ? Colors.transparent : AppColors.glassEdge,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => showAppointmentSheet(context, ref, existing: a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          scheduleLabel(a.at),
                          if (a.who != null) 'with ${a.who}',
                          if (a.place != null) a.place!,
                        ].join(' · '),
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.3,
                          color: missed ? AppColors.danger : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (a.contactId != null)
                  Semantics(
                    label: 'Open the conversation',
                    button: true,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ThreadScreen(contactId: a.contactId!),
                        ),
                      ),
                      icon: const Icon(LucideIcons.messageSquare, size: 17),
                      color: AppColors.inkMuted,
                    ),
                  ),
                Semantics(
                  label: 'Mark done',
                  button: true,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await ref
                          .read(repoProvider)
                          .setAppointmentDone(a.id, true);
                      await SmsChannel.cancelAppointmentAlarm(id: a.id);
                      bumpRefresh(ref);
                      if (context.mounted) {
                        showSnackAction(
                          context,
                          'Done.',
                          actionLabel: 'Undo',
                          onAction: () async {
                            await ref
                                .read(repoProvider)
                                .setAppointmentDone(a.id, false);
                            if (a.remindAt >
                                DateTime.now().millisecondsSinceEpoch) {
                              await SmsChannel.scheduleAppointmentAlarm(
                                id: a.id,
                                atMillis: a.remindAt,
                              );
                            }
                            bumpRefresh(ref);
                          },
                        );
                      }
                    },
                    icon: const Icon(LucideIcons.check, size: 18),
                    color: AppColors.ink,
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

/// How long before the appointment to be told about it. The minute end is
/// deliberately dense — a viewing across town needs an hour's warning, but a
/// call-back needs five minutes', and the old list jumped straight from
/// fifteen minutes to an hour.
const _leadTimes = <(String label, int minutes)>[
  ('At the time', 0),
  ('5 min before', 5),
  ('10 min before', 10),
  ('15 min before', 15),
  ('30 min before', 30),
  ('1 hour before', 60),
  ('2 hours before', 120),
  ('1 day before', 1440),
];

/// Book one, or change one. [contactId] pre-fills who it is with — the usual
/// case, since these are made from inside a conversation.
Future<void> showAppointmentSheet(
  BuildContext context,
  WidgetRef ref, {
  Appointment? existing,
  int? contactId,
  String? contactName,

  /// The day the calendar was showing when + was pressed. Only the day — the
  /// time still starts at the next round hour, because tapping a date in a
  /// month view says nothing about the time of day.
  DateTime? initialDay,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AppointmentSheet(
    existing: existing,
    contactId: contactId ?? existing?.contactId,
    contactName: contactName ?? existing?.who,
    initialDay: initialDay,
  ),
);

class _AppointmentSheet extends ConsumerStatefulWidget {
  const _AppointmentSheet({
    this.existing,
    this.contactId,
    this.contactName,
    this.initialDay,
  });

  final Appointment? existing;
  final int? contactId;
  final String? contactName;
  final DateTime? initialDay;

  @override
  ConsumerState<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends ConsumerState<_AppointmentSheet> {
  late final TextEditingController _title;
  late final TextEditingController _place;
  late DateTime _at;
  late int _lead;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _place = TextEditingController(text: e?.place ?? '');
    _at = e != null
        ? DateTime.fromMillisecondsSinceEpoch(e.at)
        : _startOn(widget.initialDay);
    _lead = e == null ? 60 : ((e.at - e.remindAt) ~/ 60000).clamp(0, 1440);
    // Snap an odd stored lead onto the nearest offered one, so the chips can
    // show a selection rather than none.
    _lead = _leadTimes
        .map((l) => l.$2)
        .reduce((a, b) => (a - _lead).abs() <= (b - _lead).abs() ? a : b);
  }

  /// The next round hour — on [day] when the calendar handed one over, and
  /// at nine in the morning if that day is not today, since "the 14th" means
  /// a working hour on the 14th rather than this time of night on it.
  static DateTime _startOn(DateTime? day) {
    final now = DateTime.now();
    if (day == null || DateUtils.isSameDay(day, now)) {
      return DateTime(now.year, now.month, now.day, now.hour + 1);
    }
    return DateTime(day.year, day.month, day.day, 9);
  }

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Day',
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      helpText: 'Time',
    );
    if (!mounted || time == null) return;
    setState(() {
      _at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    final remindAt = _at.subtract(Duration(minutes: _lead));

    final id = await repo.saveAppointment(
      id: widget.existing?.id,
      contactId: widget.contactId,
      title: _title.text,
      place: _place.text,
      at: _at.millisecondsSinceEpoch,
      remindAt: remindAt.millisecondsSinceEpoch,
    );
    // Re-arm from scratch: editing an appointment moves its reminder, and a
    // stale alarm would fire at the old time.
    await SmsChannel.cancelAppointmentAlarm(id: id);
    if (remindAt.isAfter(DateTime.now())) {
      await SmsChannel.scheduleAppointmentAlarm(
        id: id,
        atMillis: remindAt.millisecondsSinceEpoch,
      );
    }
    bumpRefresh(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(
      context,
      remindAt.isAfter(DateTime.now())
          ? 'Saved — you will be reminded ${scheduleLabel(remindAt.millisecondsSinceEpoch)}.'
          : 'Saved.',
    );
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await ref.read(repoProvider).deleteAppointment(id);
    await SmsChannel.cancelAppointmentAlarm(id: id);
    bumpRefresh(ref);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: AppColors.glassCanvas,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
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
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                      child: Text(
                        widget.existing == null ? 'Remind me' : 'Reminder',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.6,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    if (widget.contactName != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
                        child: Text(
                          'with ${widget.contactName}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _Field(
                            controller: _title,
                            hint: 'Viewing, meeting, call them back…',
                            icon: LucideIcons.calendarClock,
                            autofocus: widget.existing == null,
                          ),
                          const SizedBox(height: 8),
                          _Field(
                            controller: _place,
                            hint: 'Where (optional)',
                            icon: LucideIcons.mapPin,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Material(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: _pickWhen,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                              border: Border.all(color: AppColors.glassEdge),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  LucideIcons.clock,
                                  size: 18,
                                  color: AppColors.inkMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    scheduleLabel(_at.millisecondsSinceEpoch),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  LucideIcons.chevronRight,
                                  size: 18,
                                  color: AppColors.inkMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 16, 22, 8),
                      child: Text(
                        'Remind me',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final (label, minutes) in _leadTimes)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _Chip(
                                label: label,
                                selected: _lead == minutes,
                                onTap: () => setState(() => _lead = minutes),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                      child: Row(
                        children: [
                          if (widget.existing != null) ...[
                            Material(
                              color: AppColors.dangerSoft,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                onTap: _delete,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 15,
                                  ),
                                  child: Icon(
                                    LucideIcons.trash2,
                                    size: 18,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Material(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                onTap: _saving ? null : _save,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _saving ? 'Saving…' : 'Save',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(color: AppColors.glassEdge),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: hint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              hintStyle: const TextStyle(
                fontSize: 15,
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.accent : AppColors.glass,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.glassEdge,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.ink : AppColors.inkMuted,
          ),
        ),
      ),
    ),
  );
}
