import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/license.dart';
import '../data/models.dart';
import '../data/phone.dart';
import '../data/repository.dart';
import '../native/sms_channel.dart';

/// Overridden in `main()` once the database is open, so the rest of the app can treat
/// the repository as a plain synchronous dependency.
final repoProvider = Provider<Repo>((ref) {
  throw StateError('repoProvider must be overridden in main()');
});

/// Bumped after any write. Screens watch it so a change anywhere refreshes everything
/// that is on screen — cheap, and there is only ever one user.
///
/// A note on which families below are `autoDispose` and which are not.
///
/// A `family` keeps one provider per argument, alive for the life of the app.
/// That is right for a fixed set of keys — two inbox kinds, a handful of app
/// icons — and wrong for two kinds of argument:
///
///   * a search string, where every keystroke mints a provider that is never
///     asked for again: typing "corolla" left seven cached result lists behind,
///     forever;
///   * a contact id whose value is large, like every message in a thread, where
///     browsing fifty conversations retained all fifty.
///
/// Those are `autoDispose`, so the memory goes back when the screen does. The
/// queries behind them are indexed and local, so re-running one on the way back
/// in costs a few milliseconds and no spinner worth seeing.
final refreshProvider = StateProvider<int>((ref) => 0);

void bumpRefresh(WidgetRef ref) =>
    ref.read(refreshProvider.notifier).update((v) => v + 1);

/// Names nameless threads from the phone book, quietly.
///
/// Only acts when the contacts permission is already granted — it never asks.
/// Called when the personal inbox opens and after any phone-book read, so a
/// thread that arrived as a bare number picks up its name the next time the
/// user looks at the list.
Future<void> fillThreadNames(WidgetRef ref) async {
  try {
    if (!await SmsChannel.hasContactsPermission()) return;
    final device = await SmsChannel.readDeviceContacts();
    if (device.isEmpty) return;
    final filled = await ref.read(repoProvider).fillNamesFromDevice(device);
    if (filled > 0 && ref.context.mounted) bumpRefresh(ref);
  } catch (_) {
    // Cosmetic: the threads keep working as numbers.
  }
}

void bumpRefreshRef(Ref ref) =>
    ref.read(refreshProvider.notifier).update((v) => v + 1);

final statsProvider = FutureProvider<Stats>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).stats();
});

final batchesProvider = FutureProvider<List<Batch>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).batches();
});

/// Derived from [batchesProvider] rather than queried again: `nextPendingBatch`
/// ran the same grouped aggregate over every contact a second time, on a screen
/// that had just run it.
final nextPendingBatchProvider = Provider<Batch?>((ref) {
  final batches = ref.watch(batchesProvider).valueOrNull;
  if (batches == null) return null;
  final available = batches
      .where((b) => b.status != BatchStatus.inProgress)
      .toList();
  // Fresh contacts first. A batch that is 97% done with a handful of failures
  // is worth retrying, but it should not stand in front of the next hundred
  // people who have never been messaged at all.
  for (final b in available) {
    if (b.remaining > 0) return b;
  }
  for (final b in available) {
    if (b.failed > 0) return b;
  }
  return null;
});

final needsReviewProvider = FutureProvider<List<NeedsReviewRow>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).needsReview();
});

final settingsProvider = FutureProvider<Map<String, String>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).allSettings();
});

final simsProvider = FutureProvider<List<SimCard>>((ref) {
  ref.watch(refreshProvider);
  return SmsChannel.listSims();
});

final defaultSmsProvider = FutureProvider<DefaultSmsInfo>((ref) {
  ref.watch(refreshProvider);
  return SmsChannel.defaultSmsInfo();
});

final threadsProvider = FutureProvider.family<List<ThreadSummary>, String>((
  ref,
  kind,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).threads(kind);
});

final archivedThreadsProvider =
    FutureProvider.family<List<ThreadSummary>, String>((ref, kind) {
      ref.watch(refreshProvider);
      return ref.watch(repoProvider).threads(kind, archived: true);
    });

final archivedCountProvider = FutureProvider.family<int, String>((ref, kind) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).archivedCount(kind);
});

/// Message-body search. Separate from the thread filter so the inbox can show
/// "conversations" and "in messages" as two answers to one question.
final messageSearchProvider = FutureProvider.autoDispose
    .family<List<MessageHit>, String>((ref, query) {
      ref.watch(refreshProvider);
      return ref.watch(repoProvider).searchMessages(query);
    });

/// Whether the call log can be read. Watches the refresh tick so granting the
/// permission in another screen (or in the phone settings) is noticed.
final callLogPermissionProvider = FutureProvider<bool>((ref) {
  ref.watch(refreshProvider);
  return SmsChannel.hasCallLogPermission();
});

/// Calls exchanged with one number. Empty without the permission, which the
/// thread renders as simply "no call markers".
final callsForProvider = FutureProvider.family<List<CallEntry>, String>((
  ref,
  phone,
) {
  ref.watch(refreshProvider);
  return SmsChannel.callsFor(phone);
});

/// Whether the caller-notes card may draw over other apps.
final overlayPermissionProvider = FutureProvider<bool>((ref) {
  ref.watch(refreshProvider);
  return SmsChannel.hasOverlayPermission();
});

/// The whole recent call log with each row matched to a contact where one
/// exists. Empty without the permission — the Calls screen shows its gate.
final recentCallsProvider =
    FutureProvider<List<({RecentCall call, Contact? contact})>>((ref) async {
      ref.watch(refreshProvider);
      final calls = await SmsChannel.recentCalls();
      if (calls.isEmpty) return const [];
      final keys = calls
          .map((c) => normalizePhone(c.number) ?? c.number.trim())
          .toSet()
          .toList();
      final byKey = await ref.read(repoProvider).contactsByKeys(keys);
      return [
        for (final c in calls)
          (
            call: c,
            contact: byKey[normalizePhone(c.number) ?? c.number.trim()],
          ),
      ];
    });

final templatesProvider = FutureProvider<List<Template>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).templates();
});

final appointmentsProvider = FutureProvider<List<Appointment>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).appointments();
});

final nextAppointmentProvider = FutureProvider<Appointment?>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).nextAppointment();
});

final contactAppointmentsProvider =
    FutureProvider.family<List<Appointment>, int>((ref, contactId) {
      ref.watch(refreshProvider);
      return ref.watch(repoProvider).appointmentsForContact(contactId);
    });

/// Notes written about one person.
final contactNotesProvider = FutureProvider.family<List<Note>, int>((
  ref,
  contactId,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).notesForContact(contactId);
});

final scheduledMessagesProvider =
    FutureProvider.family<List<ScheduledMessage>, int>((ref, contactId) {
      ref.watch(refreshProvider);
      return ref.watch(repoProvider).scheduledMessagesFor(contactId);
    });

/// Every deal, person joined in, for the pipeline board.
final dealsProvider = FutureProvider<List<Deal>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).deals();
});

/// The deal shown on a person's profile — their open one, or the last closed.
final contactDealProvider = FutureProvider.family<Deal?, int>((ref, contactId) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).dealForContact(contactId);
});

/// Open-stage counts for the dashboard's pipeline card.
final pipelineCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).pipelineCounts();
});

/// People with a live deal who have gone quiet — the dashboard's nudge.
final goingColdProvider = FutureProvider<List<ColdContact>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).goingCold();
});

/// Every tag with its wearer count.
final tagsProvider = FutureProvider<List<Tag>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).tags();
});

/// The tags one person wears.
final contactTagsProvider = FutureProvider.family<List<Tag>, int>((
  ref,
  contactId,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).tagsForContact(contactId);
});

/// Where this installation stands: trial, active, or expired. The footer
/// tabs, the dashboard banner and the profile card all read this one value.
final licenseProvider = FutureProvider<LicenseStatus>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).licenseStatus();
});

/// The shelf: unsold or sold, filtered by words or a #LF code.
final listingsProvider = FutureProvider.autoDispose
    .family<List<Listing>, ({bool sold, String query})>((ref, arg) {
      ref.watch(refreshProvider);
      return ref.watch(repoProvider).listings(sold: arg.sold, query: arg.query);
    });

final listingProvider = FutureProvider.family<Listing?, int>((ref, id) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).listingById(id);
});

/// Messages read from the other messengers, newest first.
final chatMessagesProvider = FutureProvider<List<ChatMessage>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).chatMessages();
});

final unseenChatCountProvider = FutureProvider<int>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).unseenChatCount();
});

/// Whether Android lets LeadForce read notifications at all.
final notificationAccessProvider = FutureProvider<bool>((ref) {
  ref.watch(refreshProvider);
  return SmsChannel.hasNotificationAccess();
});

/// The messengers LeadForce knows about that are on this phone.
final chatAppsProvider = FutureProvider<List<({String package, String label})>>(
  (ref) {
    ref.watch(refreshProvider);
    return SmsChannel.chatApps();
  },
);

/// An app's own launcher icon. Kept for the session — an icon is a couple of
/// kilobytes and the same handful are drawn on every screen that lists them.
final appIconProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  package,
) {
  return SmsChannel.appIcon(package);
});

/// Which apps have something unseen, for the dashboard's row of icons.
final unseenChatAppsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).unseenChatApps();
});

/// The seller's book of issued codes, newest first.
final issuedLicensesProvider = FutureProvider<List<Map<String, Object?>>>((
  ref,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).issuedLicenses();
});

/// The app user's own name/business/phone, straight from settings.
final profileProvider =
    FutureProvider<({String name, String business, String phone})>((ref) async {
      ref.watch(refreshProvider);
      final repo = ref.watch(repoProvider);
      return (
        name: await repo.getSetting(SettingKeys.profileName, ''),
        business: await repo.getSetting(SettingKeys.profileBusiness, ''),
        phone: await repo.getSetting(SettingKeys.profilePhone, ''),
      );
    });

/// A contact's photo from the phone book, or null. Kept for the session: a
/// thumbnail is a few kilobytes and the inbox asks for the same dozen faces
/// every time it is opened.
final contactPhotoProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  phone,
) async {
  if (phone.trim().isEmpty) return null;
  return SmsChannel.contactPhoto(phone);
});

final unreadByKindProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).unreadByKind();
});

final messagesProvider = FutureProvider.autoDispose.family<List<Message>, int>((
  ref,
  contactId,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).messagesFor(contactId);
});

final trendProvider = FutureProvider<Trend>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).trend();
});

final usageProvider = FutureProvider<Usage>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).usage();
});

final notesProvider = FutureProvider.autoDispose.family<List<Note>, String>((
  ref,
  query,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).notes(query: query);
});

/// Who is actually in a batch. Only read while its sheet is open, so the list
/// is never paid for on the dashboard.
final batchContactsProvider = FutureProvider.family<List<Contact>, int>((
  ref,
  batchId,
) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).contactsInBatch(batchId);
});

/// The same list, polled — for the Sending screen, where the engine is
/// rewriting these rows every few seconds and a refresh-driven read would
/// stand still. Only alive while that screen watches it.
final liveBatchContactsProvider = StreamProvider.family<List<Contact>, int>((
  ref,
  batchId,
) {
  final repo = ref.watch(repoProvider);
  late final StreamController<List<Contact>> controller;
  Timer? timer;

  Future<void> tick() async {
    try {
      if (!controller.isClosed) {
        controller.add(await repo.contactsInBatch(batchId));
      }
    } catch (_) {}
  }

  controller = StreamController<List<Contact>>(
    onListen: () {
      tick();
      timer = Timer.periodic(const Duration(milliseconds: 1200), (_) => tick());
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// The one pending scheduled campaign, for the dashboard's banner.
final scheduledProvider = FutureProvider<ScheduledCampaign?>((ref) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).scheduledCampaign();
});

final contactProvider = FutureProvider.family<Contact?, int>((ref, id) {
  ref.watch(refreshProvider);
  return ref.watch(repoProvider).contactById(id);
});

class ContactQuery {
  const ContactQuery({this.text = '', this.statuses});

  final String text;
  final List<String>? statuses;

  String get _key => statuses == null ? '' : statuses!.join(',');

  @override
  bool operator ==(Object other) =>
      other is ContactQuery && other.text == text && other._key == _key;

  @override
  int get hashCode => Object.hash(text, _key);
}

final contactSearchProvider = FutureProvider.autoDispose
    .family<List<Contact>, ContactQuery>((ref, q) {
      ref.watch(refreshProvider);
      return ref
          .watch(repoProvider)
          .searchContacts(query: q.text, statuses: q.statuses);
    });

/// Live campaign progress.
///
/// The send engine runs in a native foreground service and never pushes events to
/// Dart; both sides agree that the database is the truth, so the UI simply re-reads
/// it.
///
/// The interval follows whether there is anything to watch. A second is right
/// while a batch is going out — well under the minimum 3s between messages — but
/// the app spends almost all of its life with no campaign running, and a query
/// every second forever rebuilt Home every second along with it, which is most
/// of why the app felt heavy when it was doing nothing at all.
final activeCampaignProvider = StreamProvider<CampaignProgress?>((ref) {
  final repo = ref.watch(repoProvider);
  late final StreamController<CampaignProgress?> controller;
  Timer? timer;
  var interval = const Duration(seconds: 1);

  late final void Function() schedule;

  Future<void> tick() async {
    try {
      if (controller.isClosed) return;
      final progress = await repo.activeCampaign();
      controller.add(progress);
      final wanted = progress == null
          ? const Duration(seconds: 6)
          : const Duration(seconds: 1);
      if (wanted != interval) {
        interval = wanted;
        schedule();
      }
    } catch (_) {
      // A transient SQLITE_BUSY while the service writes; the next tick catches up.
    }
  }

  schedule = () {
    timer?.cancel();
    timer = Timer.periodic(interval, (_) => tick());
  };

  controller = StreamController<CampaignProgress?>(
    onListen: () {
      tick();
      schedule();
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Same polling trick for a specific campaign, used by the Sending screen after the
/// campaign finishes (when it is no longer "active").
final campaignProvider = StreamProvider.family<CampaignProgress?, int>((
  ref,
  id,
) {
  final repo = ref.watch(repoProvider);
  late final StreamController<CampaignProgress?> controller;
  Timer? timer;

  Future<void> tick() async {
    try {
      if (!controller.isClosed) controller.add(await repo.campaignById(id));
    } catch (_) {}
  }

  controller = StreamController<CampaignProgress?>(
    onListen: () {
      tick();
      timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    },
    onCancel: () {
      timer?.cancel();
      timer = null;
    },
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});
