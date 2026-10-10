import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// A month at a time, with a mark under every day that has something on it.
///
/// Hand-drawn rather than pulled from a package: a calendar is a grid, six
/// rows of seven, and the whole of it here is under two hundred lines. A
/// dependency would cost more to keep in step with this palette than it saves,
/// and this app ships with no network at all — every kilobyte is one the user
/// carries.
///
/// Weeks start on Monday, which is how a working week is counted here.
class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.onSelect,
    required this.onMonth,
    this.counts = const {},
    this.missed = const {},
  });

  /// Any day inside the month being shown.
  final DateTime month;

  /// The day whose list is below. Null shows the month with nothing picked.
  final DateTime? selected;

  final ValueChanged<DateTime> onSelect;

  /// -1 for the month before, +1 for the one after.
  final ValueChanged<int> onMonth;

  /// How many things are on each day, keyed by [dayKey].
  final Map<int, int> counts;

  /// Which days hold something already missed, so the mark can say so.
  final Set<int> missed;

  /// A day flattened to one comparable number — 20260806 — so a map of days
  /// needs no date arithmetic to look one up.
  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    // Monday is 1 in Dart, so this is how many blanks come before the 1st.
    final lead = first.weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final rows = ((lead + days) / 7).ceil();
    final today = DateUtils.dateOnly(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              _Arrow(
                icon: LucideIcons.chevronLeft,
                label: 'Previous month',
                onTap: () => onMonth(-1),
              ),
              Expanded(
                child: Text(
                  '${_months[month.month - 1]} ${month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ),
              _Arrow(
                icon: LucideIcons.chevronRight,
                label: 'Next month',
                onTap: () => onMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (var row = 0; row < rows; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (_) {
                        final n = row * 7 + col - lead + 1;
                        if (n < 1 || n > days) {
                          return const SizedBox(height: 44);
                        }
                        final date = DateTime(month.year, month.month, n);
                        final key = dayKey(date);
                        return _Day(
                          number: n,
                          isToday: date == today,
                          isSelected:
                              selected != null &&
                              DateUtils.isSameDay(selected, date),
                          count: counts[key] ?? 0,
                          missed: missed.contains(key),
                          onTap: () => onSelect(date),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, size: 20, color: AppColors.accentDark),
      ),
    ),
  );
}

/// One cell: the number, and under it a mark for what the day holds.
///
/// The mark is a dot per item up to three, then a dot with a count — a row of
/// eleven dots says less than "3+" does, and the point of a month view is to
/// see at a glance which days are busy.
class _Day extends StatelessWidget {
  const _Day({
    required this.number,
    required this.isToday,
    required this.isSelected,
    required this.count,
    required this.missed,
    required this.onTap,
  });

  final int number;
  final bool isToday;
  final bool isSelected;
  final int count;
  final bool missed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final markColour = missed ? AppColors.danger : AppColors.accent;

    return SizedBox(
      height: 44,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.ink
                    : isToday
                    ? AppColors.accentSoft
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isSelected
                      ? Colors.white
                      : isToday
                      ? AppColors.accentDark
                      : AppColors.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              height: 8,
              child: count == 0
                  ? null
                  : count <= 3
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < count; i++)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: markColour,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: markColour,
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
