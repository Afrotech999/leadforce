import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';

/// The sentences you type every day, one tap away.
///
/// A broker says "is it still available?", "the price is negotiable", "send me
/// your ID" a dozen times a day, in Amharic, on a phone keyboard. Returns the
/// chosen body, already rendered with [name] where the template says `{name}`.
Future<String?> showTemplatesSheet(
  BuildContext context, {
  String? name,
  String? currentText,
  bool fillName = false,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      _TemplatesSheet(name: name, currentText: currentText, fillName: fillName),
);

class _TemplatesSheet extends ConsumerStatefulWidget {
  const _TemplatesSheet({this.name, this.currentText, required this.fillName});

  /// Who the message is going to, when it is going to exactly one person.
  final String? name;

  /// Whether to substitute `{name}` on the way out.
  ///
  /// True in a conversation — there is one recipient and the placeholder is
  /// noise. False in the campaign composer, where the placeholder is the whole
  /// point and the send engine fills it per contact.
  final bool fillName;

  /// What is in the composer right now, offered as something to save.
  final String? currentText;

  @override
  ConsumerState<_TemplatesSheet> createState() => _TemplatesSheetState();
}

class _TemplatesSheetState extends ConsumerState<_TemplatesSheet> {
  bool _managing = false;

  String _render(String body) {
    if (!widget.fillName) return body;
    final name = widget.name?.trim();
    return body.replaceAll(
      '{name}',
      (name == null || name.isEmpty) ? 'there' : name,
    );
  }

  Future<void> _edit({Template? existing}) async {
    final label = TextEditingController(text: existing?.label ?? '');
    final body = TextEditingController(
      text: existing?.body ?? widget.currentText?.trim() ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New template' : 'Edit template'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name it (optional)',
                hintText: 'Still available?',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: body,
              autofocus: existing == null,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Hello {name}, is the car still available?',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final text = body.text;
    final name = label.text;
    label.dispose();
    body.dispose();
    if (saved != true || text.trim().isEmpty) return;
    await ref
        .read(repoProvider)
        .saveTemplate(id: existing?.id, label: name, body: text);
    bumpRefresh(ref);
    if (mounted) setState(() => _managing = true);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(templatesProvider).valueOrNull ?? const <Template>[];

    return ClipRRect(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Quick messages',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (list.isNotEmpty)
                        Semantics(
                          label: _managing ? 'Done editing' : 'Edit templates',
                          button: true,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _managing = !_managing),
                            child: Text(_managing ? 'Done' : 'Edit'),
                          ),
                        ),
                    ],
                  ),
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(22, 4, 22, 16),
                    child: Text(
                      'Save the sentences you send every day — a price, an '
                      'address, "still available?" — and they become one tap.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _Row(
                        template: list[i],
                        managing: _managing,
                        canMoveUp: i > 0,
                        canMoveDown: i < list.length - 1,
                        onUse: () =>
                            Navigator.pop(context, _render(list[i].body)),
                        onEdit: () => _edit(existing: list[i]),
                        onMove: (delta) async {
                          await ref
                              .read(repoProvider)
                              .moveTemplate(list[i].id, delta);
                          bumpRefresh(ref);
                        },
                        onDelete: () async {
                          await ref
                              .read(repoProvider)
                              .deleteTemplate(list[i].id);
                          bumpRefresh(ref);
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        onTap: () => _edit(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.plus,
                                size: 17,
                                color: AppColors.ink,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                (widget.currentText?.trim().isNotEmpty ?? false)
                                    ? 'Save what I typed'
                                    : 'New quick message',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
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
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.template,
    required this.managing,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onUse,
    required this.onEdit,
    required this.onMove,
    required this.onDelete,
  });

  final Template template;
  final bool managing;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final ValueChanged<int> onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(color: AppColors.glassEdge),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: managing ? onEdit : onUse,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, managing ? 4 : 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  if (template.label.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      template.body.replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (managing) ...[
              _Mini(
                icon: LucideIcons.arrowUp,
                label: 'Move up',
                onTap: canMoveUp ? () => onMove(-1) : null,
              ),
              _Mini(
                icon: LucideIcons.arrowDown,
                label: 'Move down',
                onTap: canMoveDown ? () => onMove(1) : null,
              ),
              _Mini(
                icon: LucideIcons.trash2,
                label: 'Delete',
                danger: true,
                onTap: onDelete,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Mini extends StatelessWidget {
  const _Mini({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      color: danger ? AppColors.danger : AppColors.inkMuted,
      disabledColor: AppColors.muted,
    ),
  );
}
