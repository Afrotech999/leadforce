import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/license.dart';
import '../data/selling.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';

/// The seller's desk, behind the passphrase: turn a buyer's installation
/// code into an activation code, and keep the book of who was sold what.
///
/// Everything happens on this phone — the code is its own authority, so
/// nothing here needs a network. The one rule that matters: check the money
/// actually arrived (your own Telebirr statement, not the screenshot) BEFORE
/// generating, because a generated code cannot be taken back.
class SellerScreen extends ConsumerStatefulWidget {
  const SellerScreen({super.key});

  @override
  ConsumerState<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends ConsumerState<SellerScreen> {
  final _install = TextEditingController();
  final _note = TextEditingController();
  int _days = 30;
  String? _generated;

  @override
  void dispose() {
    _install.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final raw = _install.text.trim();
    if (License.normalize(raw).length < 8) {
      showSnack(context, 'That does not look like an installation code.');
      return;
    }
    final code = License.issue(installCode: raw, days: _days);
    await ref
        .read(repoProvider)
        .recordIssuedLicense(installCode: raw, days: _days, note: _note.text);
    bumpRefresh(ref);
    setState(() => _generated = code);
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(issuedLicensesProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Seller',
              subtitle: 'Check the money landed before you generate',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  _Field(
                    controller: _install,
                    hint: 'Buyer\'s installation code (LF-…)',
                    icon: LucideIcons.keyRound,
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    controller: _note,
                    hint: 'Who is this? (name, optional)',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (label, days, _) in Selling.plans)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _Chip(
                              label: label,
                              selected: _days == days,
                              onTap: () => setState(() => _days = days),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: _generate,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 15),
                        child: Center(
                          child: Text(
                            'Generate activation code',
                            style: TextStyle(
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
                  if (_generated != null) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _generated!),
                        );
                        if (context.mounted) {
                          showSnack(context, 'Copied — send it to the buyer.');
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _generated!,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const Icon(
                              LucideIcons.copy,
                              size: 16,
                              color: AppColors.inkMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap to copy. Only works on that buyer\'s phone, '
                      'adds $_days days, single use.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                  if (book.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                      child: Text(
                        'Issued',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                    for (final row in book)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.glass,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: AppColors.glassEdge),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (row['note'] as String?)
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true
                                          ? row['note'] as String
                                          : row['install_code'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${row['install_code']} · '
                                      '${row['days']} days · '
                                      '${formatTimestamp((row['issued_at'] as int?) ?? 0)}',
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
                  ],
                ],
              ),
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
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;

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
