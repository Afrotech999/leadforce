import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';

/// The sheets behind a deal: creating one, renaming it, and moving it through
/// its stages. Small on purpose — a deal is a title, a stage and maybe a
/// figure, and the ceremony should match.

/// "8,500,000 birr", or an empty string for nothing.
String birr(int? amount) {
  if (amount == null || amount <= 0) return '';
  final digits = amount.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return '$out birr';
}

/// Each stage's colours, quietly hotter as a deal gets closer to money.
(Color bg, Color fg) stageTint(String stage) => switch (stage) {
  DealStage.contacted => (AppColors.infoSoft, AppColors.info),
  DealStage.viewing => (AppColors.accentSoft, AppColors.ink),
  DealStage.negotiating => (AppColors.accent, AppColors.ink),
  DealStage.won => (AppColors.ink, AppColors.onInk),
  DealStage.lost => (AppColors.dangerSoft, AppColors.danger),
  _ => (AppColors.glass, AppColors.inkMuted),
};

class StageChip extends StatelessWidget {
  const StageChip({super.key, required this.stage, this.onTap});

  final String stage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = stageTint(stage);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: stage == DealStage.newLead
                ? Border.all(color: AppColors.glassEdge)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DealStage.label(stage),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 3),
                Icon(LucideIcons.chevronDown, size: 13, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Start a deal, or change what it is about. Stage moves live in
/// [showDealStageSheet] — a rename should never reset the stage clock.
Future<void> showDealSheet(
  BuildContext context,
  WidgetRef ref, {
  required int contactId,
  String? contactName,
  Deal? existing,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _DealSheet(
    contactId: contactId,
    contactName: contactName,
    existing: existing,
  ),
);

/// Move a deal to another stage. One tap per stage, done.
Future<void> showDealStageSheet(
  BuildContext context,
  WidgetRef ref,
  Deal deal,
) => showModalBottomSheet(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (_) => _StageSheet(deal: deal),
);

class _DealSheet extends ConsumerStatefulWidget {
  const _DealSheet({required this.contactId, this.contactName, this.existing});

  final int contactId;
  final String? contactName;
  final Deal? existing;

  @override
  ConsumerState<_DealSheet> createState() => _DealSheetState();
}

class _DealSheetState extends ConsumerState<_DealSheet> {
  late final TextEditingController _title;
  late final TextEditingController _price;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _price = TextEditingController(
      text: widget.existing?.price?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), ''));
    await ref
        .read(repoProvider)
        .saveDeal(
          id: widget.existing?.id,
          contactId: widget.contactId,
          title: _title.text,
          price: price,
        );
    bumpRefresh(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, widget.existing == null ? 'Deal started.' : 'Saved.');
  }

  Future<void> _delete() async {
    final id = widget.existing?.id;
    if (id == null) return;
    await ref.read(repoProvider).deleteDeal(id);
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
                        widget.existing == null ? 'Start a deal' : 'The deal',
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
                            hint: 'Bole apartment 3BR, 2018 Corolla…',
                            icon: LucideIcons.handshake,
                            autofocus: widget.existing == null,
                          ),
                          const SizedBox(height: 8),
                          _Field(
                            controller: _price,
                            hint: 'Price in birr (optional)',
                            icon: LucideIcons.banknote,
                            numeric: true,
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

class _StageSheet extends ConsumerWidget {
  const _StageSheet({required this.deal});

  final Deal deal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                  child: Text(
                    'Where does ${deal.what} stand?',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.5,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                for (final stage in DealStage.all)
                  _StageRow(
                    stage: stage,
                    current: stage == deal.stage,
                    onTap: () async {
                      await ref.read(repoProvider).setDealStage(deal.id, stage);
                      bumpRefresh(ref);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        showSnack(
                          context,
                          stage == DealStage.won
                              ? 'Won. Congratulations.'
                              : 'Moved to ${DealStage.label(stage)}.',
                        );
                      }
                    },
                  ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.current,
    required this.onTap,
  });

  final String stage;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = stageTint(stage);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: stage == DealStage.newLead ? AppColors.muted : bg,
                shape: BoxShape.circle,
                border: bg == AppColors.glass
                    ? Border.all(color: AppColors.hairline)
                    : null,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                DealStage.label(stage),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  color: stage == DealStage.lost
                      ? AppColors.danger
                      : AppColors.ink,
                ),
              ),
            ),
            if (current)
              Icon(
                LucideIcons.check,
                size: 18,
                color: fg == AppColors.onInk ? AppColors.ink : fg,
              ),
          ],
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
    this.numeric = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool autofocus;
  final bool numeric;

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
            keyboardType: numeric ? TextInputType.number : null,
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
