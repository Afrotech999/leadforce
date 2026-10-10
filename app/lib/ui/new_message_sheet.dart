import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/phone.dart';
import '../native/sms_channel.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';
import 'thread_screen.dart';

/// Start a conversation with anybody — a number typed in, or a person picked
/// from the phone book. The Messages tab could only ever *answer*; there was
/// no way to speak first.
Future<void> showNewMessageSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const _NewMessageSheet(),
);

class _NewMessageSheet extends ConsumerStatefulWidget {
  const _NewMessageSheet();

  @override
  ConsumerState<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends ConsumerState<_NewMessageSheet> {
  final _field = TextEditingController();
  List<({String? name, String? phone})> _device = const [];
  bool _granted = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _field.addListener(() => setState(() {}));
    _loadIfAllowed();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _loadIfAllowed() async {
    if (!await SmsChannel.hasContactsPermission()) return;
    final list = await SmsChannel.readDeviceContacts();
    if (mounted) {
      setState(() {
        _granted = true;
        _device = tidyPhoneBook(list);
      });
    }
    // The phone book is in hand — name any threads that arrived as numbers.
    final filled = await ref.read(repoProvider).fillNamesFromDevice(list);
    if (filled > 0 && mounted) bumpRefresh(ref);
  }

  Future<void> _grant() async {
    final ok = await SmsChannel.requestContactsPermission();
    if (ok) {
      await _loadIfAllowed();
    } else if (mounted) {
      // Android stops showing the dialog after two denials; from then on the
      // only way in is the app's settings page.
      showSnack(
        context,
        'Android is blocking the contacts prompt. Allow Contacts in the '
        'phone settings that just opened.',
      );
      await SmsChannel.openAppSettings();
    }
  }

  Future<void> _openThread(String raw) async {
    if (_opening) return;
    _opening = true;
    try {
      final contactId = await ref.read(repoProvider).contactForCompose(raw);
      if (!mounted) return;
      if (contactId == null) {
        showSnack(context, 'Type a phone number first.', error: true);
        return;
      }
      bumpRefresh(ref);
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(
        MaterialPageRoute(builder: (_) => ThreadScreen(contactId: contactId)),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final query = _field.text.trim().toLowerCase();
    // A number is searched by its digits alone, so "0911" finds a contact
    // stored as "+251 91 1..." — the two are the same number written twice.
    final digits = query.replaceAll(RegExp(r'\D'), '');
    final matches = query.isEmpty
        ? _device
        : _device.where((c) {
            if ((c.name ?? '').toLowerCase().contains(query)) return true;
            if (digits.isEmpty) return false;
            return (c.phone ?? '')
                .replaceAll(RegExp(r'\D'), '')
                .contains(digits);
          }).toList();
    final canSubmit = _field.text.contains(RegExp(r'[0-9]'));

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
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
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
                      margin: const EdgeInsets.only(top: 10, bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Text(
                      'New message',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.8,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        border: Border.all(color: AppColors.glassEdge),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.phone,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _field,
                              autofocus: true,
                              // Letters, not just digits. The field said
                              // "or search your contacts" while a formatter
                              // threw away every letter typed into it, so the
                              // only way to reach anybody was to scroll — and
                              // the scroll was capped. Between them, a phone
                              // book of thousands looked like a phone book of
                              // fifty entries beginning with a symbol.
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.words,
                              onSubmitted: (v) {
                                if (canSubmit) _openThread(v);
                              },
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Number — or search your contacts',
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
                  ),
                  if (!_granted)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: InkWell(
                        onTap: _grant,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Row(
                            children: const [
                              Icon(
                                LucideIcons.bookUser,
                                size: 17,
                                color: AppColors.info,
                              ),
                              SizedBox(width: 9),
                              Text(
                                'Search your phone contacts too',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.info,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        // Every one of them. ListView.builder only builds the
                        // rows on screen, so a phone book of six thousand
                        // costs the same as one of six — and capping it at
                        // fifty, alphabetically, meant a full phone book
                        // showed fifty entries beginning with a symbol and
                        // looked for all the world like the app could not
                        // read the rest.
                        itemCount: matches.length,
                        itemBuilder: (_, i) {
                          final c = matches[i];
                          final name = (c.name ?? '').trim();
                          final phone = (c.phone ?? '').trim();
                          return InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            onTap: phone.isEmpty
                                ? null
                                : () => _openThread(phone),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  ContactAvatar(
                                    label: name.isEmpty ? phone : name,
                                    radius: 17,
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
                                            fontSize: 14,
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
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: canSubmit
                            ? AppColors.accent
                            : AppColors.glassSoft,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          onTap: canSubmit
                              ? () => _openThread(_field.text)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            child: Center(
                              child: Text(
                                'Message this number',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: canSubmit
                                      ? AppColors.ink
                                      : AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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

/// The phone book as it comes off the device, made fit to pick from.
///
/// Android hands over one row per *number*, not per person, formatted
/// however it was typed. So one contact with a number saved twice — once
/// with spaces, once without — arrives as two rows that look identical but
/// are not, and a picker shows them both. Dedupe on the normalized number,
/// which is the only thing about a row that identifies who it reaches.
///
/// Rows that cannot receive a message come out: a USSD string like *889#2
/// is a perfectly reasonable thing to save in a phone book and a nonsense
/// thing to offer in a "who do you want to text" list.
///
/// Then sorted so people come before bare numbers, because a phone book
/// sorted by raw display name puts every entry beginning with #, * or + at
/// the top — which is exactly what the first screenful used to be.
List<({String? name, String? phone})> tidyPhoneBook(
  List<({String? name, String? phone})> raw,
) {
  final seen = <String>{};
  final out = <({String? name, String? phone})>[];
  for (final c in raw) {
    final phone = (c.phone ?? '').trim();
    if (phone.isEmpty) continue;
    if (phone.contains('*') || phone.contains('#')) continue;
    final key = normalizePhone(phone) ?? phone.replaceAll(RegExp(r'\D'), '');
    if (key.replaceAll(RegExp(r'\D'), '').length < 6) continue;
    if (!seen.add(key)) continue;
    final name = (c.name ?? '').trim();
    // A name that is only the number again is not a name. Run the name
    // through the same normalizer as the number before comparing: a contact
    // saved as "0911000003" against a number stored as "+251911000003" is the
    // same thing said twice, and comparing raw digits would miss it.
    final nameDigits = name.replaceAll(RegExp(r'\D'), '');
    final keyDigits = key.replaceAll(RegExp(r'\D'), '');
    final nameIsTheNumber =
        nameDigits.isNotEmpty &&
        (nameDigits == keyDigits ||
            (normalizePhone(name) != null && normalizePhone(name) == key) ||
            nameDigits.replaceAll(RegExp(r'^0+'), '') ==
                keyDigits.replaceAll(RegExp(r'^251'), ''));
    out.add((
      name: name.isEmpty || nameIsTheNumber ? null : name,
      phone: phone,
    ));
  }
  out.sort((a, b) {
    final an = a.name, bn = b.name;
    if ((an == null) != (bn == null)) return an == null ? 1 : -1;
    if (an != null && bn != null) {
      return an.toLowerCase().compareTo(bn.toLowerCase());
    }
    return (a.phone ?? '').compareTo(b.phone ?? '');
  });
  return out;
}
