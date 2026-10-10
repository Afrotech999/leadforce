import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/segments.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'sending_screen.dart';
import 'templates_sheet.dart';

/// Compose a campaign against one pre-made batch (spec 10.2).
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, required this.batchId});

  final int batchId;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  int _delaySeconds = 5;
  int? _subId;
  String _fallback = 'there';
  bool _loading = true;
  bool _starting = false;
  List<Contact> _preview = const [];
  int _unsent = 0;
  int _retryable = 0;
  bool _includeFailed = true;
  int _capRemaining = 0;
  bool _capCountsSegments = true;

  /// Everyone this run will actually message.
  int get _recipients => _unsent + (_includeFailed ? _retryable : 0);

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(repoProvider);
    final delay = await repo.getSettingInt(SettingKeys.delaySeconds, 5);
    final sim = await repo.getSetting(SettingKeys.simSubscriptionId, '');
    final fallback = await repo.getSetting(SettingKeys.nameFallback, 'there');
    final contacts = await repo.contactsInBatch(widget.batchId);
    final pending = contacts
        .where((c) => c.status == ContactStatus.notSent)
        .toList();
    final failed = contacts
        .where((c) => c.status == ContactStatus.failed)
        .toList();
    final retryable = await repo.retryableInBatch(widget.batchId);
    // The message is almost always the same one as last time. Retyping Amharic
    // into an empty box for every batch is the kind of small tax that makes a
    // tool feel unfinished.
    final last = await repo.getSetting(SettingKeys.lastTemplate, '');
    final capCountsSegments =
        await repo.getSettingInt(SettingKeys.capCountsSegments, 1) == 1;
    final cap = await repo.getSettingInt(SettingKeys.dailyCap, 100);
    final used = capCountsSegments
        ? await repo.segmentsSentToday()
        : await repo.sentToday();
    if (!mounted) return;
    setState(() {
      _delaySeconds = delay;
      _subId = int.tryParse(sim);
      _fallback = fallback;
      _unsent = pending.length;
      _retryable = retryable;
      _preview = [...pending, ...failed].take(3).toList();
      _capCountsSegments = capCountsSegments;
      _capRemaining = (cap - used).clamp(0, cap);
      _loading = false;
    });
    if (_controller.text.isEmpty && last.isNotEmpty) _controller.text = last;
  }

  /// A saved sentence, put in the box with its `{name}` left intact — here the
  /// placeholder is the point, since the engine fills it per contact.
  Future<void> _insertTemplate() async {
    final chosen = await showTemplatesSheet(
      context,
      currentText: _controller.text,
    );
    if (chosen == null || !mounted) return;
    final existing = _controller.text.trimRight();
    _controller.text = existing.isEmpty ? chosen : '$existing\n$chosen';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _insertNameChip() {
    final text = _controller.text;
    final sel = _controller.selection;
    final at = sel.isValid ? sel.start : text.length;
    final updated = text.replaceRange(
      at,
      sel.isValid ? sel.end : text.length,
      '{name}',
    );
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: at + '{name}'.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingState());
    }

    final body = _controller.text;
    final rendered = renderTemplate(
      body,
      _preview.isEmpty ? null : _preview.first.name,
      _fallback,
    );
    final info = countSegments(rendered.isEmpty ? body : rendered);
    final sims = ref.watch(simsProvider).valueOrNull ?? const <SimCard>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Compose campaign')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _RecipientsCard(
            unsent: _unsent,
            retryable: _retryable,
            includeFailed: _includeFailed,
            onIncludeFailed: (v) => setState(() => _includeFailed = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            focusNode: _focus,
            maxLines: 8,
            minLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Message',
              hintText: 'Hello {name}, …',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Built here rather than as an ActionChip: a chip label with no
              // colour of its own takes whatever Material hands it, and this one
              // came out white on a pale pill — the button was there and could
              // not be read.
              Material(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: _insertNameChip,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.user, size: 16, color: AppColors.ink),
                        SizedBox(width: 7),
                        Text(
                          '{name}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The same saved sentences the one-to-one composer offers. A
              // campaign template and a personal one are the same thing.
              Material(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: _insertTemplate,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.zap, size: 16, color: AppColors.ink),
                        SizedBox(width: 7),
                        Text(
                          'Saved',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nameless contacts get "$_fallback"',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SegmentCounter(
            info: info,
            recipients: _recipients,
            capRemaining: _capRemaining,
            capCountsSegments: _capCountsSegments,
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 16),
            _PreviewCard(
              contacts: _preview,
              template: body,
              fallback: _fallback,
            ),
          ],
          const SizedBox(height: 16),
          if (sims.length > 1)
            _SimPicker(
              sims: sims,
              selected: _subId,
              onChanged: (v) => setState(() => _subId = v),
            ),
          _DelaySlider(
            seconds: _delaySeconds,
            onChanged: (v) => setState(() => _delaySeconds = v),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      (_starting || body.trim().isEmpty || _recipients == 0)
                      ? null
                      : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.send),
                  label: Text(
                    _recipients == 0
                        ? 'Nothing left to send in this batch'
                        : 'Send to $_recipients contact${_recipients == 1 ? '' : 's'}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Send later. The same run, on the clock instead of on the tap.
              Semantics(
                label: 'Schedule this send',
                button: true,
                child: Material(
                  color: AppColors.glass,
                  shape: const CircleBorder(
                    side: BorderSide(color: AppColors.glassEdge),
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap:
                        (_starting || body.trim().isEmpty || _recipients == 0)
                        ? null
                        : _schedule,
                    child: const Padding(
                      padding: EdgeInsets.all(13),
                      child: Icon(
                        LucideIcons.calendarClock,
                        size: 20,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    final repo = ref.read(repoProvider);
    setState(() => _starting = true);

    try {
      // 1. Permissions. The native side asks for SMS, phone state and notifications
      //    in one dialog; only SEND_SMS is non-negotiable.
      final granted = await SmsChannel.requestSmsPermissions();
      if (!granted) {
        if (!mounted) return;
        showSnack(context, 'SMS permission is required to send.', error: true);
        setState(() => _starting = false);
        return;
      }

      // 2. Default-SMS role. Explained first, then one tap (spec 9.2).
      final info = await SmsChannel.defaultSmsInfo();
      if (!info.isDefault) {
        if (!mounted) return;
        final proceed = await _explainDefaultRole(context, info);
        if (proceed != true) {
          setState(() => _starting = false);
          return;
        }
        // Resolves once the user has answered the system dialog.
        final gotRole = await SmsChannel.requestDefaultRole();
        if (!gotRole) {
          if (!mounted) return;
          final anyway = await _confirmWithoutRole(context);
          if (anyway != true) {
            setState(() => _starting = false);
            return;
          }
        }
      }

      // 3. Remember the chosen delay / SIM as the new defaults.
      await repo.setSetting(SettingKeys.delaySeconds, '$_delaySeconds');
      if (_subId != null) {
        await repo.setSetting(SettingKeys.simSubscriptionId, '$_subId');
      }

      // 4. Put the retryable failures back in the pool first, so the engine —
      //    which only ever targets 'not_sent' — actually reaches them.
      if (_includeFailed && _retryable > 0) {
        final requeued = await repo.retryFailed(batchId: widget.batchId);
        if (requeued == 0 && _unsent == 0) {
          if (!mounted) return;
          showSnack(
            context,
            'Those contacts have used up their retry attempts. Raise "Max attempts '
            'per contact" in Settings to try them again.',
            error: true,
          );
          setState(() => _starting = false);
          return;
        }
      }

      // 5. Writing the campaign row IS starting the campaign; the service picks it up.
      final campaignId = await repo.createCampaign(
        batchId: widget.batchId,
        template: _controller.text.trim(),
        simSubscriptionId: _subId,
        delaySeconds: _delaySeconds,
      );
      await repo.setSetting(SettingKeys.lastTemplate, _controller.text.trim());
      await SmsChannel.startSendService();

      if (!mounted) return;
      bumpRefresh(ref);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SendingScreen(campaignId: campaignId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Could not start: $e', error: true);
      setState(() => _starting = false);
    }
  }

  /// The same run as [_start], put on the clock. Permissions and the
  /// default-SMS role are settled now, while the user is looking at the
  /// screen — an alarm at 9am has nobody to ask.
  Future<void> _schedule() async {
    final repo = ref.read(repoProvider);
    setState(() => _starting = true);

    try {
      final granted = await SmsChannel.requestSmsPermissions();
      if (!granted) {
        if (!mounted) return;
        showSnack(context, 'SMS permission is required to send.', error: true);
        setState(() => _starting = false);
        return;
      }

      final info = await SmsChannel.defaultSmsInfo();
      if (!info.isDefault) {
        if (!mounted) return;
        final proceed = await _explainDefaultRole(context, info);
        if (proceed != true) {
          setState(() => _starting = false);
          return;
        }
        final gotRole = await SmsChannel.requestDefaultRole();
        if (!gotRole) {
          if (!mounted) return;
          final anyway = await _confirmWithoutRole(context);
          if (anyway != true) {
            setState(() => _starting = false);
            return;
          }
        }
      }

      // One schedule at a time. Two alarms would race each other into the
      // same send loop; the newer intention simply replaces the older one.
      final existing = await repo.scheduledCampaign();
      if (existing != null) {
        if (!mounted) return;
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace the scheduled send?'),
            content: Text(
              '${existing.batchName} is already set to go out '
              '${scheduleLabel(existing.at)}. Only one send can wait on the '
              'clock — scheduling this one cancels that one.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep it'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace != true) {
          setState(() => _starting = false);
          return;
        }
        await repo.cancelScheduled(existing.campaignId);
        await SmsChannel.cancelAlarm(campaignId: existing.campaignId);
      }

      if (!mounted) return;
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 30)),
        helpText: 'Day to send',
      );
      if (!mounted) return;
      if (date == null) {
        setState(() => _starting = false);
        return;
      }
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
        helpText: 'Time to send',
      );
      if (!mounted) return;
      if (time == null) {
        setState(() => _starting = false);
        return;
      }
      final at = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (at.isBefore(now.add(const Duration(minutes: 2)))) {
        showSnack(
          context,
          'Pick a time at least a couple of minutes from now — or just '
          'press Send.',
          error: true,
        );
        setState(() => _starting = false);
        return;
      }

      await repo.setSetting(SettingKeys.delaySeconds, '$_delaySeconds');
      if (_subId != null) {
        await repo.setSetting(SettingKeys.simSubscriptionId, '$_subId');
      }

      // Failures go back in the pool now, not at fire time: the engine only
      // ever targets 'not_sent', and there is nobody around at 9am to answer
      // a "requeue?" question.
      if (_includeFailed && _retryable > 0) {
        final requeued = await repo.retryFailed(batchId: widget.batchId);
        if (requeued == 0 && _unsent == 0) {
          if (!mounted) return;
          showSnack(
            context,
            'Those contacts have used up their retry attempts. Raise "Max '
            'attempts per contact" in Settings to try them again.',
            error: true,
          );
          setState(() => _starting = false);
          return;
        }
      }

      final campaignId = await repo.scheduleCampaign(
        batchId: widget.batchId,
        template: _controller.text.trim(),
        simSubscriptionId: _subId,
        delaySeconds: _delaySeconds,
        at: at.millisecondsSinceEpoch,
      );
      await repo.setSetting(SettingKeys.lastTemplate, _controller.text.trim());
      await SmsChannel.scheduleAlarm(
        campaignId: campaignId,
        atMillis: at.millisecondsSinceEpoch,
      );

      if (!mounted) return;
      bumpRefresh(ref);
      Navigator.of(context).pop();
      showSnack(
        context,
        'Scheduled — goes out ${scheduleLabel(at.millisecondsSinceEpoch)}. '
        'Keep the phone on and the SIM in.',
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, 'Could not schedule: $e', error: true);
      setState(() => _starting = false);
    }
  }

  Future<bool?> _explainDefaultRole(BuildContext context, DefaultSmsInfo info) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(LucideIcons.messageSquare),
        title: const Text('Become the default SMS app?'),
        content: Text(
          'To send this batch without Android interrupting you every 30 messages, and to '
          'catch replies here instead of in ${info.label ?? 'your usual app'}, this app '
          'needs to be your default SMS app while the campaign runs.\n\n'
          'Your personal messages and OTPs will arrive here until you switch back. '
          'They will be kept separate, under Inbox → Other, and we will remind you to '
          'switch back when the batch ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmWithoutRole(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(LucideIcons.alertTriangle),
        title: const Text('Send without being default?'),
        content: const Text(
          'Android will show a confirmation dialog after roughly 30 messages, and replies '
          'will go to your normal Messages app instead of this one.\n\n'
          'You can still send, but the batch will need babysitting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send anyway'),
          ),
        ],
      ),
    );
  }
}

class _RecipientsCard extends StatelessWidget {
  const _RecipientsCard({
    required this.unsent,
    required this.retryable,
    required this.includeFailed,
    required this.onIncludeFailed,
  });

  final int unsent;
  final int retryable;
  final bool includeFailed;
  final ValueChanged<bool> onIncludeFailed;

  @override
  Widget build(BuildContext context) {
    final total = unsent + (includeFailed ? retryable : 0);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(LucideIcons.users),
            title: Text('$total recipient${total == 1 ? '' : 's'}'),
            subtitle: Text(
              retryable > 0
                  ? '$unsent never sent, $retryable failed and can be retried. '
                        'Contacts already reached, or who replied, are excluded.'
                  : 'Contacts already sent to, or who replied, are excluded '
                        'automatically.',
            ),
            isThreeLine: retryable > 0,
          ),
          if (retryable > 0)
            SwitchListTile(
              value: includeFailed,
              onChanged: onIncludeFailed,
              secondary: const Icon(LucideIcons.rotateCcw),
              title: Text('Retry $retryable failed'),
              subtitle: const Text(
                'Sends to contacts whose last attempt failed — for example when '
                'credit ran out.',
              ),
            ),
        ],
      ),
    );
  }
}

/// Live segment + cost counter (spec 2.4 / 10.2).
class _SegmentCounter extends StatelessWidget {
  const _SegmentCounter({
    required this.info,
    required this.recipients,
    required this.capRemaining,
    required this.capCountsSegments,
  });

  final SegmentInfo info;
  final int recipients;
  final int capRemaining;
  final bool capCountsSegments;

  /// How many of these recipients today's cap still has room for. Told before
  /// the send rather than discovered when the engine stops halfway.
  int get _reachableToday {
    if (info.segments <= 0) return recipients;
    final room = capCountsSegments
        ? capRemaining ~/ info.segments
        : capRemaining;
    return room.clamp(0, recipients);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalMessages = info.segments * recipients;
    final reachable = _reachableToday;

    return Card(
      color: info.isUnicode
          ? scheme.tertiaryContainer
          : scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "GSM-7" beside "153/153 · 2 segments" is wider than a narrow
            // phone once the counts reach three digits, so the encoding label
            // gives way first rather than the row running off the card.
            Row(
              children: [
                Icon(
                  info.isUnicode ? LucideIcons.languages : LucideIcons.type,
                  size: 18,
                  color: info.isUnicode
                      ? scheme.onTertiaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    info.encodingLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: info.isUnicode ? scheme.onTertiaryContainer : null,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${info.units}/${info.unitsPerSegment} · ${info.segments} '
                  'segment${info.segments == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: info.isUnicode
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$totalMessages message${totalMessages == 1 ? '' : 's'} will be billed '
              '(${info.segments} × $recipients recipients)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: info.isUnicode ? scheme.onTertiaryContainer : null,
              ),
            ),
            if (reachable < recipients) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.hourglass, size: 16, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reachable == 0
                          ? "Today's cap is already used up, so this batch will stop "
                                'immediately. Raise the cap in Settings, or run it '
                                'tomorrow.'
                          : 'Today\'s cap has room for about $reachable of these '
                                '$recipients. The rest stay unsent and roll into the '
                                'next run.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: scheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (info.isUnicode) ...[
              const SizedBox(height: 8),
              Text(
                'Amharic and other non-Latin characters force Unicode encoding, so each '
                'segment holds 70 characters instead of 160. '
                '${info.nonGsmSample.isEmpty ? '' : 'First such character: "${info.nonGsmSample}".'}',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.contacts,
    required this.template,
    required this.fallback,
  });

  final List<Contact> contacts;
  final String template;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Exactly what the first three contacts will receive.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final c in contacts) ...[
              Text(
                '${c.display} · ${c.phoneLocal}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Text(
                  template.trim().isEmpty
                      ? 'Type a message to see the preview.'
                      : renderTemplate(template, c.name, fallback),
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimPicker extends StatelessWidget {
  const _SimPicker({
    required this.sims,
    required this.selected,
    required this.onChanged,
  });

  final List<SimCard> sims;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SIM', style: Theme.of(context).textTheme.titleSmall),
          for (final sim in sims)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected == sim.subscriptionId
                    ? LucideIcons.circleDot
                    : LucideIcons.circle,
                color: selected == sim.subscriptionId
                    ? Theme.of(context).colorScheme.onSurface
                    : null,
              ),
              title: Text(sim.displayName),
              subtitle: Text(sim.label),
              onTap: () => onChanged(sim.subscriptionId),
            ),
        ],
      ),
    ),
  );
}

class _DelaySlider extends StatelessWidget {
  const _DelaySlider({required this.seconds, required this.onChanged});

  final int seconds;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.glassEdge),
    ),
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Delay between messages',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '${seconds}s',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context),
          child: Slider(
            value: seconds.toDouble(),
            min: 3,
            max: 10,
            divisions: 7,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        const SizedBox(height: 2),
        // One line. The reasoning behind the pacing lives on the About screen;
        // what matters here is how long this batch will take.
        Text(
          _estimate(seconds),
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
        ),
      ],
    ),
  );

  static String _estimate(int seconds) {
    final minutes = (100 * seconds) / 60;
    return 'A 100-contact batch takes about ${minutes.toStringAsFixed(0)} minutes.';
  }
}
