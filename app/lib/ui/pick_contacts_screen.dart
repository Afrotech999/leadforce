import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';

/// Tick people out of the phone book, straight into one batch.
///
/// The CSV path fills six thousand contacts; this fills a batch the user is
/// curating by hand. Every ticked row goes through the same normalizer and
/// the same one-batch-per-number rule as everything else.
class PickContactsScreen extends ConsumerStatefulWidget {
  const PickContactsScreen({
    super.key,
    required this.batchId,
    required this.batchName,
  });

  final int batchId;
  final String batchName;

  @override
  ConsumerState<PickContactsScreen> createState() => _PickContactsScreenState();
}

class _PickContactsScreenState extends ConsumerState<PickContactsScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  List<({String? name, String? phone})> _device = const [];
  final _picked = <String>{};
  bool _granted = false;
  bool _loading = true;
  bool _saving = false;

  /// The request came back refused without a dialog — Android does that after
  /// two denials, and from then on the only way in is the settings page.
  bool _blockedBySystem = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// Coming back from the settings page is a resume; if the permission was
  /// granted there, the gate should open without being asked to.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_granted) _load();
  }

  Future<void> _load() async {
    final granted = await SmsChannel.hasContactsPermission();
    if (granted) {
      final list = await SmsChannel.readDeviceContacts();
      if (!mounted) return;
      setState(() {
        _granted = true;
        _device = list;
        _loading = false;
      });
      // The phone book is in hand — name any threads stored as bare numbers.
      final filled = await ref.read(repoProvider).fillNamesFromDevice(list);
      if (filled > 0 && mounted) bumpRefresh(ref);
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _grant() async {
    final ok = await SmsChannel.requestContactsPermission();
    if (ok) {
      setState(() => _loading = true);
      await _load();
    } else if (mounted) {
      setState(() => _blockedBySystem = true);
      await SmsChannel.openAppSettings();
    }
  }

  Future<void> _save() async {
    if (_saving || _picked.isEmpty) return;
    setState(() => _saving = true);
    try {
      final entries = _device.where((c) => _picked.contains(c.phone)).toList();
      final result = await ref
          .read(repoProvider)
          .addPhonesToBatch(widget.batchId, entries);
      bumpRefresh(ref);
      if (!mounted) return;
      final parts = <String>[
        if (result.added > 0) '${result.added} added',
        if (result.existing > 0) '${result.existing} already on a list',
        if (result.invalid > 0) '${result.invalid} not usable numbers',
      ];
      showSnack(context, parts.isEmpty ? 'Nothing to add.' : parts.join(' · '));
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? _device
        : _device
              .where(
                (c) =>
                    (c.name ?? '').toLowerCase().contains(q) ||
                    (c.phone ?? '').replaceAll(' ', '').contains(q),
              )
              .toList();

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'From your phone',
              subtitle: 'into ${widget.batchName}',
            ),
            if (_granted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search name or number',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 13),
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
            Expanded(
              child: _loading
                  ? const LoadingState()
                  : !_granted
                  ? EmptyState(
                      icon: LucideIcons.bookUser,
                      title: _blockedBySystem
                          ? 'Android is blocking the prompt'
                          : 'Your phone book stays yours',
                      message: _blockedBySystem
                          ? 'The permission dialog was refused before, so '
                                'Android will not show it again. In the '
                                'settings page that just opened, tap '
                                'Permissions → Contacts → Allow, then come '
                                'back.'
                          : 'LeadForce reads names and numbers once, on your '
                                'say-so. Nothing leaves the phone.',
                      action: EmptyAction(
                        label: _blockedBySystem
                            ? 'Open phone settings'
                            : 'Allow contacts',
                        icon: _blockedBySystem
                            ? LucideIcons.settings2
                            : LucideIcons.check,
                        onTap: _blockedBySystem
                            ? SmsChannel.openAppSettings
                            : _grant,
                      ),
                    )
                  : matches.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.searchX,
                      title: 'Nobody matches',
                      message: 'Try fewer letters.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final c = matches[i];
                        final phone = (c.phone ?? '').trim();
                        final name = (c.name ?? '').trim();
                        final on = _picked.contains(c.phone);
                        return InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          onTap: phone.isEmpty
                              ? null
                              : () => setState(() {
                                  on
                                      ? _picked.remove(c.phone)
                                      : _picked.add(c.phone!);
                                }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                ContactAvatar(
                                  label: name.isEmpty ? phone : name,
                                  radius: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name.isEmpty ? phone : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.2,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      if (name.isNotEmpty)
                                        Text(
                                          phone,
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
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: on
                                        ? AppColors.accent
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: on
                                          ? AppColors.accent
                                          : AppColors.muted,
                                      width: 1.6,
                                    ),
                                  ),
                                  child: on
                                      ? const Icon(
                                          LucideIcons.check,
                                          size: 15,
                                          color: AppColors.ink,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Material(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: _saving ? null : _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Center(
                        child: Text(
                          _saving
                              ? 'Adding…'
                              : 'Add ${_picked.length} to ${widget.batchName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              ),
            ),
    );
  }
}
