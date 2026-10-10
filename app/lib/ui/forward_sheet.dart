import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'thread_screen.dart';

/// "Send this to somebody else."
///
/// Picking a person opens their conversation with the text already in the
/// composer rather than sending it there and then. Forwarding to the wrong
/// person is the classic messaging mistake, and one that cannot be taken back
/// over SMS — so the last tap stays the user's.
Future<void> showForwardSheet(
  BuildContext context,
  WidgetRef ref,
  String body,
) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ForwardSheet(body: body),
);

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet({required this.body});

  final String body;

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(int contactId) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            ThreadScreen(contactId: contactId, initialText: widget.body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    // Conversations first — forwarding is nearly always to somebody already
    // being talked to — then the wider contact list once a search narrows it.
    final campaign =
        ref.watch(threadsProvider('campaign')).valueOrNull ??
        const <ThreadSummary>[];
    final personal =
        ref.watch(threadsProvider('other')).valueOrNull ??
        const <ThreadSummary>[];
    final threads = [...personal, ...campaign]
        .where((t) => q.isEmpty || t.display.toLowerCase().contains(q))
        .take(q.isEmpty ? 12 : 30)
        .toList();

    final contacts = q.length < 2
        ? const <Contact>[]
        : (ref
                      .watch(contactSearchProvider(ContactQuery(text: q)))
                      .valueOrNull ??
                  const <Contact>[])
              .where((c) => !threads.any((t) => t.contactId == c.id))
              .take(20)
              .toList();

    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: AppColors.glassCanvas,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(22, 0, 22, 4),
                    child: Text(
                      'Forward to',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.5,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                    child: Text(
                      widget.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.search,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              onChanged: (v) => setState(() => _query = v),
                              style: const TextStyle(
                                fontSize: 14.5,
                                color: AppColors.ink,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Search people',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: (threads.isEmpty && contacts.isEmpty)
                        ? const Padding(
                            padding: EdgeInsets.fromLTRB(22, 20, 22, 30),
                            child: Text(
                              'Nobody matches that.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                            children: [
                              for (final t in threads)
                                _Row(
                                  label: t.display,
                                  sub: t.phoneLocal,
                                  phone: t.phoneE164,
                                  onTap: () => _pick(t.contactId),
                                ),
                              if (contacts.isNotEmpty)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                                  child: Text(
                                    'Other contacts',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ),
                              for (final c in contacts)
                                _Row(
                                  label: c.display,
                                  sub: c.phoneLocal,
                                  phone: c.phoneE164,
                                  onTap: () => _pick(c.id),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.sub,
    required this.phone,
    required this.onTap,
  });

  final String label;
  final String sub;
  final String phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(AppRadius.chip),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          ContactAvatar(label: label, radius: 18, phone: phone),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 18,
            color: AppColors.inkMuted,
          ),
        ],
      ),
    ),
  );
}
