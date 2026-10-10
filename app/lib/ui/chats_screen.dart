import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'contact_notes_screen.dart';
import 'kit.dart';
import 'notes_screen.dart';

/// Everything that arrived in the other messengers, in one list.
///
/// Read from their notifications, on this phone, for the apps the user
/// ticked and no others. Replying happens in the app it came from — tapping
/// a row opens it — because a notification's reply channel dies the moment
/// the message is read anywhere else, and a button that works only sometimes
/// is worse than no button.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list is reading it; the badge should not outlive the visit.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(repoProvider).markChatsSeen();
      if (mounted) bumpRefresh(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(notificationAccessProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final chosen = (settings?[SettingKeys.chatApps] ?? '')
        .split(',')
        .where((p) => p.trim().isNotEmpty)
        .length;
    final messages =
        ref.watch(chatMessagesProvider).valueOrNull ?? const <ChatMessage>[];

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            PageBar(
              title: 'Other Apps',
              subtitle: 'What came in everywhere else · tap to open it there',
              actions: [
                RoundAction(
                  icon: LucideIcons.trash2,
                  label: 'Clear this feed',
                  onPressed: () => _clear(context),
                ),
              ],
            ),
            Expanded(
              child: access == false
                  ? const _Gate(
                      title: 'LeadForce is not allowed to read notifications',
                      message:
                          'Android keeps this behind its own switch. Turn it '
                          'on for LeadForce and messages from the apps you pick '
                          'will appear here — read on this phone, stored on '
                          'this phone, sent nowhere.\n\n'
                          'If the switch is greyed out and Android says '
                          '"Restricted setting": that is because LeadForce was '
                          'installed from a file rather than the Play Store. '
                          'Hold the LeadForce icon → App info → ⋮ (top right) → '
                          'Allow restricted settings. Then come back here.',
                      label: 'Open the setting',
                    )
                  : chosen == 0
                  ? const _Gate(
                      title: 'No apps picked yet',
                      message:
                          'Choose which messengers LeadForce should watch in '
                          'Settings → Other messengers. It reads nothing '
                          'from any app you have not ticked.',
                      label: 'Open settings',
                      toSettings: true,
                    )
                  : messages.isEmpty
                  ? const EmptyState(
                      icon: LucideIcons.messagesSquare,
                      title: 'Nothing yet',
                      message:
                          'The next message that arrives in one of your '
                          'picked apps shows up here. Older ones cannot be '
                          'read — only what arrives from now on.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _Row(message: messages[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget these messages?'),
        content: const Text(
          'Everything read from the other apps is deleted from LeadForce. The '
          'messages themselves stay where they are, in their own apps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(repoProvider).clearChatMessages();
    bumpRefresh(ref);
  }
}

class _Gate extends ConsumerWidget {
  const _Gate({
    required this.title,
    required this.message,
    required this.label,
    this.toSettings = false,
  });

  final String title;
  final String message;
  final String label;
  final bool toSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) => EmptyState(
    icon: LucideIcons.messagesSquare,
    title: title,
    message: message,
    action: EmptyAction(
      label: label,
      icon: LucideIcons.settings2,
      onTap: () async {
        if (toSettings) {
          Navigator.of(context).pop();
          return;
        }
        await SmsChannel.openNotificationAccess();
      },
    ),
  );
}

class _Row extends ConsumerWidget {
  const _Row({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = message;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: m.seen ? AppColors.glass : AppColors.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.glassEdge),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () async {
            final ok = await SmsChannel.openApp(m.app);
            if (!ok && context.mounted) {
              showSnack(context, 'Could not open ${m.appLabel}.', error: true);
            }
          },
          onLongPress: () => _actions(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AvatarWithApp(label: m.who, package: m.app),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatTimestamp(m.at),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          AppIcon(package: m.app, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            m.appLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkMuted,
                            ),
                          ),
                          if (m.room != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'in ${m.room}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ],
                          if (m.contactId == null) ...[
                            const SizedBox(width: 6),
                            const Text(
                              '· not linked',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final m = message;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(LucideIcons.userRoundPlus, size: 20),
                title: Text(
                  m.contactId == null
                      ? 'This is somebody I know'
                      : 'Link to a different person',
                ),
                subtitle: const Text('Their messages count as talking'),
                onTap: () => Navigator.pop(ctx, 'link'),
              ),
              if (m.contactId != null)
                ListTile(
                  leading: const Icon(LucideIcons.user, size: 20),
                  title: const Text('Open their profile'),
                  onTap: () => Navigator.pop(ctx, 'profile'),
                ),
              ListTile(
                leading: const Icon(LucideIcons.stickyNote, size: 20),
                title: const Text('Write it down'),
                onTap: () => Navigator.pop(ctx, 'note'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'link':
        final picked = await _pickContact(context, ref);
        if (picked == null) return;
        await ref
            .read(repoProvider)
            .linkChatSender(app: m.app, sender: m.sender, contactId: picked.id);
        bumpRefresh(ref);
        if (context.mounted) {
          showSnack(context, '${m.sender} is ${picked.display}.');
        }
      case 'profile':
        final c = await ref.read(repoProvider).contactById(m.contactId!);
        if (c == null || !context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ContactProfileScreen(contact: c)),
        );
        bumpRefresh(ref);
      case 'note':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NoteEditorScreen(
              contactId: m.contactId,
              initialBody: '${m.appLabel} · ${m.who}\n${m.body}\n',
            ),
          ),
        );
        bumpRefresh(ref);
    }
  }

  Future<Contact?> _pickContact(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<Contact>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _ContactPicker(),
      );
}

/// Type a name, tap the person. Small enough to live here rather than earn
/// its own file.
class _ContactPicker extends ConsumerStatefulWidget {
  const _ContactPicker();

  @override
  ConsumerState<_ContactPicker> createState() => _ContactPickerState();
}

class _ContactPickerState extends ConsumerState<_ContactPicker> {
  final _search = TextEditingController();
  List<Contact> _found = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _lookup(String q) async {
    final found = await ref.read(repoProvider).quickContactLookup(q, limit: 20);
    if (mounted) setState(() => _found = found);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardHigh,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
                          autofocus: true,
                          onChanged: _lookup,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: AppColors.ink,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Who is this?',
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
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _found)
                      ListTile(
                        leading: ContactAvatar(label: c.display, radius: 18),
                        title: Text(c.display),
                        subtitle: Text(c.phoneLocal),
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
