import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'add_contact_sheet.dart';
import 'common.dart';
import 'footer.dart';
import 'kit.dart' hide SectionHeader;
import 'thread_screen.dart';

/// Searchable contact list with status filters (spec 10.6).
class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({super.key});

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
  final _search = TextEditingController();
  final _typing = Debouncer();
  String? _status;

  @override
  void dispose() {
    _typing.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ContactQuery(
      text: _search.text,
      statuses: _status == null ? null : [_status!],
    );
    final async = ref.watch(contactSearchProvider(query));

    return Scaffold(
      body: Column(
        children: [
          PageBar(
            title: 'Contacts',
            actions: [
              RoundAction(
                icon: LucideIcons.userPlus,
                label: 'Add a contact',
                onPressed: () => showAddContactSheet(context),
              ),
            ],
          ),
          SearchField(
            controller: _search,
            hint: 'Search name or number',
            onChanged: (_) => _typing.run(() {
              if (mounted) setState(() {});
            }),
            onClear: _search.text.isEmpty
                ? null
                : () {
                    _search.clear();
                    _typing.flush(() => setState(() {}));
                  },
          ),
          FilterChips(
            chips: [
              FilterChipSpec(
                label: 'All',
                selected: _status == null,
                onTap: () => setState(() => _status = null),
              ),
              for (final s in ContactStatus.all)
                FilterChipSpec(
                  label: ContactStatus.label(s),
                  selected: _status == s,
                  onTap: () =>
                      setState(() => _status = _status == s ? null : s),
                ),
            ],
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingState(),
              error: (e, _) =>
                  ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
              data: (contacts) {
                if (contacts.isEmpty) {
                  return EmptyState(
                    icon: LucideIcons.search,
                    title: 'No contacts match',
                    message: _search.text.isEmpty && _status == null
                        ? 'Import a CSV to get started.'
                        : 'Try a different search or filter.',
                  );
                }
                // Dense hairline rows on white, not a card per person: this
                // list runs to thousands, and at that length a card apiece is
                // chrome repeated six thousand times.
                return Container(
                  color: AppColors.card,
                  child: ListView.separated(
                    padding: EdgeInsets.only(bottom: footerClearance(context)),
                    itemCount: contacts.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 68),
                    itemBuilder: (context, i) =>
                        _ContactRow(contact: contacts[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactDetailScreen(contactId: contact.id),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          ContactAvatar(label: contact.display, radius: 19),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  contact.phoneLocal,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          // Only a status that says something. "Not sent" stamped on every
          // row of a fresh import was ink spent restating the default — the
          // rows that have moved are the ones worth marking.
          if (contact.status != ContactStatus.notSent) ...[
            const SizedBox(width: 8),
            StatusChip(status: contact.status, dense: true),
          ],
        ],
      ),
    ),
  );
}

class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.contactId});

  final int contactId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(contactProvider(contactId));
    final messages = ref.watch(messagesProvider(contactId));

    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: contact.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (c) {
          if (c == null) {
            return const EmptyState(
              icon: LucideIcons.userX,
              title: 'Contact not found',
              message: 'It may have been removed.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    ContactAvatar(label: c.display, radius: 27),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.phoneLocal,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          StatusChip(status: c.status, dense: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _row('E.164', c.phoneE164),
                    _row('Source', c.source ?? '—'),
                    _row(
                      'Batch',
                      c.batchId == null ? 'Unassigned' : 'Batch #${c.batchId}',
                    ),
                    _row('Attempts', '${c.attempts}'),
                    _row('Last sent', formatDateTime(c.lastSentAt ?? 0)),
                    if (c.lastError != null) _row('Last error', c.lastError!),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ThreadScreen(contactId: c.id),
                          ),
                        ),
                        icon: const Icon(LucideIcons.messageCircle),
                        label: const Text('Conversation'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: c.status == ContactStatus.doNotContact
                          ? OutlinedButton.icon(
                              onPressed: () async {
                                final repo = ref.read(repoProvider);
                                await repo.reinstate(c.id);
                                await repo.generateBatches();
                                bumpRefresh(ref);
                              },
                              icon: const Icon(LucideIcons.undo2),
                              label: const Text('Unblock'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(repoProvider)
                                    .markDoNotContact(c.id);
                                bumpRefresh(ref);
                              },
                              icon: const Icon(LucideIcons.ban),
                              label: const Text('Do not contact'),
                            ),
                    ),
                  ],
                ),
              ),
              const SectionHeader('History'),
              messages.when(
                skipLoadingOnReload: true,
                loading: () => const LoadingState(),
                error: (e, _) => ErrorState(error: e),
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: Text('Nothing sent or received yet.'),
                    );
                  }
                  return Column(
                    children: [
                      for (final m in list.reversed)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            m.isInbound
                                ? LucideIcons.arrowDownLeft
                                : LucideIcons.arrowUpRight,
                            size: 18,
                          ),
                          title: Text(
                            m.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatDateTime(m.createdAt)} · ${m.status}'
                            '${m.segments > 1 ? ' · ${m.segments} segments' : ''}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// Contacts in one bucket, opened by tapping a figure on the Home stats panel.
///
/// Takes a set of statuses because "Sent" on Home means everything that left the
/// phone — `sent` and `delivered` both.
class ContactsByStatusScreen extends ConsumerWidget {
  const ContactsByStatusScreen({
    super.key,
    required this.title,
    required this.statuses,
  });

  final String title;
  final List<String> statuses;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      contactSearchProvider(ContactQuery(statuses: statuses)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
        data: (contacts) {
          if (contacts.isEmpty) {
            return EmptyState(
              icon: LucideIcons.users,
              title: 'Nobody here',
              message: 'No contacts are $title right now.',
            );
          }
          return ListView.separated(
            itemCount: contacts.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
            itemBuilder: (context, i) {
              final c = contacts[i];
              return ListTile(
                leading: ContactAvatar(label: c.display),
                title: Text(
                  c.display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  c.lastError != null
                      ? '${c.phoneLocal} · ${c.lastError}'
                      : c.phoneLocal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: StatusChip(status: c.status, dense: true),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactDetailScreen(contactId: c.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
