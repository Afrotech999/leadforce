import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import 'common.dart';

/// Rows the importer could not normalize (spec 10.7). Nothing is ever dropped
/// silently; every one of these is editable and can be pushed back into the pool.
class NeedsReviewScreen extends ConsumerWidget {
  const NeedsReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(needsReviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Needs review')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e, onRetry: () => bumpRefresh(ref)),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.checkCircle,
              title: 'Nothing to review',
              message: 'Every imported row normalized cleanly.',
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _ReviewTile(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({required this.row});

  final NeedsReviewRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.errorContainer,
        child: Icon(LucideIcons.helpCircle, color: scheme.onErrorContainer),
      ),
      title: Text(
        row.rawPhone?.isNotEmpty == true ? row.rawPhone! : '(no number)',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.rawName != null) Text(row.rawName!),
          Text(
            row.reason,
            style: TextStyle(color: scheme.error, fontSize: 12.5),
          ),
        ],
      ),
      isThreeLine: row.rawName != null,
      trailing: const Icon(LucideIcons.pencil),
      onTap: () => _edit(context, ref),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final phone = TextEditingController(text: row.rawPhone ?? '');
    final name = TextEditingController(text: row.rawName ?? '');
    String? error;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Fix this row'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone',
                  helperText: '09… or +2519…',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final repo = ref.read(repoProvider);
                final problem = await repo.resolveNeedsReview(
                  row.id,
                  phone.text,
                  name.text,
                  row.rawSource,
                );
                if (problem != null) {
                  setState(() => error = problem);
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, 'saved');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    phone.dispose();
    name.dispose();

    if (action == 'discard') {
      await ref.read(repoProvider).discardNeedsReview(row.id);
    }
    if (action == 'saved') {
      await ref.read(repoProvider).generateBatches();
    }
    if (action != null) bumpRefresh(ref);
  }
}
