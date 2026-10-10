import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// The layout language, in one file so every screen is built from the same
/// parts rather than each inventing its own spacing.
///
/// Modelled on HubSpot's app: a white app bar with the page name at the left
/// and plain icon actions at the right, a pale page under it, and everything on
/// that page inside white cards with a one-pixel edge. Nothing floats, nothing
/// is translucent, and the only colours are navy text, teal for what is live or
/// tappable, and one orange action per screen.

/// The app bar at the top of a tab.
///
/// White, 56 high, hairline underneath, title at 20pt medium on the left and
/// the actions as bare glyphs on the right. The old header was a greeting over
/// a 34pt two-line title, which ate a third of the screen before any content —
/// handsome on a dashboard and wrong on a working tool, where the first row of
/// data should be visible without scrolling.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    this.greeting,
    required this.title,
    this.actions = const [],
  });

  /// Kept in the signature because a dozen screens pass it, but no longer drawn
  /// as a line of its own: it becomes the small grey line under the title where
  /// it says something the title does not.
  final String? greeting;

  /// The page name. One line — "Your Dashboard", not "Your / Dashboard".
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    // The status bar is part of the bar, painted the same white — which is why
    // the screens no longer inset their own top. Inside a SafeArea that has
    // already eaten the inset this reads zero, so both ways round are right.
    padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top, 8, 0),
    height: 56 + MediaQuery.paddingOf(context).top,
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
              if (greeting != null)
                Text(
                  greeting!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: AppColors.inkMuted,
                  ),
                ),
            ],
          ),
        ),
        for (final a in actions) a,
      ],
    ),
  );
}

/// An action in the app bar: a bare teal glyph with a wide tap target.
///
/// The circle around it is gone. A row of five outlined circles was five
/// competing shapes in the busiest 40 pixels of the screen; HubSpot draws the
/// glyph and nothing else, and the touch area does the work the circle used to.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.dot = false,
  });

  final IconData icon;
  final VoidCallback onPressed;

  /// What a screen reader says for this glyph. Without it TalkBack reads a
  /// row of five of these as "button, button, button, button, button" — a
  /// glyph is recognisable to an eye and mute to everything else. Optional
  /// only because some call sites wrap their own Semantics; every bare one
  /// should pass it.
  final String? label;

  /// A small dot, for "there is something waiting". A count would be louder
  /// than this corner of the screen deserves.
  final bool dot;

  @override
  Widget build(BuildContext context) =>
      Semantics(label: label, button: true, child: _body(context));

  Widget _body(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 22, color: AppColors.accentDark),
          ),
        ),
      ),
      if (dot)
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: AppColors.action,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.card, width: 1.5),
            ),
          ),
        ),
    ],
  );
}

/// The app bar on a pushed page: back arrow, title, optional line under it,
/// optional actions at the right.
///
/// Sixteen screens each built this row by hand — a RoundAction, a gap, a
/// Column with a 22pt title and an 11.5pt grey line — with slightly different
/// padding every time and no white bar behind any of them. One widget now, so
/// every page in the app is topped by the same 56 pixels.
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// Defaults to popping the route, which is what all but one caller wants.
  final VoidCallback? onBack;

  /// The listings shelf is a pushed page from one door and a tab from another,
  /// so
  /// it asks for the arrow only when there is something to go back to.
  final bool showBack;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    padding: EdgeInsets.fromLTRB(6, MediaQuery.paddingOf(context).top, 8, 0),
    height: 56 + MediaQuery.paddingOf(context).top,
    child: Row(
      children: [
        if (showBack)
          RoundAction(
            icon: LucideIcons.arrowLeft,
            label: 'Back',
            onPressed: onBack ?? () => Navigator.of(context).pop(),
          ),
        SizedBox(width: showBack ? 4 : 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.2,
                    color: AppColors.inkMuted,
                  ),
                ),
            ],
          ),
        ),
        for (final a in actions) a,
      ],
    ),
  );
}

/// The row of three outlined tiles under the app bar — Feed, Dashboards, Calls
/// in HubSpot, and the three places a broker actually starts here.
class QuickTiles extends StatelessWidget {
  const QuickTiles({super.key, required this.tiles});

  final List<QuickTile> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      children: [
        for (final t in tiles)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: t.onTap,
                  child: Container(
                    height: 78,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(t.icon, size: 23, color: AppColors.ink),
                            if (t.dot)
                              Positioned(
                                top: -2,
                                right: -4,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppColors.action,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class QuickTile {
  const QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dot;
}

/// A section heading over a card: a bold line, an optional grey line under it,
/// and a teal "View all" on the right. The pattern above every widget on
/// HubSpot's home screen.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accentDark,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A white card with an edge — the container everything on a page sits in.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
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
          padding: padding,
          child: child,
        ),
      ),
    ),
  );
}

/// `36 Tasks` — the figure and its name side by side in a pill, in a row that
/// scrolls. Reads as a sentence rather than as a chart.
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.value,
    required this.label,
    this.onTap,
    this.accent = false,
  });

  final String value;
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => Material(
    color: accent ? AppColors.accent : AppColors.glass,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      side: BorderSide(
        color: accent ? Colors.transparent : AppColors.glassEdge,
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1,
                fontWeight: FontWeight.w400,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A horizontal run of [StatPill]s, bleeding off the right edge so it is
/// obvious there is more to scroll to.
class StatPillRow extends StatelessWidget {
  const StatPillRow({super.key, required this.children});

  final List<Widget> children;

  /// The row sits clear of the bar above it. Pinned straight underneath, the
  /// figures read as part of the app bar rather than as the first thing on the
  /// page, and the whole screen felt crammed against the top of the phone.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => children[i],
      ),
    ),
  );
}

/// A borderless card with a quiet title and, optionally, a small action on the
/// right. No outline anywhere — the card is a shade lighter than the page and
/// that is the whole separation.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.action,
    this.onAction,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
  });

  final String? title;
  final IconData? action;
  final VoidCallback? onAction;
  final Widget child;
  final Color? color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    decoration: BoxDecoration(
      color: color ?? AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.glassEdge),
    ),
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (action != null)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAction,
                      child: Icon(action, size: 18, color: AppColors.inkMuted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        child,
      ],
    ),
  );
}

/// The list row the reference is built around: a huge pale numeral in the
/// middle, a two-line label to its left, a two-line label to its right, and a
/// small measure in the corner. The numeral is the thing you read from across
/// the room; everything else is there when you look closer.
class GhostRow extends StatelessWidget {
  const GhostRow({
    super.key,
    required this.numeral,
    this.numeralCaption,
    required this.leftTop,
    required this.leftBottom,
    required this.rightTop,
    required this.rightBottom,
    this.cornerLabel,
    this.cornerValue,
    this.tone = GhostTone.plain,
    this.onTap,
    this.leading,
    this.trailing,
    this.footer,
  });

  final String numeral;

  /// The unit under the numeral — "left", "sent". Sits with the figure it
  /// belongs to rather than in a column of its own.
  final String? numeralCaption;

  final String leftTop;
  final String leftBottom;
  final String rightTop;
  final String rightBottom;
  final String? cornerLabel;
  final String? cornerValue;
  final GhostTone tone;
  final VoidCallback? onTap;

  /// Leads the top line — the queue number, small and muted.
  final Widget? leading;

  /// Ends the top line, opposite everything else — the drag handle, which the
  /// thumb wants on the right of a phone held one-handed.
  final Widget? trailing;

  /// A strip along the bottom of the card, under a hairline: the way out of
  /// whatever state the row is announcing. Inside the card rather than under
  /// it, because it belongs to this row and a second card would say otherwise.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    // Every card is white. The live one is marked by a teal edge and a teal
    // numeral, the finished one by a grey numeral — colour as ink, never as
    // paint. Filling the live card with teal put navy labels and a pale
    // numeral on a mid-teal slab: the "Reached 99%" line came out at about
    // two to one against its background, which is unreadable in daylight and
    // fails any contrast check going.
    final (numeralColour, edge, edgeWidth) = switch (tone) {
      GhostTone.plain => (AppColors.ghost, AppColors.hairline, 1.0),
      GhostTone.accent => (AppColors.accent, AppColors.accent, 1.5),
      GhostTone.muted => (AppColors.muted, AppColors.hairline, 1.0),
    };
    const background = AppColors.card;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: edge, width: edgeWidth),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Padding(
            // Tighter than it was: four of these plus the CRM sections have
            // to share one dashboard now, and the old height spent most of
            // its pixels on air around the numeral.
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (cornerLabel != null || leading != null || trailing != null)
                  Row(
                    children: [
                      ?leading,
                      if (leading != null) const SizedBox(width: 10),
                      if (cornerLabel != null)
                        Text(
                          cornerLabel!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      if (cornerValue != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          cornerValue!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _label(leftTop, leftBottom, false)),
                    // The numeral is allowed to shrink before either label
                    // wraps: a four-digit count is rarer than a long batch name.
                    // The unit belongs to the numeral, under it, not stranded
                    // in the left column. Split across the card it read as
                    // "Failed / left" with a number floating between them,
                    // which is not a sentence in any language.
                    Flexible(
                      flex: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              numeral,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 38,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.5,
                                color: numeralColour,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (numeralCaption != null)
                              Text(
                                numeralCaption!,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: _label(rightTop, rightBottom, true)),
                  ],
                ),
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String top, String bottom, bool alignRight) => Column(
    crossAxisAlignment: alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        top,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 1),
      Text(
        bottom,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.ink,
        ),
      ),
    ],
  );
}

enum GhostTone { plain, accent, muted }

/// The pill tabs the reference uses above a list — selected is the lighter one.
class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;
  final EdgeInsets padding;

  /// Underlined tabs on a white strip, not pills. HubSpot marks the live tab
  /// with a thick teal rule under its label and a hairline under the whole row
  /// — the same bar as "Due tasks / Future tasks" and "All deals / Add views".
  /// The name stays PillTabs because a dozen screens call it that.
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    height: 46,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(left: padding.left * 0.8),
      itemCount: labels.length,
      itemBuilder: (_, i) {
        final selected = i == index;
        return InkWell(
          onTap: () => onSelect(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? AppColors.accentDark : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Center(
              child: Text(
                labels[i],
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.accentDark : AppColors.inkMuted,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The progress bar from the reference, exactly: a row of thin rounded
/// ticks, the filled ones running a red-to-orange gradient across the filled
/// range, the rest grey, and the percentage in a little gradient badge.
///
/// Ticks over a continuous bar for a reason the reference understood: a batch
/// is discrete work, and a hundred small marks filling one by one say
/// "messages, one at a time" the way a smooth fill cannot.
class ProgressTicks extends StatelessWidget {
  const ProgressTicks({
    super.key,
    required this.value,
    this.height = 20,
    this.onDark = false,
    this.showPercent = true,
  });

  /// 0..1. Clamped, so a cap overshoot cannot draw past the track.
  final double value;
  final double height;

  /// Dims the unfilled ticks for the dark surfaces (footer bar, usage card).
  final bool onDark;
  final bool showPercent;

  // Sampled from the reference, deliberately not the app palette — the user
  // asked for this one literally.
  static const _from = Color(0xFFE8402A);
  static const _to = Color(0xFFF6A21E);

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    final rest = onDark
        ? Colors.white.withValues(alpha: 0.20)
        : const Color(0xFFE3E4E0);

    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                const tick = 3.5;
                const gap = 4.0;
                var n = ((box.maxWidth + gap) / (tick + gap)).floor();
                if (n < 1) n = 1;
                final filled = (v * n).round().clamp(0, n);

                return SizedBox(
                  height: height,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < n; i++)
                        Container(
                          width: tick,
                          height: height,
                          decoration: BoxDecoration(
                            // The gradient runs across the filled range, so
                            // the head is always the warm end — exactly how
                            // the reference reads at 23%.
                            color: i < filled
                                ? Color.lerp(
                                    _from,
                                    _to,
                                    filled == 1 ? 1 : i / (filled - 1),
                                  )
                                : rest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (showPercent) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_from, _to]),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                '${(v * 100).round()}%',
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A figure with its caption underneath, for the top of a card.
class BigFigure extends StatelessWidget {
  const BigFigure({
    super.key,
    required this.value,
    required this.caption,
    this.trailing,
  });

  final String value;
  final String caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 44,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.8,
                  color: AppColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              caption,
              maxLines: 2,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 14), trailing!],
    ],
  );
}
