import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/license.dart';
import 'native/sms_channel.dart';
import 'state/providers.dart';
import 'theme.dart';
import 'ui/listings_screen.dart';
import 'ui/footer.dart';
import 'ui/profile_screen.dart';
import 'ui/sending_bar.dart';
import 'ui/subscribe_screen.dart';
import 'ui/home_screen.dart';
import 'ui/inbox_screen.dart';
import 'ui/lock_screen.dart';
import 'ui/notes_screen.dart';
import 'ui/calls_screen.dart';
import 'ui/thread_screen.dart';

/// Held so a notification tap can push a conversation from outside the widget
/// tree, on a resume that no screen is listening for.
final navigatorKey = GlobalKey<NavigatorState>();

class CampaignSmsApp extends StatelessWidget {
  const CampaignSmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LeadForce',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: navigatorKey,
      // Two things wrap every screen in the app.
      //
      // The lock comes first, so nothing of the app is built — let alone
      // painted — until the code is in.
      //
      // The text clamp is the reason the fixed-height cards on the notes board
      // and the listings shelf survive a phone set to its largest font. Android
      // goes past 2x, which turns a two-line card into a four-line one inside
      // a box that cannot grow, and the page overflows. 1.3 keeps the app
      // readable for someone who needs bigger text without shattering the
      // layouts; below 1.0 nothing is gained by letting the system shrink it.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.3,
        child: AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
      home: const AppShell(),
    );
  }
}

/// Holds the lock screen in front of everything until the code is entered.
///
/// Locks again whenever the app leaves the foreground, which is the moment
/// that matters: the phone is being handed over, or put down on a table. There
/// is no grace period on purpose — a lock with a five-minute window is off
/// exactly when somebody is holding your phone.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// Null while the first read is in flight — the app is neither locked nor
  /// unlocked until the database has answered, and drawing either one before
  /// then would flash the wrong screen.
  bool? _locked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read() async {
    final set = await ref.read(repoProvider).lockIsSet();
    if (mounted) setState(() => _locked = set);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `paused` is the app going away. `inactive` is not enough on its own —
    // it also fires for a notification shade pull or a permission dialog, and
    // locking behind those would be unusable.
    if (state == AppLifecycleState.paused) _read();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    if (locked == null) {
      return const ColoredBox(
        color: AppColors.canvas,
        child: SizedBox.expand(),
      );
    }

    // The app stays in the tree behind the lock rather than being swapped out
    // for it. Taking it out would destroy the navigator, so unlocking would
    // dump the user back on the dashboard having lost whatever page they were
    // on, and a notification tap that arrives while locked would have no
    // navigator to push onto. The lock is opaque and full-screen, so nothing
    // behind it is visible, and while it is up the app below takes no taps and
    // is invisible to a screen reader.
    return Stack(
      children: [
        ExcludeSemantics(
          excluding: locked,
          child: AbsorbPointer(absorbing: locked, child: widget.child),
        ),
        if (locked)
          LockScreen(onUnlocked: () => setState(() => _locked = false)),
      ],
    );
  }
}

/// Bottom-nav shell.
///
/// Campaign replies and personal texts get a footer tab each rather than two
/// tabs inside one Inbox screen. Keeping them apart is the whole point of the
/// walled-off inbox, and a bank OTP one swipe from a lead was not far enough
/// apart — now they are different places.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// An IndexedStack that only builds a tab the first time it is visited.
///
/// A plain IndexedStack builds all five tabs on the first frame, which meant
/// every query in the app ran before the dashboard could paint. Now startup
/// builds one screen; the others are built when tapped and stay alive from
/// then on, so switching back is instant and state survives exactly as before.
class _LazyStack extends StatefulWidget {
  const _LazyStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_LazyStack> createState() => _LazyStackState();
}

class _LazyStackState extends State<_LazyStack> {
  late final Set<int> _visited = {widget.index};

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeInterruptedCampaign();
      _openThreadFromNotification();
    });
  }

  /// START_STICKY normally brings the send service back by itself, but a force-stop
  /// or an aggressive OEM task killer defeats that. Opening the app is a good moment
  /// to check. Starting an already-running service is a no-op.
  Future<void> _resumeInterruptedCampaign() async {
    try {
      // A send whose receipt never arrived leaves its contact 'queued', and
      // 'queued' is excluded from every future batch — so without this, that
      // person quietly disappears from the campaign. Settling them as failed
      // puts them in the retry queue where they are visible.
      final rescued = await ref.read(repoProvider).sweepStalePending();
      if (rescued > 0) bumpRefresh(ref);
      final active = await ref.read(repoProvider).activeCampaign();
      if (active != null) await SmsChannel.startSendService();
    } catch (_) {
      // Nothing actionable; the Sending screen still shows the true state.
    }
  }

  /// Tapping an inbox notification should land on that conversation — opening it
  /// is what marks it read, so anything less leaves a badge the user cannot
  /// explain and cannot clear.
  Future<void> _openThreadFromNotification() async {
    try {
      // A share from another app first: the user is standing in Telegram with
      // something to sell in hand — nothing else pending outranks that.
      final share = await SmsChannel.takePendingShare();
      if (share != null && mounted) {
        await navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) =>
                ListingIntakeScreen(text: share.text, photos: share.photos),
          ),
        );
        if (mounted) bumpRefresh(ref);
        return;
      }
      // The after-call nudge next: if both are somehow pending, the note is
      // the fresher intention — the user tapped "write it down" last.
      final callNote = await SmsChannel.takePendingCallNote();
      if (callNote != null && mounted) {
        await navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => NoteEditorScreen(
              contactId: callNote.contactId,
              initialBody: callNote.prefill,
            ),
          ),
        );
        if (mounted) bumpRefresh(ref);
        return;
      }
      final contactId = await SmsChannel.takePendingThread();
      if (contactId == null || !mounted) return;
      await navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ThreadScreen(contactId: contactId)),
      );
    } catch (_) {
      // The Inbox tab still lists it; not worth an error to the user.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The default-SMS role can only change outside our process, and replies land in
    // the DB from a broadcast receiver. Both mean: re-read everything on resume.
    if (state == AppLifecycleState.resumed) {
      bumpRefresh(ref);
      _openThreadFromNotification();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Each inbox carries its own count; a single total would not say which of
    // the two places to look in.
    final unread = ref.watch(unreadByKindProvider).valueOrNull ?? const {};
    final replies = unread['campaign'] ?? 0;
    final personal = unread['other'] ?? 0;
    final active = ref.watch(activeCampaignProvider).valueOrNull;

    // First open: who is this? Only once, and only when settings have
    // actually loaded — flashing the welcome at every startup would be worse
    // than never showing it.
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings != null && settings[SettingKeys.welcomed] != '1') {
      return const WelcomeScreen();
    }

    // Out of subscription: the business tools lock, the phone stays a phone.
    // Replies, Messages and Calls keep working — this app may be somebody's
    // default SMS app, and a lapsed subscription must never cost them a bank
    // OTP or a family text.
    final expired =
        ref.watch(licenseProvider).valueOrNull?.phase == LicensePhase.expired;

    return Scaffold(
      // The footer is opaque furniture now, not floating glass, so the body
      // stops at the top of it rather than running underneath.
      extendBody: false,
      body: _LazyStack(
        index: _index,
        children: [
          expired ? const LockedScreen() : const HomeScreen(),
          const InboxTab(),
          const PersonalInboxTab(),
          const CallsScreen(),
          expired ? const LockedScreen() : const NotesScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The running campaign, visible from every tab. Part of the footer
          // rather than each screen so no page can lose sight of it.
          if (active != null) SendingBar(progress: active),
          AppFooter(
            index: _index,
            // No refresh on a tab switch. The IndexedStack keeps every screen
            // alive, so switching tabs changed no data — it just re-ran every
            // query in the app and flashed all of them through their spinner.
            onSelect: (i) => setState(() => _index = i),
            items: [
              // "Home", not "Dash": the tab is the whole dashboard, and
              // "Dash" is designer shorthand a first-time or second-language
              // user has to decode. "Home" is the one word every phone has
              // already taught everybody.
              const FooterItem(
                outline: LucideIcons.house,
                solid: LucideIcons.house,
                label: 'Home',
              ),
              FooterItem(
                outline: LucideIcons.messagesSquare,
                solid: LucideIcons.messagesSquare,
                label: 'Replies',
                badge: replies,
              ),
              FooterItem(
                outline: LucideIcons.messageCircle,
                solid: LucideIcons.messageCircle,
                label: 'Messages',
                badge: personal,
              ),
              const FooterItem(
                outline: LucideIcons.phone,
                solid: LucideIcons.phone,
                label: 'Calls',
              ),
              const FooterItem(
                outline: LucideIcons.stickyNote,
                solid: LucideIcons.stickyNote,
                label: 'Notes',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
