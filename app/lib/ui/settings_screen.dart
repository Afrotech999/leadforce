import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'common.dart';
import 'footer.dart';
import 'kit.dart';
import 'lock_screen.dart';
import 'needs_review_screen.dart';
import 'profile_screen.dart';
import 'usage_screen.dart';

/// Settings, kept to one line a row wherever a row can manage it.
///
/// The previous version gave every setting an icon, a title and a two-line
/// explanation, which made a page of six controls scroll like a manual. A
/// setting whose name says what it does gets no second line; the ones that
/// genuinely need a caveat get a short one, and the long-form explanations live
/// on the About screen where somebody reading them has gone looking.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final sims = ref.watch(simsProvider).valueOrNull ?? const <SimCard>[];
    final defaultSms = ref.watch(defaultSmsProvider).valueOrNull;
    final overlayAllowed =
        ref.watch(overlayPermissionProvider).valueOrNull ?? false;
    final callLogAllowed =
        ref.watch(callLogPermissionProvider).valueOrNull ?? false;
    final notificationAccess =
        ref.watch(notificationAccessProvider).valueOrNull ?? false;
    final chatApps =
        ref.watch(chatAppsProvider).valueOrNull ??
        const <({String package, String label})>[];
    final stats = ref.watch(statsProvider).valueOrNull;

    return Scaffold(
      body: settings.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
        data: (s) {
          int intOf(String key, int fallback) =>
              int.tryParse(s[key] ?? '') ?? fallback;
          final countSegments = intOf(SettingKeys.capCountsSegments, 1) == 1;
          final quietOn = intOf(SettingKeys.quietEnabled, 1) == 1;
          final quietStart = intOf(SettingKeys.quietStart, 21);
          final quietEnd = intOf(SettingKeys.quietEnd, 8);
          final chatAppsOn = (s[SettingKeys.chatApps] ?? '')
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toSet();
          final lockOn = (s[SettingKeys.lockHash] ?? '').isNotEmpty;
          // The backup row says how long ago, because "back it up sometimes"
          // is advice and "last one was 24 days ago" is a decision.
          final lastBackup = intOf(SettingKeys.lastBackupAt, 0);
          final backupHint = lastBackup <= 0
              ? 'never backed up — email it to yourself, or save it to Drive'
              : 'last one ${timeAgoLabel(lastBackup)}';
          final currentSim = sims
              .where(
                (x) =>
                    x.subscriptionId ==
                    int.tryParse(s[SettingKeys.simSubscriptionId] ?? ''),
              )
              .firstOrNull;

          return ListView(
            padding: EdgeInsets.only(bottom: footerClearance(context)),
            children: [
              const SafeArea(
                top: false,
                bottom: false,
                child: ScreenHeader(
                  greeting: 'How this app sends',
                  title: 'Your Settings',
                ),
              ),

              const _Label('You'),
              _Group([
                _Row(
                  title: 'Your profile',
                  hint: 'name, business, subscription',
                  trailing: const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
              ]),

              const _Label('Sending'),
              _Group([
                _Stepper(
                  title: 'Daily cap',
                  hint: countSegments
                      ? 'counted in SMS'
                      : 'counted in messages',
                  value: '${intOf(SettingKeys.dailyCap, 100)}',
                  onMinus: () =>
                      _bump(ref, s, SettingKeys.dailyCap, -10, 10, 1000),
                  onPlus: () =>
                      _bump(ref, s, SettingKeys.dailyCap, 10, 10, 1000),
                ),
                _Toggle(
                  title: 'Count the cap in SMS',
                  hint: 'Amharic costs about three times Latin',
                  value: countSegments,
                  onChanged: (v) =>
                      _save(ref, SettingKeys.capCountsSegments, v ? '1' : '0'),
                ),
                _Stepper(
                  title: 'Delay between messages',
                  hint: 'real gaps vary either side',
                  value: '${intOf(SettingKeys.delaySeconds, 5)}s',
                  onMinus: () =>
                      _bump(ref, s, SettingKeys.delaySeconds, -1, 3, 10),
                  onPlus: () =>
                      _bump(ref, s, SettingKeys.delaySeconds, 1, 3, 10),
                ),
                _Stepper(
                  title: 'Batch size',
                  hint: 'for batches built from here on',
                  value: '${intOf(SettingKeys.batchSize, 100)}',
                  onMinus: () =>
                      _bump(ref, s, SettingKeys.batchSize, -10, 10, 500),
                  onPlus: () =>
                      _bump(ref, s, SettingKeys.batchSize, 10, 10, 500),
                ),
                _Stepper(
                  title: 'Attempts per contact',
                  value: '${intOf(SettingKeys.maxAttempts, 2)}',
                  onMinus: () =>
                      _bump(ref, s, SettingKeys.maxAttempts, -1, 1, 5),
                  onPlus: () => _bump(ref, s, SettingKeys.maxAttempts, 1, 1, 5),
                ),
                _Value(
                  title: 'Fallback for {name}',
                  value: s[SettingKeys.nameFallback] ?? 'there',
                  onTap: () => _edit(
                    context,
                    ref,
                    title: 'Fallback for {name}',
                    key: SettingKeys.nameFallback,
                    current: s[SettingKeys.nameFallback] ?? 'there',
                  ),
                ),
                _Toggle(
                  title: 'Quiet hours',
                  hint: quietOn ? null : 'campaigns can run at any hour',
                  value: quietOn,
                  onChanged: (v) =>
                      _save(ref, SettingKeys.quietEnabled, v ? '1' : '0'),
                ),
                if (quietOn)
                  _QuietHours(
                    start: quietStart,
                    end: quietEnd,
                    onChanged: (from, to) async {
                      await _save(ref, SettingKeys.quietStart, '$from');
                      await _save(ref, SettingKeys.quietEnd, '$to');
                    },
                  ),
                const _Battery(),
                if (sims.isNotEmpty)
                  _Value(
                    title: 'Send from',
                    value: currentSim?.displayName ?? 'Device default',
                    onTap: () => _pickSim(context, ref, sims, currentSim),
                  ),
              ]),

              const _Label('Your package'),
              _Group([
                _Nav(
                  title: 'SMS used',
                  hint: 'what your package has paid for',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const UsageScreen()),
                  ),
                ),
              ]),

              const _Label('Replies'),
              _Group([
                _Toggle(
                  title: 'Receive replies in this app',
                  // Now that the dashboard no longer carries a standing warning,
                  // this line is the one place that says what holding the role
                  // costs. It names it plainly.
                  hint: defaultSms?.isDefault == true
                      ? 'personal texts and OTPs arrive here until you turn this off'
                      : 'replies go to ${defaultSms?.label ?? 'your usual app'}',
                  value: defaultSms?.isDefault == true,
                  onChanged: (on) async {
                    if (on) {
                      await SmsChannel.requestDefaultRole();
                    } else {
                      await SmsChannel.restoreDefaultRole(
                        defaultSms?.previousPackage,
                      );
                    }
                    bumpRefresh(ref);
                  },
                ),
                _Value(
                  title: 'STOP keywords',
                  value: _short(
                    s[SettingKeys.stopKeywords] ?? defaultStopKeywords,
                  ),
                  onTap: () => _edit(
                    context,
                    ref,
                    title: 'STOP keywords',
                    key: SettingKeys.stopKeywords,
                    current: s[SettingKeys.stopKeywords] ?? defaultStopKeywords,
                    multiline: true,
                  ),
                ),
              ]),

              const _Label('Contacts'),
              _Group([
                _Nav(
                  title: 'Rebuild remaining batches',
                  onTap: () async {
                    final created = await ref
                        .read(repoProvider)
                        .generateBatches();
                    bumpRefresh(ref);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      created == 0
                          ? 'Nothing to batch.'
                          : '$created new batches created.',
                    );
                  },
                ),
                _Nav(
                  title: 'Retry all failed',
                  onTap: () async {
                    final n = await ref.read(repoProvider).retryFailed();
                    bumpRefresh(ref);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      n == 0 ? 'Nothing to retry.' : '$n contacts requeued.',
                    );
                  },
                ),
                if (stats != null && stats.needsReview > 0)
                  _Nav(
                    title: 'Needs review',
                    value: '${stats.needsReview}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NeedsReviewScreen(),
                      ),
                    ),
                  ),
              ]),

              const _Label('Calls'),
              _Group([
                _Toggle(
                  title: 'Show notes when they call',
                  // Two permissions, not one, and the second is the one that
                  // catches people out: from Android 10 the ringing number is
                  // withheld from every app that does not hold the call log,
                  // so with "display over other apps" granted and the call log
                  // missing, the card has permission to appear and no idea who
                  // is calling. The hint says which of the two is short.
                  hint: !overlayAllowed
                      ? 'needs "display over other apps" — tap to grant'
                      : !callLogAllowed
                      ? 'also needs the call log, or Android will not say who '
                            'is ringing — tap to grant'
                      : 'their notes float over the incoming call',
                  value:
                      overlayAllowed &&
                      intOf(SettingKeys.callOverlayEnabled, 1) == 1,
                  onChanged: (v) async {
                    await _save(
                      ref,
                      SettingKeys.callOverlayEnabled,
                      v ? '1' : '0',
                    );
                    if (!v) return;
                    if (!callLogAllowed) {
                      await SmsChannel.requestCallLogPermission();
                    }
                    if (!overlayAllowed) {
                      await SmsChannel.requestOverlayPermission();
                    }
                    bumpRefresh(ref);
                  },
                ),
              ]),

              const _Label('Other messengers'),
              _Group([
                _Row(
                  title: 'Read my notifications',
                  hint: notificationAccess
                      ? 'allowed — LeadForce can see the apps you tick below'
                      : 'Android keeps this behind its own switch. Greyed '
                            'out? Hold the LeadForce icon → App info → ⋮ → '
                            'Allow restricted settings, then try again.',
                  trailing: Icon(
                    notificationAccess
                        ? LucideIcons.check
                        : LucideIcons.chevronRight,
                    size: 18,
                    color: notificationAccess
                        ? AppColors.ink
                        : AppColors.inkMuted,
                  ),
                  onTap: SmsChannel.openNotificationAccess,
                ),
                for (final app in chatApps)
                  _Toggle(
                    leading: AppIcon(package: app.package, size: 26),
                    title: app.label,
                    hint: chatAppsOn.contains(app.package)
                        ? 'messages appear in Other Apps'
                        : null,
                    value: chatAppsOn.contains(app.package),
                    onChanged: (on) {
                      final next = {...chatAppsOn};
                      if (on) {
                        next.add(app.package);
                      } else {
                        next.remove(app.package);
                      }
                      _save(ref, SettingKeys.chatApps, next.join(','));
                    },
                  ),
                if (chatApps.isEmpty)
                  const _Row(
                    title: 'No messengers found',
                    hint:
                        'WhatsApp, Telegram, Instagram and the rest appear '
                        'here once they are installed',
                    trailing: SizedBox.shrink(),
                  ),
                _Row(
                  title: 'What LeadForce reads',
                  hint:
                      'Only messages that arrive as notifications, only from '
                      'the apps ticked above, only while this is on. Nothing '
                      'is sent anywhere, and LeadForce never replies for you — '
                      'tapping a message opens its own app.',
                  trailing: const SizedBox.shrink(),
                ),
              ]),

              const _Label('Privacy'),
              _Group([
                _Nav(
                  title: lockOn ? 'Change your code' : 'Lock this app',
                  hint: lockOn
                      ? 'a code is asked for every time the app is opened'
                      : 'ask for a code before anything can be read — for '
                            'when the phone is handed to somebody',
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LockSetupScreen(alreadySet: lockOn),
                      ),
                    );
                    bumpRefresh(ref);
                  },
                ),
              ]),

              const _Label('Backup'),
              _Group([
                _Nav(
                  title: 'Send a backup',
                  hint: backupHint,
                  onTap: () => _share(context, ref),
                ),
                _Nav(
                  title: 'Save to this phone',
                  hint: 'to Documents/LeadForce',
                  onTap: () => _export(context, ref),
                ),
                _Nav(
                  title: 'Restore from backup',
                  hint: 'replaces everything on this phone',
                  onTap: () => _restore(context, ref),
                ),
              ]),

              const _Label('About'),
              _Group([
                _Nav(
                  title: 'How this app works',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  static String _short(String value) {
    final parts = value.split(',').where((p) => p.trim().isNotEmpty).toList();
    if (parts.length <= 2) return value;
    return '${parts.take(2).map((p) => p.trim()).join(', ')} +${parts.length - 2}';
  }

  Future<void> _save(WidgetRef ref, String key, String value) async {
    await ref.read(repoProvider).setSetting(key, value);
    bumpRefresh(ref);
  }

  Future<void> _bump(
    WidgetRef ref,
    Map<String, String> settings,
    String key,
    int by,
    int min,
    int max,
  ) async {
    final current = int.tryParse(settings[key] ?? '') ?? min;
    final next = (current + by).clamp(min, max);
    if (next != current) await _save(ref, key, '$next');
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String key,
    required String current,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: multiline ? 4 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null && result.trim().isNotEmpty) {
      await _save(ref, key, result.trim());
    }
  }

  Future<void> _pickSim(
    BuildContext context,
    WidgetRef ref,
    List<SimCard> sims,
    SimCard? current,
  ) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Send from',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              title: const Text('Device default'),
              selected: current == null,
              onTap: () => Navigator.pop(ctx, -1),
            ),
            for (final sim in sims)
              ListTile(
                title: Text(sim.displayName),
                subtitle: Text(sim.label),
                selected: current?.subscriptionId == sim.subscriptionId,
                onTap: () => Navigator.pop(ctx, sim.subscriptionId),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _save(
      ref,
      SettingKeys.simSubscriptionId,
      choice == -1 ? '' : '$choice',
    );
  }

  static String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  /// Hands the backup to whatever the phone can send with — Gmail, Telegram,
  /// Drive. It never leaves on its own: the user picks the app and the
  /// recipient, so this stays inside "nothing leaves the phone by itself".
  Future<void> _share(BuildContext context, WidgetRef ref) async {
    await ref.read(repoProvider).checkpoint();
    final error = await SmsChannel.shareBackup(stamp: _stamp());
    if (error != null) {
      if (context.mounted) showSnack(context, error, error: true);
      return;
    }
    // Stamped only when the share actually went out, so the reminder is not
    // silenced by a chooser the user backed out of... which it can be, since
    // Android does not tell us what happened after the chooser. Handing the
    // file to another app is as far as this side of it goes.
    await ref.read(repoProvider).markBackedUp();
    bumpRefresh(ref);
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(repoProvider).contactsCsv();
      await ref.read(repoProvider).checkpoint();
      final files = await SmsChannel.exportBackup(csv: csv, stamp: _stamp());
      await ref.read(repoProvider).markBackedUp();
      bumpRefresh(ref);
      if (!context.mounted) return;
      showSnack(context, 'Saved: ${files.join(', ')}');
    } catch (e) {
      if (!context.mounted) return;
      showSnack(context, 'Export failed: $e', error: true);
    }
  }

  /// Pick, then read, then ask, then swap — in that order.
  ///
  /// The file is opened and inspected before anything is overwritten, so
  /// choosing the wrong document out of a downloads folder costs a sentence
  /// rather than every contact. The confirmation quotes what is actually in the
  /// file, which is also the only honest way to tell two backups apart.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final path = await SmsChannel.pickFile();
    if (path == null) return;

    final description = await Repo.describeBackup(path);
    if (!context.mounted) return;
    if (description == null || !description.startsWith('ok:')) {
      showSnack(
        context,
        description ?? 'That file could not be read.',
        error: true,
      );
      return;
    }
    final parts = description.split(':');
    final contacts = int.tryParse(parts[1]) ?? 0;
    final messages = int.tryParse(parts[2]) ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(LucideIcons.alertTriangle),
        title: const Text('Replace all data?'),
        content: Text(
          'That backup holds $contacts contacts and $messages messages.\n\n'
          'Restoring it replaces every contact, batch and message currently on '
          'this phone. This cannot be undone.\n\n'
          'The app will close afterwards; reopen it to use the restored data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final target = '${await getDatabasesPath()}/$databaseName';
    final safety = File('$target.previous');
    try {
      // Close first so no handle is holding the old file, then swap it out. The
      // sidecar WAL/SHM files must go too or SQLite will replay them over the copy.
      await ref.read(repoProvider).db.close();
      final current = File(target);
      if (current.existsSync()) await current.copy(safety.path);
      for (final suffix in ['-wal', '-shm']) {
        final f = File('$target$suffix');
        if (f.existsSync()) await f.delete();
      }
      await File(path).copy(target);

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restored'),
          content: const Text(
            'Close the app and open it again to load the restored data.',
          ),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Close app'),
            ),
          ],
        ),
      );
    } catch (e) {
      // Put back what was there. A half-copied database is worse than no
      // restore at all, and the user has already closed their only handle.
      if (safety.existsSync()) {
        try {
          await safety.copy(target);
        } catch (_) {
          // Nothing further to try; the message below is the honest answer.
        }
      }
      if (!context.mounted) return;
      showSnack(context, 'Restore failed: $e', error: true);
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: AppColors.inkMuted,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.glassEdge),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18),
          children[i],
        ],
      ],
    ),
  );
}

/// The shape every row shares: a name, optionally a short qualifier under it,
/// and one control on the right. No icons — five settings do not need five
/// pictures to tell them apart.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.trailing,
    this.hint,
    this.onTap,
    this.leading,
  });

  final String title;
  final String? hint;
  final Widget trailing;
  final VoidCallback? onTap;

  /// Sits before the title — an app's own icon, where the row is about one.
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 13)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    ),
  );
}

/// Minus, value, plus — one quiet pill rather than two filled circles. The old
/// pair were the heaviest thing on the page and they only ever moved by one.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.hint,
  });

  final String title;
  final String? hint;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    hint: hint,
    trailing: Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(icon: LucideIcons.minus, onTap: onMinus),
          // Fixed rather than minimum width: with a minimum, '500' and '2'
          // made pills of different lengths and the column of minus discs
          // came out ragged down the page.
          SizedBox(
            width: 52,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _Step(icon: LucideIcons.plus, onTap: onPlus, accent: true),
        ],
      ),
    ),
  );
}

/// The signs carry colour now: plus is the accent, minus is ink. The pale
/// discs read as disabled, and on a page of six steppers that mattered.
class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap, this.accent = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => Material(
    color: accent ? AppColors.accent : AppColors.ink,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 17,
          color: accent ? AppColors.ink : Colors.white,
        ),
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.value,
    required this.onChanged,
    this.hint,
    this.leading,
  });

  final String title;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    hint: hint,
    leading: leading,
    onTap: () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

class _Value extends StatelessWidget {
  const _Value({required this.title, required this.value, required this.onTap});

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    onTap: onTap,
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.inkMuted,
        ),
      ),
    ),
  );
}

class _Nav extends StatelessWidget {
  const _Nav({required this.title, required this.onTap, this.hint, this.value});

  final String title;
  final String? hint;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    hint: hint,
    onTap: onTap,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          Text(
            value!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
            ),
          ),
        const SizedBox(width: 4),
        const Icon(
          LucideIcons.chevronRight,
          size: 20,
          color: AppColors.inkMuted,
        ),
      ],
    ),
  );
}

class _QuietHours extends StatelessWidget {
  const _QuietHours({
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final int start;
  final int end;
  final void Function(int start, int end) onChanged;

  static String hh(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  Future<int?> _pick(BuildContext context, String title, int current) =>
      showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 320,
            height: 300,
            child: GridView.count(
              crossAxisCount: 4,
              children: [
                for (var h = 0; h < 24; h++)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Material(
                      color: h == current ? AppColors.ink : AppColors.canvas,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(ctx, h),
                        child: Center(
                          child: Text(
                            hh(h),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: h == current
                                  ? Colors.white
                                  : AppColors.ink,
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

  @override
  Widget build(BuildContext context) => _Value(
    title: 'Quiet from / until',
    value: '${hh(start)} – ${hh(end)}',
    onTap: () async {
      final from = await _pick(context, 'Quiet from', start);
      if (from == null || !context.mounted) return;
      final to = await _pick(context, 'Quiet until', end);
      if (to == null) return;
      onChanged(from, to);
    },
  );
}

/// Battery optimisation. Reads its own state, because the answer changes
/// outside the app in a system dialog we do not own.
class _Battery extends StatefulWidget {
  const _Battery();

  @override
  State<_Battery> createState() => _BatteryState();
}

class _BatteryState extends State<_Battery> with WidgetsBindingObserver {
  bool? _optimized;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final value = await SmsChannel.isBatteryOptimized();
    if (mounted) setState(() => _optimized = value);
  }

  @override
  Widget build(BuildContext context) {
    final optimized = _optimized;
    if (optimized == null) {
      return const _Value(title: 'Battery', value: 'checking…', onTap: _noop);
    }
    if (!optimized) {
      return const _Value(
        title: 'Battery',
        value: 'unrestricted',
        onTap: _noop,
      );
    }
    return _Nav(
      title: 'Let batches run to the end',
      hint: 'Android may stop one partway to save power',
      onTap: () async {
        final error = await SmsChannel.requestBatteryExemption();
        if (error != null && context.mounted) {
          showSnack(context, error, error: true);
        }
      },
    );
  }
}

void _noop() {}
