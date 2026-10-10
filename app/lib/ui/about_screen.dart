import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// What the app does, and what it never does.
///
/// The contact details that used to live here are gone: the app ships to one
/// person who already knows how to reach themselves, and a screen of blank
/// fields waiting to be filled in was a form nobody was going to fill. What is
/// left is the part worth keeping — the promises the app makes about your SIM,
/// your list and your phone.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('How this app works')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
      children: const [
        _Point(
          icon: LucideIcons.smartphone,
          title: 'Your own SIM, your own allowance',
          body:
              'Every message is an ordinary SMS from this phone. There is no '
              'gateway and no sender ID to buy — the cost is whatever your '
              'operator charges.',
        ),
        _Point(
          icon: LucideIcons.user,
          title: 'One person at a time',
          body:
              'Nobody is put in a group thread and nobody can see anyone else '
              'on your list. Each contact gets one message addressed to them.',
        ),
        _Point(
          icon: LucideIcons.smartphoneNfc,
          title: 'Nothing leaves this phone',
          body:
              'No server, no cloud, no account. Your contacts, messages and '
              'replies live in this app and back up to a folder you choose.',
        ),
        _Point(
          icon: LucideIcons.calculator,
          title: 'Counted the way your operator counts',
          body:
              'Latin text fits 160 characters in one SMS; Amharic fits 70, so '
              'the same message costs about three times as much. The daily cap '
              'counts SMS rather than messages, and SMS used shows where it '
              'went.',
        ),
        _Point(
          icon: LucideIcons.timer,
          title: 'Paced, with a daily cap and quiet hours',
          body:
              'Messages go out one at a time with an uneven gap between them, '
              'a hard stop for the day, and nothing at all overnight.',
        ),
        _Point(
          icon: LucideIcons.circleSlash,
          title: 'Stop means stop',
          body:
              'Anyone who replies STOP — or አቁም — is blocked permanently and '
              'never appears in another batch.',
          last: true,
        ),
      ],
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(bottom: last ? 0 : 10),
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.glassEdge),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.ink),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.inkMuted,
          ),
        ),
      ],
    ),
  );
}
