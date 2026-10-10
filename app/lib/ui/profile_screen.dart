import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/database.dart';
import '../data/license.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';
import 'seller_screen.dart';
import 'subscribe_screen.dart';

/// The app user's own page: who they are, and where their subscription
/// stands. Every other profile in the app is somebody else's; this one is
/// theirs.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _business = TextEditingController();
  final _phone = TextEditingController();
  bool _loaded = false;

  /// Taps on the version line; seven of them open the seller door.
  int _taps = 0;

  @override
  void dispose() {
    _name.dispose();
    _business.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repoProvider);
    await repo.setSetting(SettingKeys.profileName, _name.text.trim());
    await repo.setSetting(SettingKeys.profileBusiness, _business.text.trim());
    await repo.setSetting(SettingKeys.profilePhone, _phone.text.trim());
    bumpRefresh(ref);
    if (mounted) showSnack(context, 'Saved.');
  }

  Future<void> _knock() async {
    _taps++;
    if (_taps < 7) return;
    _taps = 0;
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final field = TextEditingController();
        return AlertDialog(
          title: const Text('Seller'),
          content: TextField(
            controller: field,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Passphrase'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(field.text),
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
    if (pass == null || !mounted) return;
    if (License.isSellerPass(pass)) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const SellerScreen()));
    } else {
      showSnack(context, 'Not it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final license = ref.watch(licenseProvider).valueOrNull;
    if (!_loaded && profile != null) {
      _loaded = true;
      _name.text = profile.name;
      _business.text = profile.business;
      _phone.text = profile.phone;
    }

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(title: 'You'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Center(
                    child: ContactAvatar(
                      label: _name.text.isEmpty ? 'You' : _name.text,
                      radius: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Field(
                    controller: _name,
                    hint: 'Your name',
                    icon: LucideIcons.user,
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    controller: _business,
                    hint: 'Business name (optional)',
                    icon: LucideIcons.briefcaseBusiness,
                  ),
                  const SizedBox(height: 8),
                  _Field(
                    controller: _phone,
                    hint: 'Your number (optional)',
                    icon: LucideIcons.phone,
                    keyboard: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: _save,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: Text(
                            'Save',
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
                  const SizedBox(height: 22),
                  if (license != null) SubscriptionCard(license: license),
                  const SizedBox(height: 26),
                  // Seven taps here open the seller screen — the quiet door.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _knock,
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          'LeadForce',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
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
    );
  }
}

/// The subscription, as a card: what phase, how long, and the way to renew.
/// Shared by the profile page and (with the same look) the locked screen.
class SubscriptionCard extends ConsumerWidget {
  const SubscriptionCard({super.key, required this.license});

  final LicenseStatus license;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (title, line) = switch (license.phase) {
      LicensePhase.trial => (
        'Free trial',
        license.daysLeft <= 0
            ? 'Ends today'
            : '${license.daysLeft} day${license.daysLeft == 1 ? '' : 's'} left',
      ),
      LicensePhase.active => (
        'Subscribed',
        'Until ${formatDateTime(license.until).split(' ').first}'
            ' · ${license.daysLeft} day${license.daysLeft == 1 ? '' : 's'} left',
      ),
      LicensePhase.expired => ('Subscription ended', 'Renew to keep working'),
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassEdge),
      ),
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                license.phase == LicensePhase.expired
                    ? LucideIcons.lock
                    : LucideIcons.badgeCheck,
                size: 18,
                color: license.phase == LicensePhase.expired
                    ? AppColors.danger
                    : AppColors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                line,
                style: TextStyle(
                  fontSize: 12.5,
                  color: license.phase == LicensePhase.expired
                      ? AppColors.danger
                      : AppColors.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The installation code: what a buyer sends with their payment.
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: license.installCode));
              if (context.mounted) showSnack(context, 'Code copied.');
            },
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      license.installCode,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: AppColors.ink,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const Icon(
                    LucideIcons.copy,
                    size: 15,
                    color: AppColors.inkMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'This phone\'s code — it goes with your payment.',
            style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 12),
          Material(
            color: license.phase == LicensePhase.expired
                ? AppColors.accent
                : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SubscribeScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Center(
                  child: Text(
                    license.phase == LicensePhase.active
                        ? 'Extend my time'
                        : 'Subscribe',
                    style: const TextStyle(
                      fontSize: 14,
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
    );
  }
}

/// First open: who is this phone's broker? One screen, two fields, skippable.
/// Also the moment the trial clock quietly starts.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _name = TextEditingController();
  final _business = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _name.dispose();
    _business.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final repo = ref.read(repoProvider);
    await repo.setSetting(SettingKeys.profileName, _name.text.trim());
    await repo.setSetting(SettingKeys.profileBusiness, _business.text.trim());
    await repo.setSetting(SettingKeys.welcomed, '1');
    // Starts the trial clock and mints the installation code.
    await repo.licenseStatus();
    bumpRefresh(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: [
            const Text(
              'Welcome to LeadForce',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -1.0,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your contacts, campaigns, deals and notes — all on this '
              'phone, nothing in any cloud. The first '
              '7 days are free, full app.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 28),
            _Field(
              controller: _name,
              hint: 'Your name',
              icon: LucideIcons.user,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _business,
              hint: 'Business name (optional)',
              icon: LucideIcons.briefcaseBusiness,
            ),
            const SizedBox(height: 16),
            // The themed primary, not a hand-rolled teal fill: in this
            // design teal is ink — links, live tabs — and the very first
            // button a new user ever presses should not be the one place the
            // system contradicts itself. The label restates the offer, so the
            // button answers "what happens when I press this".
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _starting ? null : _start,
                child: const Text('Start my free week'),
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
    this.autofocus = false,
    this.keyboard,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool autofocus;
  final TextInputType? keyboard;

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
            keyboardType: keyboard,
            textCapitalization: TextCapitalization.words,
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
