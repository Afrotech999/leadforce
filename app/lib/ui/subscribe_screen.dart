import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/selling.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';

/// Paying for LeadForce, without a payment system: the prices, the accounts to
/// pay into, this phone's code to send with the screenshot, and the box the
/// activation code comes back into. The whole flow is written on the screen
/// because the buyer does it alone, probably once a month.
class SubscribeScreen extends ConsumerStatefulWidget {
  const SubscribeScreen({super.key});

  @override
  ConsumerState<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends ConsumerState<SubscribeScreen> {
  final _code = TextEditingController();
  bool _activating = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_activating) return;
    setState(() => _activating = true);
    try {
      final error = await ref.read(repoProvider).redeemCode(_code.text);
      bumpRefresh(ref);
      if (!mounted) return;
      if (error != null) {
        showSnack(context, error, error: true);
        return;
      }
      _code.clear();
      final status = await ref.read(repoProvider).licenseStatus();
      if (!mounted) return;
      showSnack(
        context,
        'Active — ${status.daysLeft} days on the clock. Thank you.',
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) return;
    setState(() => _code.text = text);
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseProvider).valueOrNull;
    final install = license?.installCode ?? '…';

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(title: 'Subscribe'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  const _Step('1', 'Pay for the time you want'),
                  _Card(
                    child: Column(
                      children: [
                        for (final (label, _, price) in Selling.plans)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                Text(
                                  price,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 18),
                        _CopyLine(label: 'Telebirr', value: Selling.telebirr),
                        _CopyLine(label: 'CBE', value: Selling.cbeAccount),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.user,
                                size: 14,
                                color: AppColors.inkMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Selling.accountName,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Step(
                    '2',
                    'Send the payment screenshot with this phone\'s code',
                  ),
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: () async {
                            await Clipboard.setData(
                              ClipboardData(text: install),
                            );
                            if (context.mounted) {
                              showSnack(context, 'Code copied.');
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    install,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
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
                        const SizedBox(height: 10),
                        Material(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: () async {
                              final body = Uri.encodeComponent(
                                'My LeadForce code is $install — payment screenshot coming.',
                              );
                              final error = await SmsChannel.openExternal(
                                'sms:${Selling.sellerPhone}?body=$body',
                              );
                              if (error != null && context.mounted) {
                                showSnack(context, error, error: true);
                              }
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: Text(
                                  'Send my code by SMS',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Send the screenshot itself on Telegram or WhatsApp '
                          'to the same number.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Step('3', 'Paste the activation code you get back'),
                  _Card(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _code,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.ink,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'LF2-…',
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    hintStyle: TextStyle(
                                      fontSize: 14.5,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                              Semantics(
                                label: 'Paste',
                                button: true,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _paste,
                                  icon: const Icon(
                                    LucideIcons.clipboardPaste,
                                    size: 18,
                                  ),
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        // The themed primary. This is the money button, and
                        // the money button is the last place to freelance the
                        // design system.
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _activating ? null : _activate,
                            child: Text(_activating ? 'Checking…' : 'Activate'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What an expired install sees in place of the locked tabs. Deliberately
/// gentle: nothing is deleted, texting still works, and the way back is one
/// button.
class LockedScreen extends ConsumerWidget {
  const LockedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            children: [
              const Icon(LucideIcons.lock, size: 40, color: AppColors.muted),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Your LeadForce time has ended',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Everything is still here — your contacts, deals and '
                  'notes are safe on this phone, and receiving and replying '
                  'to messages keeps working. Campaigns and the CRM come '
                  'back the moment you renew.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.55,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Material(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SubscribeScreen()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 15),
                    child: Center(
                      child: Text(
                        'Renew',
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.text);

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.glassEdge),
    ),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    child: child,
  );
}

class _CopyLine extends StatelessWidget {
  const _CopyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(AppRadius.chip),
    onTap: () async {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) showSnack(context, '$label number copied.');
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          const Icon(LucideIcons.copy, size: 14, color: AppColors.inkMuted),
        ],
      ),
    ),
  );
}
