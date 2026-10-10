import 'package:campaign_sms/data/database.dart';
import 'package:campaign_sms/data/repository.dart';
import 'package:campaign_sms/state/providers.dart';
import 'package:campaign_sms/theme.dart';
import 'package:campaign_sms/ui/home_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The drag itself, end to end.
///
/// `reorder_test.dart` pins down the index arithmetic, but that function being
/// right is no use if the grip is not wired to it. This one puts a finger on
/// the handle, moves it, and reads the order back out of the database. On
/// BatchesScreen, since that is where the queue lives now.
void main() {
  setUpAll(sqfliteFfiInit);

  testWidgets('dragging a batch by its grip rewrites the order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    late final ProviderContainer container;
    late final Repo repo;
    await tester.runAsync(() async {
      final db = await openCampaignDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '1');
      for (var i = 0; i < 3; i++) {
        await repo.upsertContact(e164: '+25191111111$i', name: 'Contact $i');
      }
      await repo.generateBatches();
      container = ProviderContainer(
        overrides: [repoProvider.overrideWithValue(repo)],
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BatchesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Batch 1'), findsOneWidget);
    final grips = find.byIcon(LucideIcons.gripVertical);
    expect(grips, findsNWidgets(3));

    // Batch 1 down past Batch 2. The card is about 100 logical pixels tall, so
    // a 130px drag lands it in the second slot.
    // The list sits below the page bar and the tabs, so make sure the row is
    // actually on screen before putting a finger on it.
    await tester.ensureVisible(grips.first);
    await tester.pump();
    final start = tester.getCenter(grips.first);
    expect(
      tester.getRect(grips.first).top,
      greaterThan(0),
      reason: 'a gesture on an off-screen row proves nothing',
    );
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 100));
    // Moved in small steps rather than one jump: the list works out where the
    // card belongs from the moves it sees, and a single 130px leap tells it
    // almost nothing. A finger does not teleport either.
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    // The write is real async on a real SQLite, so it needs real time to land.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    late final List<String> order;
    await tester.runAsync(() async {
      order = (await repo.batches()).map((b) => b.name).toList();
    });
    expect(order, [
      'Batch 2',
      'Batch 1',
      'Batch 3',
    ], reason: 'the grip has to be wired to the reorder, not just drawn');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });

  testWidgets('press-and-hold on the card body also lifts it', (tester) async {
    // The grip is precise but tiny; holding the card anywhere is the gesture
    // every list app trains. Both recognizers share the gesture arena, so this
    // test failing would mean one of them ate the other.
    tester.view.physicalSize = const Size(720, 3000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    late final ProviderContainer container;
    late final Repo repo;
    await tester.runAsync(() async {
      final db = await openCampaignDatabase(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
      addTearDown(db.close);
      repo = Repo(db);
      await repo.setSetting(SettingKeys.batchSize, '1');
      for (var i = 0; i < 3; i++) {
        await repo.upsertContact(e164: '+25191111111$i', name: 'Contact $i');
      }
      await repo.generateBatches();
      container = ProviderContainer(
        overrides: [repoProvider.overrideWithValue(repo)],
      );
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BatchesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final card = find.text('Batch 1');
    await tester.ensureVisible(card);
    await tester.pump();

    final gesture = await tester.startGesture(tester.getCenter(card));
    // Held still past the long-press delay: this is what activates the lift.
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    late final List<String> order;
    await tester.runAsync(() async {
      order = (await repo.batches()).map((b) => b.name).toList();
    });
    expect(order, [
      'Batch 2',
      'Batch 1',
      'Batch 3',
    ], reason: 'a held press on the card must lift it, not open the sheet');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
}
