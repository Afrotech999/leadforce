import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'contact_notes_screen.dart';
import 'footer.dart';
import 'kit.dart';
import 'thread_screen.dart';

/// The listing shelf: everything shared into LeadForce, each card remembering who
/// sent it.
///
/// The whole feature exists for one moment — a buyer says "that white
/// Corolla you posted" a week after the seller's Telegram message scrolled
/// away. The shelf answers by photo, by words, or by the #LF code printed
/// in the channel post's own caption.
class ListingsScreen extends ConsumerStatefulWidget {
  const ListingsScreen({super.key});

  @override
  ConsumerState<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends ConsumerState<ListingsScreen> {
  final _search = TextEditingController();
  final _typing = Debouncer();
  String _query = '';
  bool _sold = false;

  @override
  void dispose() {
    _typing.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listings =
        ref.watch(listingsProvider((sold: _sold, query: _query))).valueOrNull ??
        const <Listing>[];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Your Listings',
              subtitle: 'Anything you are selling — a car, a house, a machine',
              showBack: Navigator.of(context).canPop(),
            ),
            SearchField(
              controller: _search,
              hint: 'Search listings, sellers or a code',
              onChanged: (v) => _typing.run(() {
                if (mounted) setState(() => _query = v);
              }),
              onClear: _query.isEmpty
                  ? null
                  : () {
                      _search.clear();
                      _typing.flush(() => setState(() => _query = ''));
                    },
            ),
            PillTabs(
              labels: const ['For sale', 'Sold'],
              index: _sold ? 1 : 0,
              onSelect: (i) => setState(() => _sold = i == 1),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: listings.isEmpty
                  ? EmptyState(
                      icon: LucideIcons.car,
                      title: _query.isNotEmpty
                          ? 'Nothing matches'
                          : _sold
                          ? 'Nothing sold yet'
                          : 'The shelf is empty',
                      message: _query.isNotEmpty
                          ? 'No listing mentions "$_query".'
                          : _sold
                          ? 'Anything you mark sold moves here.'
                          : 'When a seller sends you a listing on Telegram, '
                                'long-press the message → Share → LeadForce. '
                                'It lands here with who sent it, and you '
                                'get a #code to paste in your post.',
                    )
                  : GridView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        footerClearance(context),
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                      itemCount: listings.length,
                      itemBuilder: (_, i) => _CarCard(listing: listings[i]),
                    ),
            ),
          ],
        ),
      ),
      // The manual door: the same intake the share sheet opens, empty. For
      // when Telegram hides Share behind the wrong menu, or the listing arrived
      // by word of mouth.
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: FloatingActionButton(
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ListingIntakeScreen(text: '', photos: []),
              ),
            );
            bumpRefresh(ref);
          },
          backgroundColor: AppColors.action,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: const Icon(LucideIcons.plus, size: 26),
        ),
      ),
    );
  }
}

/// A photo of the first picture, or the placeholder — never a crash, even
/// when the file has been cleaned away.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({super.key, required this.path, this.fit = BoxFit.cover});

  final String? path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p != null && File(p).existsSync()) {
      return Image.file(File(p), fit: fit);
    }
    return Container(
      color: AppColors.accentSoft,
      child: const Center(
        child: Icon(LucideIcons.car, size: 34, color: AppColors.inkMuted),
      ),
    );
  }
}

class _CarCard extends ConsumerWidget {
  const _CarCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: const BorderSide(color: AppColors.glassEdge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ListingScreen(carId: listing.id)),
          );
          bumpRefresh(ref);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: ListingPhoto(path: listing.photos.firstOrNull),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${listing.code} · ${listing.who}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkMuted,
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

/// One listing, whole: the photos, the words, the code, and — the point — the
/// person who sent it, one tap from a call.
class ListingScreen extends ConsumerWidget {
  const ListingScreen({super.key, required this.carId});

  final int carId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listing = ref.watch(listingProvider(carId)).valueOrNull;
    if (listing == null) {
      return const Scaffold(body: SafeArea(child: LoadingState()));
    }

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  RoundAction(
                    icon: LucideIcons.arrowLeft,
                    label: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      listing.what,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // The code, always visible and always one tap from the
                  // clipboard — it exists to be pasted into the channel post.
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: listing.code),
                        );
                        if (context.mounted) {
                          showSnack(
                            context,
                            '${listing.code} copied — paste it in your post.',
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          listing.code,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  if (listing.photos.isNotEmpty)
                    SizedBox(
                      height: 230,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: listing.photos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ListingPhoto(path: listing.photos[i]),
                          ),
                        ),
                      ),
                    ),
                  if (listing.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
                      child: Text(
                        listing.body.trim(),
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SourceCard(listing: listing),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: listing.sold
                              ? AppColors.card
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: () async {
                              await ref
                                  .read(repoProvider)
                                  .setListingSold(listing.id, !listing.sold);
                              bumpRefresh(ref);
                              if (context.mounted) {
                                showSnack(
                                  context,
                                  listing.sold
                                      ? 'Back on the shelf.'
                                      : 'Sold. Congratulations.',
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Center(
                                child: Text(
                                  listing.sold
                                      ? 'Back on the shelf'
                                      : 'Mark sold',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.2,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          onTap: () => _delete(context, ref, listing),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Icon(
                              LucideIcons.trash2,
                              size: 18,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Shared in ${formatDateTime(listing.createdAt)}'
                      '${listing.sold && listing.soldAt != null ? ' · sold ${formatTimestamp(listing.soldAt!)}' : ''}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
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

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Listing listing,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this listing?'),
        content: const Text('The photos and the sender note go with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(repoProvider).deleteListing(listing.id);
    for (final p in listing.photos) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    bumpRefresh(ref);
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// Who sent it — the whole reason the shelf exists.
class _SourceCard extends ConsumerWidget {
  const _SourceCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.glassEdge),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          ContactAvatar(label: listing.who, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SENT BY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  listing.who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          if (listing.sourceContactId != null) ...[
            Semantics(
              label: 'Call them',
              button: true,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final c = await ref
                      .read(repoProvider)
                      .contactById(listing.sourceContactId!);
                  if (c == null) return;
                  final error = await SmsChannel.openExternal(
                    'tel:${c.phoneE164}',
                  );
                  if (error != null && context.mounted) {
                    showSnack(context, error, error: true);
                  }
                },
                icon: const Icon(LucideIcons.phone, size: 18),
                color: AppColors.ink,
              ),
            ),
            Semantics(
              label: 'Message them',
              button: true,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ThreadScreen(contactId: listing.sourceContactId!),
                  ),
                ),
                icon: const Icon(LucideIcons.messageSquare, size: 18),
                color: AppColors.ink,
              ),
            ),
            Semantics(
              label: 'Their profile',
              button: true,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final c = await ref
                      .read(repoProvider)
                      .contactById(listing.sourceContactId!);
                  if (c == null || !context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ContactProfileScreen(contact: c),
                    ),
                  );
                  bumpRefresh(ref);
                },
                icon: const Icon(LucideIcons.user, size: 18),
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The share lands here: the photos are already saved, the words are
/// prefilled, and there is exactly one question — who sent this?
///
/// Also reachable by hand from the shelf's + button, with everything empty —
/// for the days Telegram hides its Share behind the wrong menu.
class ListingIntakeScreen extends ConsumerStatefulWidget {
  const ListingIntakeScreen({
    super.key,
    required this.text,
    required this.photos,
  });

  final String text;
  final List<String> photos;

  @override
  ConsumerState<ListingIntakeScreen> createState() =>
      _ListingIntakeScreenState();
}

class _ListingIntakeScreenState extends ConsumerState<ListingIntakeScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final _who = TextEditingController();
  late final List<String> _photos = [...widget.photos];
  List<Contact> _suggestions = const [];
  Contact? _picked;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final firstLine = widget.text
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    _title = TextEditingController(
      text: firstLine.length > 60 ? firstLine.substring(0, 60) : firstLine,
    );
    _body = TextEditingController(text: widget.text.trim());
    // A phone number in the shared text is probably the seller — offer it.
    final phone = RegExp(
      r'(\+?251|0)9\d[\d ]{7,10}',
    ).firstMatch(widget.text)?.group(0);
    if (phone != null) {
      _who.text = phone.replaceAll(' ', '');
      _lookup(_who.text);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _who.dispose();
    super.dispose();
  }

  /// Gallery → cache (the picker's copy) → permanent listing storage.
  Future<void> _addPhoto() async {
    final picked = await SmsChannel.pickFile();
    if (picked == null) return;
    final path = await SmsChannel.importListingPhoto(picked);
    if (path == null) {
      if (mounted) {
        showSnack(context, 'Could not read that file.', error: true);
      }
      return;
    }
    if (mounted) setState(() => _photos.add(path));
  }

  Future<void> _lookup(String q) async {
    final found = await ref.read(repoProvider).quickContactLookup(q);
    if (mounted) setState(() => _suggestions = found);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(repoProvider);
      var contactId = _picked?.id;
      final whoText = _who.text.trim();
      // A typed phone number becomes a real contact even if it was not one
      // before — a seller is exactly who the app should know. Only numbers,
      // though: "Teddy Cars 2" must stay words, not become a contact keyed
      // by nonsense.
      final digits = whoText.replaceAll(RegExp(r'[^0-9]'), '');
      if (contactId == null && digits.length >= 9) {
        contactId = await repo.contactForCompose(whoText);
      }
      final id = await repo.saveListing(
        title: _title.text,
        body: _body.text,
        sourceContactId: contactId,
        sourceText: contactId == null ? whoText : null,
        photos: _photos,
      );
      final listing = await repo.listingById(id);
      await Clipboard.setData(ClipboardData(text: listing?.code ?? ''));
      bumpRefresh(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
        context,
        'On the shelf as ${listing?.code} — code copied, paste it in your post.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Row(
                children: [
                  RoundAction(
                    icon: LucideIcons.arrowLeft,
                    label: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New listing',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.7,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          'Shared in — one question: who sent it?',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        if (i == _photos.length) {
                          // Always one more slot: shared photos can be added
                          // to, and a hand-made card starts from zero.
                          return Semantics(
                            label: 'Add a photo',
                            button: true,
                            child: Material(
                              color: AppColors.glass,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                                side: const BorderSide(
                                  color: AppColors.glassEdge,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                                onTap: _addPhoto,
                                child: const AspectRatio(
                                  aspectRatio: 4 / 3,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        LucideIcons.camera,
                                        size: 22,
                                        color: AppColors.inkMuted,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Add photo',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.inkMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: ListingPhoto(path: _photos[i]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.glassEdge),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _title,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'What is it? White Corolla 2018…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 15),
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: Border.all(color: AppColors.glassEdge),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _body,
                      maxLines: 4,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: AppColors.ink,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Details — price, km, colour…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_picked != null)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
                      child: Row(
                        children: [
                          ContactAvatar(label: _picked!.display, radius: 15),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_picked!.display} · ${_picked!.phoneLocal}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _picked = null),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(
                                LucideIcons.x,
                                size: 16,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.userRound,
                            size: 17,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _who,
                              onChanged: _lookup,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                              decoration: const InputDecoration(
                                hintText:
                                    'Who sent it? Name, number, or @telegram',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 15,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final c in _suggestions)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        onTap: () => setState(() {
                          _picked = c;
                          _suggestions = const [];
                        }),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Row(
                            children: [
                              ContactAvatar(label: c.display, radius: 15),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${c.display} · ${c.phoneLocal}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Material(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      onTap: _saving ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Center(
                          child: Text(
                            _saving ? 'Saving…' : 'Put it on the shelf',
                            style: const TextStyle(
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
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'You get a #code to paste into your channel post.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.inkMuted,
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
