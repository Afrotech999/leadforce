import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';

/// Shared bits of chrome, so every screen has a real empty state and a real error
/// state instead of a dead end (spec 10).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Minimal on purpose: a thin glyph on a soft disc, a short title, one
    // quiet line. The old version drew the icon at 56px in the middle of the
    // screen, which made every empty state the loudest thing in the app.
    // A big pale glyph, a sentence in the app's own text colour, and one
    // outlined action under it — the shape of every empty state in HubSpot's
    // app. The glyph is drawn at the size an illustration would be and in the
    // palest ink on the palette, so it reads as a backdrop rather than as
    // something to look at.
    // Scrollable rather than a bare Column: this is a tall piece of furniture —
    // a 92px glyph, a title, a sentence and a button — and it is dropped into
    // whatever space is left over. Under the month calendar that space is a
    // couple of hundred pixels, and a Column simply overflows it. Scrolling
    // costs nothing when it fits and saves the screen when it does not.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 24, 40, 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 92, color: AppColors.muted),
                  const SizedBox(height: 26),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  if (action != null) const SizedBox(height: 24),
                  ?action,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: LucideIcons.alertCircle,
    title: 'Something went wrong',
    message: '$error',
    action: onRetry == null
        ? null
        : EmptyAction(label: 'Try again', onTap: onRetry!),
  );
}

/// The one button an empty state is allowed: a compact accent pill, sized to
/// its words. The theme's FilledButton is a full-width ink slab meant for the
/// bottom of a form — under two quiet lines of copy it was the loudest thing
/// on the screen.
class EmptyAction extends StatelessWidget {
  const EmptyAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  /// Outlined in orange with orange text, not a filled button: it is the only
  /// action on an otherwise empty screen, so it has to be findable without
  /// being the loudest thing the app can draw.
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(AppRadius.full),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.full),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: AppColors.action),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.actionDark),
              const SizedBox(width: 8),
            ],
            // Flexible, because this sits inside an empty state's padding on
            // a 360dp phone and a four-word label does not fit there.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.actionDark,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(),
    ),
  );
}

/// One consistent colour language for contact status across every screen.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.dense = false});

  final String status;
  final bool dense;

  static (Color, Color) _colors(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ContactStatus.notSent => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      ContactStatus.queued => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ContactStatus.sent => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      ContactStatus.delivered => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      ContactStatus.replied => (scheme.primary, scheme.onPrimary),
      ContactStatus.failed => (scheme.errorContainer, scheme.onErrorContainer),
      ContactStatus.doNotContact => (scheme.error, scheme.onError),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
  }

  static IconData iconFor(String status) => switch (status) {
    ContactStatus.notSent => LucideIcons.clock,
    ContactStatus.queued => LucideIcons.hourglass,
    ContactStatus.sent => LucideIcons.check,
    ContactStatus.delivered => LucideIcons.checkCheck,
    ContactStatus.replied => LucideIcons.reply,
    ContactStatus.failed => LucideIcons.alertCircle,
    ContactStatus.doNotContact => LucideIcons.ban,
    _ => LucideIcons.helpCircle,
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(context, status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(status), size: dense ? 12 : 14, color: fg),
          const SizedBox(width: 4),
          Text(
            ContactStatus.label(status),
            style: TextStyle(
              color: fg,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            // Muted, not the accent: these are signposts, not actions, and
            // charcoal at 11pt uppercase would compete with the row titles.
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Circular monogram, the way every messaging app does it.
class ContactAvatar extends ConsumerWidget {
  const ContactAvatar({
    super.key,
    required this.label,
    this.status,
    this.radius = 22,
    this.phone,
  });

  final String label;
  final String? status;
  final double radius;

  /// When given, the phone book's photo for this number replaces the initials.
  /// Left null on long lists — six thousand contacts is six thousand lookups.
  final String? phone;

  /// Stable per-contact colours, the way every phone app does it: bright
  /// enough to tell people apart at a glance, muted a step so a whole list
  /// of them still sits beside the periwinkle theme rather than shouting
  /// over it. No warm red — that would read as "missed call".
  static const _palette = [
    Color(0xFFD97A34), // orange
    Color(0xFF3492BD), // azure
    Color(0xFFAD3079), // magenta
    Color(0xFF6D9E3A), // green
    Color(0xFF5560B8), // indigo
    Color(0xFF2E8C7E), // teal
    Color(0xFF8A55B8), // purple
    Color(0xFFB88A2E), // amber
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final trimmed = label.trim();
    final photo = (phone == null || phone!.trim().isEmpty)
        ? null
        : ref.watch(contactPhotoProvider(phone!)).valueOrNull;
    final initials = trimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.substring(0, 1))
        .join()
        .toUpperCase();
    // A bare number gets the person glyph rather than a '#': the circle
    // should say "somebody", not "typo".
    final startsWithLetter =
        initials.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(initials);
    final bg = _palette[trimmed.hashCode.abs() % _palette.length];

    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: bg,
          foregroundImage: photo == null ? null : MemoryImage(photo),
          child: startsWithLetter
              ? Text(
                  initials,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.82,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Icon(
                  LucideIcons.userRound,
                  size: radius * 1.05,
                  color: Colors.white,
                ),
        ),
        if (status != null)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                StatusChip.iconFor(status!),
                size: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Another app's own launcher icon — WhatsApp's green, Telegram's blue.
///
/// Borrowed rather than redrawn: a hand-made copy of somebody's logo is
/// always slightly wrong, and the real one is one call away.
class AppIcon extends ConsumerWidget {
  const AppIcon({super.key, required this.package, this.size = 20});

  final String package;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(appIconProvider(package)).valueOrNull;
    if (bytes == null) {
      // Not installed, or the icon could not be drawn: a neutral mark keeps
      // the row's shape rather than collapsing it.
      return Icon(
        LucideIcons.messageSquare,
        size: size * 0.8,
        color: AppColors.inkMuted,
      );
    }
    return Image.memory(
      bytes,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// A person, wearing the badge of the app they wrote from — the way every
/// unified inbox says "this one came in on WhatsApp" without a word.
class AvatarWithApp extends StatelessWidget {
  const AvatarWithApp({
    super.key,
    required this.label,
    required this.package,
    this.radius = 19,
  });

  final String label;
  final String package;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: radius * 2,
    height: radius * 2,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        ContactAvatar(label: label, radius: radius),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: const BoxDecoration(
              color: AppColors.cardHigh,
              shape: BoxShape.circle,
            ),
            child: ClipOval(child: AppIcon(package: package, size: 15)),
          ),
        ),
      ],
    ),
  );
}

String formatTimestamp(int millis) {
  if (millis <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  if (sameDay) return '$hh:$mm';
  final yesterday = now.subtract(const Duration(days: 1));
  if (dt.year == yesterday.year &&
      dt.month == yesterday.month &&
      dt.day == yesterday.day) {
    return 'Yesterday';
  }
  return '${dt.day}/${dt.month}/${dt.year % 100}';
}

String formatDateTime(int millis) {
  if (millis <= 0) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${dt.day}/${dt.month}/${dt.year} $hh:$mm';
}

/// A snack with a way back out of what just happened. Archiving, in
/// particular, should never need an apology — only an Undo.
void showSnackAction(
  BuildContext context,
  String message, {
  required String actionLabel,
  required VoidCallback onAction,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
}

/// "today at 15:30", "tomorrow at 09:00", or "Tue 12 Aug at 09:00" — how a
/// person says when something will happen.
/// "Just now", "40 min ago", "2 hr ago" — and past twelve hours, the clock
/// time, because "19 hr ago" takes arithmetic to mean anything.
String timeAgoLabel(int millis) {
  if (millis <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - millis;
  final minutes = diff ~/ 60000;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 12) return '$hours hr ago';
  return formatTimestamp(millis);
}

String scheduleLabel(int millis) {
  final at = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final time =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'today at $time';
  if (day == today.add(const Duration(days: 1))) return 'tomorrow at $time';
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
  return '${weekdays[at.weekday - 1]} ${at.day} ${months[at.month - 1]} at $time';
}

/// Holds a fast-changing value still for a moment before anything acts on it.
///
/// Every search box in the app runs a `LIKE '%…%'` over the table behind it on
/// each keystroke. On six thousand contacts that is a full scan per letter, and
/// typing a name fires seven of them, of which only the last one's answer is
/// ever read. This waits for the typing to stop.
///
/// The delay is deliberately short. A search that lags behind the finger feels
/// broken, and a tenth of a second is under the threshold where anyone notices
/// a wait but over the one where a fast typist fires a query per letter.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 140)]);

  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Do it now, cancelling anything pending — for the submit key, where the
  /// user has said they are finished.
  void flush(VoidCallback action) {
    _timer?.cancel();
    action();
  }

  void dispose() => _timer?.cancel();
}

/// The search field: a filled pale-grey box with a glyph, the width of the
/// screen, sitting under a tab row or an app bar.
///
/// Every list screen had its own — a pill with a hairline, built inline five
/// times over with slightly different padding each time. This is the one from
/// HubSpot's Deals screen: square corners, no outline, the field colour doing
/// the containing.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search',
    this.onClear,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  /// Shown as an × once there is something to clear.
  final VoidCallback? onClear;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    padding: padding,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(LucideIcons.search, size: 19, color: AppColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 15, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                hintStyle: const TextStyle(
                  fontSize: 15,
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(LucideIcons.x, size: 17, color: AppColors.inkMuted),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The row of filter pills under a search field — "All Types 0 ⌄", "Sorted by
/// Due Date ⌄". Outlined in teal, scrolls sideways, never wraps.
class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.chips});

  final List<FilterChipSpec> chips;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: c.selected ? AppColors.accentSoft : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  onTap: c.onTap,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: c.selected ? AppColors.accent : AppColors.muted,
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: c.selected
                                ? FontWeight.w500
                                : FontWeight.w400,
                            color: c.selected
                                ? AppColors.accentDark
                                : AppColors.ink,
                          ),
                        ),
                        if (c.count != null) ...[
                          const SizedBox(width: 5),
                          Text(
                            '${c.count}',
                            style: TextStyle(
                              fontSize: 14,
                              color: c.selected
                                  ? AppColors.accentDark
                                  : AppColors.inkMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                        if (c.dropdown) ...[
                          const SizedBox(width: 4),
                          Icon(
                            LucideIcons.chevronDown,
                            size: 15,
                            color: c.selected
                                ? AppColors.accentDark
                                : AppColors.inkMuted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class FilterChipSpec {
  const FilterChipSpec({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
    this.dropdown = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int? count;

  /// Draws a chevron, for a chip that opens a menu rather than toggling.
  final bool dropdown;
}
