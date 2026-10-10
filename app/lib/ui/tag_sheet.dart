import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';

/// Put labels on a person — "buyer", "car", "hot" — or take them off.
///
/// Tap toggles a tag on this person; typing makes a new one; a long press
/// deletes the tag itself, everywhere, after asking. One sheet does all
/// three because a broker files people mid-phone-call, not in a settings
/// screen.
Future<void> showTagSheet(
  BuildContext context,
  WidgetRef ref, {
  required int contactId,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _TagSheet(contactId: contactId),
);

class _TagSheet extends ConsumerStatefulWidget {
  const _TagSheet({required this.contactId});

  final int contactId;

  @override
  ConsumerState<_TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends ConsumerState<_TagSheet> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _name.text.trim();
    if (text.isEmpty) return;
    final repo = ref.read(repoProvider);
    final id = await repo.ensureTag(text);
    if (id != null) await repo.setContactTag(widget.contactId, id, true);
    _name.clear();
    bumpRefresh(ref);
  }

  Future<void> _deleteEverywhere(Tag tag) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${tag.name}"?'),
        content: const Text(
          'This takes the tag off everyone wearing it, not just this person.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(repoProvider).deleteTag(tag.id);
    bumpRefresh(ref);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tagsProvider).valueOrNull ?? const <Tag>[];
    final worn =
        ref.watch(contactTagsProvider(widget.contactId)).valueOrNull ??
        const <Tag>[];
    final wornIds = worn.map((t) => t.id).toSet();
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
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 0, 22, 2),
                      child: Text(
                        'Tags',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.6,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
                      child: Text(
                        'Tap to put one on them. Hold to delete it for good.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    if (all.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in all)
                              _TagChip(
                                tag: tag,
                                on: wornIds.contains(tag.id),
                                onTap: () async {
                                  await ref
                                      .read(repoProvider)
                                      .setContactTag(
                                        widget.contactId,
                                        tag.id,
                                        !wornIds.contains(tag.id),
                                      );
                                  bumpRefresh(ref);
                                },
                                onLongPress: () => _deleteEverywhere(tag),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.glass,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                                border: Border.all(color: AppColors.glassEdge),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.tag,
                                    size: 17,
                                    color: AppColors.inkMuted,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _name,
                                      autofocus: all.isEmpty,
                                      onSubmitted: (_) => _add(),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: AppColors.ink,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'New tag — buyer, car, hot…',
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        hintStyle: TextStyle(
                                          fontSize: 15,
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: AppColors.accent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _add,
                              child: const Padding(
                                padding: EdgeInsets.all(13),
                                child: Icon(
                                  LucideIcons.plus,
                                  size: 20,
                                  color: AppColors.ink,
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

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.on,
    required this.onTap,
    required this.onLongPress,
  });

  final Tag tag;
  final bool on;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: on ? AppColors.accent : AppColors.glass,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: on ? Colors.transparent : AppColors.glassEdge,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (on) ...[
              const Icon(LucideIcons.check, size: 14, color: AppColors.ink),
              const SizedBox(width: 5),
            ],
            Text(
              tag.count > 0 ? '${tag.name} · ${tag.count}' : tag.name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? AppColors.ink : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
