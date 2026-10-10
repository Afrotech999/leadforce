import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Draw under the status and navigation bars, and make both transparent, so
  // the page colour runs to the top of the screen. Without this Android puts
  // its own grey scrim behind the clock and the battery, which on a pale page
  // reads as a band of a different colour above the app rather than as part
  // of it. SafeArea keeps the content clear of them.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Opened before the first frame so every screen can treat the repository as a plain
  // synchronous dependency instead of an AsyncValue it has to unwrap everywhere.
  //
  // If this fails or stalls the app must say so. A silent hang here shows nothing but
  // the launcher splash, which is indistinguishable from a crash and impossible to
  // report usefully.
  try {
    final db = await openCampaignDatabase().timeout(
      const Duration(seconds: 20),
      onTimeout: () =>
          throw StateError('Opening the database timed out after 20 seconds.'),
    );
    runApp(
      ProviderScope(
        overrides: [repoProvider.overrideWithValue(Repo(db))],
        child: const CampaignSmsApp(),
      ),
    );
  } catch (error, stack) {
    // Also to logcat, so `adb logcat -s flutter` catches it even if the screen
    // is unreadable or the failure happens before anything can be drawn.
    debugPrint('LeadForce failed to start: $error');
    debugPrintStack(stackTrace: stack);
    runApp(StartupFailureApp(error: error, stack: stack));
  }
}

/// Shown when the database cannot be opened. Gives the user something to read out
/// rather than a frozen splash screen.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.stack,
  });

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2B2757),
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('LeadForce could not start')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'The app could not open its database, so it stopped instead of '
              'freezing. Nothing has been lost.',
              style: TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 20),
            SelectableText(
              '$error',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 20),
            const Text(
              'If this keeps happening, reinstalling the app clears the database '
              'and starts fresh — but that also deletes campaign progress, so '
              'export a backup first if you can.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('Technical details'),
              tilePadding: EdgeInsets.zero,
              children: [
                SelectableText(
                  '$stack',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
