@Tags(['preview'])
library;

import 'dart:io';

import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/models.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:campaign_sms/state/providers.dart';
import 'package:campaign_sms/theme.dart';
import 'package:campaign_sms/ui/home_screen.dart';
import 'package:campaign_sms/ui/notes_screen.dart';
import 'package:campaign_sms/ui/inbox_screen.dart';
import 'package:campaign_sms/ui/lock_screen.dart';
import 'package:campaign_sms/ui/listings_screen.dart';
import 'package:campaign_sms/ui/deals_screen.dart';
import 'package:campaign_sms/ui/schedule_screen.dart';
import 'package:campaign_sms/ui/footer.dart';
import 'package:campaign_sms/ui/calls_screen.dart';
import 'package:campaign_sms/ui/chats_screen.dart';
import 'package:campaign_sms/ui/contacts_screen.dart';
import 'package:campaign_sms/ui/profile_screen.dart';
import 'package:campaign_sms/ui/settings_screen.dart';
import 'package:campaign_sms/ui/subscribe_screen.dart';
import 'package:campaign_sms/ui/thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Renders screens to PNG so the design can be looked at rather than imagined.
///
/// Not part of the ordinary run — tagged `preview`, and only useful with
/// `--update-goldens`, which is what writes the files.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    // Answer the native channel here: without a handler these calls never
    // complete in a test, so anything gated on them (the permissions banner)
    // silently vanishes from every preview. "All permissions off" is the
    // state worth looking at.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.loomsolutions.campaign_sms/native'),
          (call) async => call.method.startsWith('has') ? false : null,
        );
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final loader = FontLoader('Lexend')
        ..addFont(
          File(
            'assets/fonts/Lexend-$w.ttf',
          ).readAsBytes().then((b) => b.buffer.asByteData()),
        );
      await loader.load();
    }
  });

  Future<ProviderContainer> seeded() async {
    final db = await openCampaignDatabase(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    addTearDown(db.close);
    final repo = Repo(db);
    for (var i = 0; i < 240; i++) {
      await repo.upsertContact(
        e164: '+2519111${i.toString().padLeft(5, '0')}',
        name: ['Abebe Kebede', 'Sara Tesfaye', 'Dawit Alemu'][i % 3],
      );
    }
    await repo.generateBatches();
    final batches = await repo.batches();
    final second = await repo.contactsInBatch(batches[1].id);
    for (var i = 0; i < 99; i++) {
      await repo.setContactStatus(second[i].id, ContactStatus.delivered);
    }
    await repo.setContactStatus(second[99].id, ContactStatus.failed);
    final third = await repo.contactsInBatch(batches[2].id);
    for (var i = 0; i < 18; i++) {
      await repo.setContactStatus(third[i].id, ContactStatus.delivered);
    }
    // A diary with a busy day, a quiet one, and something already missed.
    final today = DateTime.now();
    for (final (day, hour, what) in [
      (0, 9, 'Viewing — Bole flat'),
      (0, 14, 'Call Abebe back'),
      (0, 17, 'Meet Teddy at the garage'),
      (2, 11, 'Hand over plates'),
      (5, 10, 'CMC duplex viewing'),
      (-3, 15, 'Missed: ring Sara'),
    ]) {
      final at = DateTime(
        today.year,
        today.month,
        today.day + day,
        hour,
      ).millisecondsSinceEpoch;
      await repo.saveAppointment(
        title: what,
        place: '',
        at: at,
        remindAt: at - 3600000,
      );
    }
    await repo.saveNote(title: 'Dzire up to', body: '3,600,000 cash only');
    await repo.saveNote(title: 'Celario buyer', body: '');
    await repo.saveNote(title: 'Viewings', body: 'x Bole flat\n- CMC duplex');
    for (final (what, who) in [
      ('White Corolla 2018, 45,000km', 'Teddy'),
      ('Vitz 2015 silver', 'Yabsira'),
      ('Hilux double cab 2020', 'Meseret'),
    ]) {
      await repo.saveListing(
        title: what,
        body: '$who sent this',
        sourceText: who,
      );
    }
    return ProviderContainer(overrides: [repoProvider.overrideWithValue(repo)]);
  }

  Future<void> shoot(WidgetTester tester, String name, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.75;
    // A real phone's status bar and gesture bar, so the app bar can be seen
    // running up under the clock rather than being imagined doing it.
    tester.view.padding = const FakeViewPadding(
      top: 2.75 * 28,
      bottom: 2.75 * 16,
    );
    tester.view.viewPadding = const FakeViewPadding(
      top: 2.75 * 28,
      bottom: 2.75 * 16,
    );
    addTearDown(tester.view.reset);

    late final ProviderContainer container;
    await tester.runAsync(() async => container = await seeded());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: screen),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/$name.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  }

  testWidgets('home', (t) => shoot(t, 'home', const _Shell(HomeScreen())));
  testWidgets('notes', (t) => shoot(t, 'notes', const _Shell(NotesScreen())));
  testWidgets('replies', (t) => shoot(t, 'replies', const _Shell(InboxTab())));
  testWidgets('deals', (t) => shoot(t, 'deals', const _Shell(DealsScreen())));
  testWidgets('cars', (t) => shoot(t, 'cars', const _Shell(ListingsScreen())));
  testWidgets(
    'batches',
    (t) => shoot(t, 'batches', const _Shell(BatchesScreen())),
  );
  testWidgets(
    'schedule',
    (t) => shoot(t, 'schedule', const _Shell(ScheduleScreen())),
  );
  testWidgets(
    'settings',
    (t) => shoot(t, 'settings', const _Shell(SettingsTab())),
  );
  testWidgets('welcome', (t) => shoot(t, 'welcome', const WelcomeScreen()));
  testWidgets(
    'subscribe',
    (t) => shoot(t, 'subscribe', const SubscribeScreen()),
  );
  testWidgets('contacts', (t) => shoot(t, 'contacts', const ContactsTab()));
  testWidgets('chats', (t) => shoot(t, 'chats', const _Shell(ChatsScreen())));
  testWidgets('calls', (t) => shoot(t, 'calls', const _Shell(CallsScreen())));
  testWidgets('thread', (tester) async {
    late final ProviderContainer container;
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => container = await seeded());
    final repo = container.read(repoProvider);
    final c = (await tester.runAsync(
      () => repo.contactByPhone('+251911100000'),
    ))!;
    await tester.runAsync(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final (offset, dir, body) in [
        (
          -7200000,
          'outbound',
          'Hello Abebe, we have a white Corolla 2018 — interested?',
        ),
        (-3600000, 'inbound', 'Selam, saw your message'),
        (
          -3500000,
          'inbound',
          'Is the Corolla still there? What is the last price?',
        ),
      ]) {
        await repo.db.insert('message', {
          'contact_id': c.id,
          'direction': dir,
          'body': body,
          'segments': 1,
          'status': 'delivered',
          'created_at': now + offset,
        });
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: ThreadScreen(contactId: c.id),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('preview/thread.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
  testWidgets('lock', (t) => shoot(t, 'lock', LockScreen(onUnlocked: () {})));
}

/// A screen with the real bottom bar under it, since that is half of what the
/// look is being judged on.
class _Shell extends StatelessWidget {
  const _Shell(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: child,
    bottomNavigationBar: AppFooter(
      index: 0,
      onSelect: (_) {},
      items: const [
        FooterItem(
          outline: LucideIcons.house,
          solid: LucideIcons.house,
          label: 'Home',
        ),
        FooterItem(
          outline: LucideIcons.messagesSquare,
          solid: LucideIcons.messagesSquare,
          label: 'Replies',
          badge: 3,
        ),
        FooterItem(
          outline: LucideIcons.messageCircle,
          solid: LucideIcons.messageCircle,
          label: 'Messages',
        ),
        FooterItem(
          outline: LucideIcons.phone,
          solid: LucideIcons.phone,
          label: 'Calls',
        ),
        FooterItem(
          outline: LucideIcons.stickyNote,
          solid: LucideIcons.stickyNote,
          label: 'Notes',
        ),
      ],
    ),
  );
}
