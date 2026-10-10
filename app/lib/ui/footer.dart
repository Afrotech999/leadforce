import 'package:flutter/material.dart';

import '../theme.dart';

/// How much bottom padding a tab's scroll view needs so its last row clears the
/// footer.
///
/// The bar is opaque furniture now and the Scaffold gives it its own space, so
/// a scroll view no longer has to leave room for it — this is breathing room
/// and nothing else. It stays a function of the context so the call sites do
/// not all have to change.
double footerClearance(BuildContext context) => 16.0;

/// The bottom bar: white, full width, a hairline along the top.
///
/// It used to be a dark glass pill floating clear of the edges. That reads as a
/// consumer app; a CRM's bar is furniture — it sits on the edge of the screen,
/// it does not float, and it is the same white as the app bar so the page is
/// framed top and bottom by the same surface. The current destination is teal:
/// glyph, label and all. Nothing else on the bar carries colour.
class AppFooter extends StatelessWidget {
  const AppFooter({
    super.key,
    required this.index,
    required this.onSelect,
    required this.items,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final List<FooterItem> items;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppColors.card,
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _FooterButton(
                  item: items[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class FooterItem {
  const FooterItem({
    required this.outline,
    required this.solid,
    required this.label,
    this.badge = 0,
  });

  final IconData outline;
  final IconData solid;
  final String label;
  final int badge;
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FooterItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Label under the glyph, always. The previous version expanded the current
    // item into a pill with its label alongside, and five items across a phone
    // left it no room — "Batches" came out as "Ba". Stacked, every label has the
    // full width of its own column.
    final colour = selected ? AppColors.accentDark : AppColors.inkMuted;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                selected ? item.solid : item.outline,
                size: 22,
                color: colour,
              ),
              if (item.badge > 0)
                Positioned(
                  top: -3,
                  right: -5,
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
          ),
          const SizedBox(height: 4),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}
