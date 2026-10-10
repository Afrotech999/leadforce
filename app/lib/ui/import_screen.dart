import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/csv_import.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'needs_review_screen.dart';

/// Two ways in: a CSV file, or the phone's own address book (spec 6, extended).
///
/// Both land in `importRows`, so normalization, deduplication and the
/// needs-review split behave identically whichever you pick.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  String _busyLabel = '';
  ImportResult? _result;

  Future<void> _run(String label, Future<ImportResult?> Function() work) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
      _result = null;
    });
    try {
      final result = await work();
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
      if (result != null) bumpRefresh(ref);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = ImportResult.failure('$e');
        _busy = false;
      });
    }
  }

  Future<ImportResult?> _fromCsv() async {
    final path = await SmsChannel.pickFile();
    if (path == null) return null;
    return importCsv(ref.read(repoProvider), File(path));
  }

  Future<ImportResult?> _fromPhonebook() async {
    final granted = await SmsChannel.requestContactsPermission();
    if (!granted) {
      return ImportResult.failure(
        'Permission to read your contacts was declined, so nothing was imported.',
      );
    }
    final entries = await SmsChannel.readDeviceContacts();
    if (entries.isEmpty) {
      return ImportResult.failure('No contacts with phone numbers were found.');
    }
    return importRows(
      ref.read(repoProvider),
      entries
          .map((e) => (name: e.name, phone: e.phone, source: 'Phone contacts'))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Add contacts')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SourceCard(
            icon: LucideIcons.fileText,
            title: 'From a CSV file',
            body:
                'Headers are matched loosely, in any order. Both 09… and '
                '+2519… work.',
            action: 'Choose a file',
            busy: _busy && _busyLabel == 'csv',
            enabled: !_busy,
            onPressed: () => _run('csv', _fromCsv),
          ),
          const SizedBox(height: 12),
          _SourceCard(
            icon: LucideIcons.contact,
            title: 'From your phone contacts',
            body:
                'Nothing leaves the phone, and nobody is messaged until you '
                'start a campaign.',
            action: 'Import from phone',
            busy: _busy && _busyLabel == 'phone',
            enabled: !_busy,
            onPressed: () => _run('phone', _fromPhonebook),
          ),
          const SizedBox(height: 20),
          const _Reassurance(),
          if (result != null) ...[
            const SizedBox(height: 20),
            if (result.failed)
              _Failure(message: result.error!)
            else
              _Summary(result: result),
          ],
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String action;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(icon, color: AppColors.ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: enabled ? onPressed : null,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(action),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Reassurance extends StatelessWidget {
  const _Reassurance();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.infoSoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.shield, size: 18, color: AppColors.info),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Duplicates are skipped. Anything that is not a readable '
            'Ethiopian number goes to Needs review rather than being lost.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.dangerSoft,
      borderRadius: BorderRadius.circular(AppRadius.card),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.alertCircle, color: AppColors.danger, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.checkCircle, color: AppColors.ink),
              const SizedBox(width: 8),
              Text('Imported', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          _line(context, 'Rows read', '${result.rows}'),
          _line(context, 'New contacts', '${result.imported}'),
          _line(context, 'Duplicates skipped', '${result.duplicates}'),
          _line(context, 'Needs review', '${result.needsReview}'),
          _line(context, 'New batches created', '${result.batchesCreated}'),
          if (result.needsReview > 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NeedsReviewScreen()),
                ),
                icon: const Icon(LucideIcons.listFilter, size: 18),
                label: Text('Review ${result.needsReview} rows'),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _line(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ],
    ),
  );
}
