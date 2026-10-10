import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/models.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:campaign_sms/state/providers.dart';
import 'package:campaign_sms/app.dart';
import 'package:campaign_sms/theme.dart';
import 'package:campaign_sms/ui/about_screen.dart';
import 'package:campaign_sms/ui/add_contact_sheet.dart';
import 'package:campaign_sms/ui/batch_sheet.dart';
import 'package:campaign_sms/ui/calls_screen.dart';
import 'package:campaign_sms/ui/listings_screen.dart';
import 'package:campaign_sms/ui/chats_screen.dart';
import 'package:campaign_sms/ui/compose_screen.dart';
import 'package:campaign_sms/ui/contacts_screen.dart';
import 'package:campaign_sms/ui/deal_sheet.dart';
import 'package:campaign_sms/ui/deals_screen.dart';
import 'package:campaign_sms/ui/home_screen.dart';
import 'package:campaign_sms/ui/import_screen.dart';
import 'package:campaign_sms/ui/inbox_screen.dart';
import 'package:campaign_sms/ui/lock_screen.dart';
import 'package:campaign_sms/ui/needs_review_screen.dart';
import 'package:campaign_sms/ui/forward_sheet.dart';
import 'package:campaign_sms/ui/schedule_screen.dart';
import 'package:campaign_sms/ui/templates_sheet.dart';
import 'package:campaign_sms/ui/contact_notes_screen.dart';
import 'package:campaign_sms/ui/notes_screen.dart';
import 'package:campaign_sms/ui/pick_contacts_screen.dart';
import 'package:campaign_sms/ui/profile_screen.dart';
import 'package:campaign_sms/ui/seller_screen.dart';
import 'package:campaign_sms/ui/sending_screen.dart';
import 'package:campaign_sms/ui/subscribe_screen.dart';
import 'package:campaign_sms/ui/tag_sheet.dart';
import 'package:campaign_sms/ui/thread_screen.dart';
import 'package:campaign_sms/ui/usage_screen.dart';
import 'package:campaign_sms/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does every screen survive being laid out?
///
/// The dashboard shipped with a `CrossAxisAlignment.stretch` on a Row inside a
/// ListView. `stretch` needs a bounded cross axis and a ListView gives none, so
/// the row threw during layout and everything below it — the chart, the batch
/// list — silently never painted. In release there is no red banner for that;
/// the page simply stops halfway, which is exactly how it reached the user.
///
/// These pump each screen and fail on any exception. They are cheap and they
/// would have caught it.
///
/// The no-isolate factory matters: the ordinary ffi one keeps a timer alive in a
/// background isolate, and `testWidgets` fails the test on a pending timer
/// rather than on anything to do with the widgets.
void main() {
  setUpAll(sqfliteFfiInit);

  // Ids of the rows the seed creates, so the screens that need one can be built.
  late int contactId;
  late int batchId;
  late int campaignId;

  Future<ProviderContainer> seeded([
    Future<void> Function(Repo repo)? extra,
  ]) async {
    final db = await openCampaignDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final repo = Repo(db);
    // A little real data: an empty database exercises none of the branches that
    // draw numbers, and it was a populated dashboard that broke.
    for (var i = 0; i < 5; i++) {
      await repo.upsertContact(e164: '+25191111111$i', name: 'Contact $i');
    }
    await repo.generateBatches();
    await repo.saveNote(title: 'Call back', body: '- Dawit\nx Sara');
    await repo.addNeedsReview(
      name: 'Bad row',
      phone: '12',
      source: 'Gari',
      reason: 'Not an Ethiopian mobile number',
    );

    contactId = (await repo.contactByPhone('+251911111110'))!.id;
    batchId = (await repo.batches()).first.id;
    campaignId = await repo.createCampaign(
      batchId: batchId,
      template: 'Hello {name}',
      simSubscriptionId: null,
      delaySeconds: 5,
    );
    if (extra != null) await extra(repo);
    return ProviderContainer(overrides: [repoProvider.overrideWithValue(repo)]);
  }

  /// [screen] is a builder so it can be constructed after the seed has run and
  /// the ids exist. [extra] adds whatever else the screen under test needs —
  /// a stored preference, a few more rows — on top of the common seed.
  /// [inspect] runs while the screen is still mounted, for the tests that
  /// check what is on it rather than only that it laid out — everything below
  /// is torn down before this returns, so a `find` afterwards finds nothing.
  Future<Object?> layOut(
    WidgetTester tester,
    Object screen, {
    Future<void> Function(Repo repo)? extra,
    Future<void> Function()? inspect,
  }) async {
    // A small phone: the tightest thing this has to survive.
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    late final ProviderContainer container;
    await tester.runAsync(() async => container = await seeded(extra));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: screen is Widget Function() ? screen() : screen as Widget,
        ),
      ),
    );
    // Fixed pumps rather than pumpAndSettle: a screen showing a spinner never
    // settles, and waiting for one is not what this is testing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    if (inspect != null) await inspect();
    final failure = tester.takeException();
    // Disposed here rather than at teardown: Home watches a provider that polls
    // the campaign every second, and a live timer at the end of the test body
    // fails the test on the pending-timer invariant instead of on the layout.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
    return failure;
  }

  // Screens with no arguments.
  for (final (name, screen) in <(String, Widget)>[
    ('Home', const HomeScreen()),
    ('Replies', const InboxTab()),
    ('Messages', const PersonalInboxTab()),
    ('Notes', const NotesScreen()),
    ('Settings', const SettingsTab()),
    ('About', const AboutScreen()),
    ('Import', const ImportScreen()),
    ('Contacts', const ContactsTab()),
    ('Needs review', const NeedsReviewScreen()),
    ('Usage', const UsageScreen()),
    ('Archived', const ArchivedScreen(kind: 'other')),
    ('Schedule', const ScheduleScreen()),
    ('Calls', const CallsScreen()),
    ('Pipeline', const DealsScreen()),
    ('All batches', const BatchesScreen()),
    ('Listings', const ListingsScreen()),
    // Under MissingPlugin the access check answers false, so this renders its
    // permission gate — which is the layout that must not throw.
    ('Other apps', const ChatsScreen()),
    // The intake with a photo path that does not exist: the placeholder must
    // hold, because shared files can vanish under the app.
    (
      'Listing intake',
      const ListingIntakeScreen(
        text: 'White Corolla 2018\n0911223344',
        photos: ['/nowhere/gone.jpg'],
      ),
    ),
    // Selling the app: the user's own page, the pay flow, the seller desk,
    // the wall an expired install meets, and the first-run welcome.
    ('Profile', const ProfileScreen()),
    ('Subscribe', const SubscribeScreen()),
    ('Seller', const SellerScreen()),
    ('Locked', const LockedScreen()),
    ('Welcome', const WelcomeScreen()),
    // The wall in front of the app, and the page that sets it up.
    ('Lock setup (new)', const LockSetupScreen(alreadySet: false)),
    ('Lock setup (change)', const LockSetupScreen(alreadySet: true)),
  ]) {
    testWidgets('$name lays out without throwing', (tester) async {
      expect(await layOut(tester, screen), isNull);
    });
  }

  // And the ones that need a row to point at. The builder runs after the seed,
  // so the ids are real.
  for (final (name, build) in <(String, Widget Function())>[
    ('Compose', () => ComposeScreen(batchId: batchId)),
    // Under MissingPlugin the permission check answers false, so this renders
    // its permission gate — which is the layout that must not throw.
    (
      'Pick contacts',
      () => PickContactsScreen(batchId: batchId, batchName: 'Batch 1'),
    ),
    ('Sending', () => SendingScreen(campaignId: campaignId)),
    ('Thread', () => ThreadScreen(contactId: contactId)),
    ('Contact detail', () => ContactDetailScreen(contactId: contactId)),
    (
      'Contact profile',
      () => ContactProfileScreen(
        contact: Contact(
          id: contactId,
          phoneE164: '+251911111110',
          phoneLocal: '0911111110',
          name: 'Contact 0',
          source: null,
          status: ContactStatus.notSent,
          batchId: null,
          lastSentAt: null,
          lastError: null,
          attempts: 0,
          isCampaign: true,
          muted: false,
        ),
      ),
    ),
    // The sheets are where a batch is inspected and a walk-in is added, so they
    // get the same layout guard the full screens do.
    (
      'Batch sheet',
      () => _SheetHost(open: (context, _) => showBatchSheet(context, batchId)),
    ),
    (
      'Add contact sheet',
      () => _SheetHost(open: (context, _) => showAddContactSheet(context)),
    ),
    // The broker's three: saved sentences, what is known about a person, and
    // the sheet that books a viewing.
    (
      'Templates sheet',
      () => _SheetHost(open: (context, _) => showTemplatesSheet(context)),
    ),
    (
      'Appointment sheet',
      () => _SheetHost(
        open: (context, ref) => showAppointmentSheet(context, ref),
      ),
    ),
    // Where a forwarded message goes. Long-press now opens the message-actions
    // sheet, and this is the screen behind its busiest row.
    (
      'Forward sheet',
      () => _SheetHost(
        open: (context, ref) => showForwardSheet(context, ref, 'Forward me'),
      ),
    ),
    // The CRM sheets: a deal's facts, and a person's tags.
    (
      'Deal sheet',
      () => _SheetHost(
        open: (context, ref) =>
            showDealSheet(context, ref, contactId: contactId),
      ),
    ),
    (
      'Tag sheet',
      () => _SheetHost(
        open: (context, ref) =>
            showTagSheet(context, ref, contactId: contactId),
      ),
    ),
  ]) {
    testWidgets('$name lays out without throwing', (tester) async {
      expect(await layOut(tester, build), isNull);
    });
  }

  // Ticking a note swaps the header for the selection bar, and the selection
  // bar has to make the same room for the status bar the header does. As a
  // bare row it drew its close button under the clock.
  testWidgets('the selection bar clears the status bar', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 56, bottom: 0);
    tester.view.viewPadding = const FakeViewPadding(top: 56, bottom: 0);
    addTearDown(tester.view.reset);

    late final ProviderContainer container;
    await tester.runAsync(() async => container = await seeded());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const NotesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('Call back'));
    await tester.pump();

    final close = tester.getTopLeft(find.byIcon(LucideIcons.x));
    expect(
      close.dy,
      greaterThanOrEqualTo(28),
      reason: 'the close button must start below a 28dp status bar',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  // The month view, with a diary in it: the grid, the marks and the day's list
  // all have to fit under one app bar on the smallest phone this supports.
  testWidgets('the schedule shows a month with its marks', (tester) async {
    final failure = await layOut(
      tester,
      const ScheduleScreen(),
      extra: (repo) async {
        final now = DateTime.now();
        for (final (day, hour, what) in [
          (0, 9, 'Viewing — Bole flat'),
          (0, 15, 'Call Abebe back'),
          (-2, 11, 'Ring Sara'),
          (4, 10, 'CMC duplex'),
        ]) {
          final at = DateTime(
            now.year,
            now.month,
            now.day + day,
            hour,
          ).millisecondsSinceEpoch;
          await repo.saveAppointment(
            title: what,
            place: '',
            at: at,
            remindAt: at - 3600000,
          );
        }
      },
      inspect: () async {
        // The month is up, today is picked, and today's two are listed.
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Viewing — Bole flat'), findsOneWidget);
        expect(find.text('Call Abebe back'), findsOneWidget);
        // Something on another day is not on today's list.
        expect(find.text('CMC duplex'), findsNothing);
      },
    );
    expect(failure, isNull);
  });

  // A batch that is through except for a failure or two must offer a way out
  // on the row itself. One dead number otherwise holds ninety-nine delivered
  // messages in "to send" forever, and the escape used to be a grey underline
  // at the bottom of a sheet two taps away.
  testWidgets('a batch stuck on failures offers the way out', (tester) async {
    final failure = await layOut(
      tester,
      const BatchesScreen(),
      extra: (repo) async {
        final batch = (await repo.batches()).first;
        final people = await repo.contactsInBatch(batch.id);
        for (final c in people.take(people.length - 1)) {
          await repo.setContactStatus(c.id, ContactStatus.delivered);
        }
        await repo.setContactStatus(people.last.id, ContactStatus.failed);
      },
      inspect: () async {
        expect(find.text('Write off'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('1 failed'), findsOneWidget);
      },
    );
    expect(failure, isNull);
  });

  // The gate itself: with a code set, the app must not be reachable behind it.
  testWidgets('the lock gate stands in front of the app', (tester) async {
    for (final locked in [false, true]) {
      late final ProviderContainer container;
      await tester.runAsync(
        () async => container = await seeded(
          (repo) async => locked ? repo.setLockPin('4821') : null,
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const AppLockGate(child: Text('the client book')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(LockScreen),
        locked ? findsOneWidget : findsNothing,
        reason: locked
            ? 'a code is set, so the wall is up'
            : 'no code, no wall',
      );
      // Behind the wall the app takes no taps — it is still in the tree so the
      // navigator survives, which is exactly why it has to be made inert.
      final absorbing = tester
          .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
          .where((w) => w.absorbing)
          .isNotEmpty;
      expect(absorbing, locked);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    }
  });

  // The keypad. It reads the code's length out of the database on open, so it
  // is pumped against a database that has one set — the state a locked phone
  // is actually in.
  testWidgets('the lock screen lays out without throwing', (tester) async {
    final failure = await layOut(
      tester,
      LockScreen(onUnlocked: () {}),
      extra: (repo) => repo.setLockPin('482173'),
    );
    expect(failure, isNull);
  });

  // The other half of the notes screen. The list is a different widget from the
  // board — compact rows that size to their content — and its second line packs
  // a name, a checklist count and a preview onto one row, which is exactly the
  // shape that overflows if any of it stops being flexible.
  testWidgets('Notes as a list lays out without throwing', (tester) async {
    final failure = await layOut(
      tester,
      const NotesScreen(),
      extra: (repo) async {
        await repo.setSetting('notes_view', 'list');
        // A note that is only a heading, one that is only a body, a long one,
        // a checklist, and one about somebody: every branch of the row.
        await repo.saveNote(title: 'Celario buyer', body: '');
        await repo.saveNote(title: '', body: 'Estar');
        await repo.saveNote(
          title: 'Dzire up to',
          body:
              '3,600,000 cash, no loan, wants it before Meskel and will '
              'take white or silver but nothing darker than that',
        );
        await repo.saveNote(
          title: 'Viewings',
          body: 'x Bole flat\n- CMC duplex\n- Summit villa',
          contactId: contactId,
        );
      },
    );
    expect(failure, isNull);
  });
}

/// A page that does nothing but put its sheet up, so a modal can be pumped by
/// the same helper that pumps a screen.
class _SheetHost extends ConsumerStatefulWidget {
  const _SheetHost({required this.open});

  /// Given the ref as well as the context: some sheets do their own reads and
  /// take a [WidgetRef] rather than reaching for one.
  final Future<void> Function(BuildContext context, WidgetRef ref) open;

  @override
  ConsumerState<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends ConsumerState<_SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
