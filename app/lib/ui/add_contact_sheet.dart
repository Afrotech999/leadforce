import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/phone.dart';
import '../state/providers.dart';
import '../theme.dart';
import 'common.dart';

/// One customer, added by hand.
///
/// Importing a spreadsheet is the way six thousand contacts get in. It is a
/// terrible way to add the one person standing in front of you, which is what
/// this is for: a name, a number, and it joins the next batch with room in it.
Future<void> showAddContactSheet(
  BuildContext context, {
  int? toBatchId,
  String? batchName,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _AddContactSheet(toBatchId: toBatchId, batchName: batchName),
);

class _AddContactSheet extends ConsumerStatefulWidget {
  const _AddContactSheet({this.toBatchId, this.batchName});

  /// When set, the new contact goes into exactly this batch — the sheet was
  /// opened from inside it, and "add" should mean "add here".
  final int? toBatchId;
  final String? batchName;

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _phoneFocus = FocusNode();
  bool _saving = false;
  String? _error;

  /// The last few added without leaving the sheet — a queue at the counter is
  /// several people, not one, and closing between each would be tedious.
  final _added = <String>[];

  @override
  void initState() {
    super.initState();
    _phone.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final result = await ref
        .read(repoProvider)
        .addContact(
          rawPhone: _phone.text,
          name: _name.text,
          toBatchId: widget.toBatchId,
        );
    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _saving = false;
        _error = result.message;
      });
      return;
    }

    bumpRefresh(ref);
    setState(() {
      _saving = false;
      _added.insert(
        0,
        '${_name.text.trim().isEmpty ? localForm(normalizePhone(_phone.text)!) : _name.text.trim()} → ${result.batchName}',
      );
      _name.clear();
      _phone.clear();
    });
    _phoneFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // The keyboard is up the whole time this sheet is open; without the inset
    // the number field sits underneath it.
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
                      margin: const EdgeInsets.only(top: 10, bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      widget.batchName == null
                          ? 'Add a contact'
                          : 'Add to ${widget.batchName}',
                      style: const TextStyle(
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
                    child: Column(
                      children: [
                        _Field(
                          controller: _name,
                          hint: 'Name (optional)',
                          icon: LucideIcons.user,
                          capitalize: true,
                          onSubmitted: (_) => _phoneFocus.requestFocus(),
                        ),
                        const SizedBox(height: 8),
                        _Field(
                          controller: _phone,
                          focusNode: _phoneFocus,
                          hint: '09… or +2519…',
                          icon: LucideIcons.phone,
                          phone: true,
                          onSubmitted: (_) => _save(),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  if (_added.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in _added.take(3))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(
                                    LucideIcons.check,
                                    size: 14,
                                    color: AppColors.inkMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      line,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              onTap: _saving ? null : _save,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                child: Center(
                                  child: Text(
                                    _saving ? 'Adding…' : 'Add to a batch',
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
                        const SizedBox(width: 10),
                        Material(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            onTap: () {
                              if (_added.isNotEmpty) {
                                showSnack(
                                  context,
                                  _added.length == 1
                                      ? '1 contact added.'
                                      : '${_added.length} contacts added.',
                                );
                              }
                              Navigator.of(context).pop();
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 15,
                              ),
                              child: Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.phone = false,
    this.capitalize = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;
  final bool phone;
  final bool capitalize;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.glass,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      border: Border.all(color: AppColors.glassEdge),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: !phone,
            keyboardType: phone ? TextInputType.phone : TextInputType.name,
            textCapitalization: capitalize
                ? TextCapitalization.words
                : TextCapitalization.none,
            textInputAction: phone
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: onSubmitted,
            inputFormatters: phone
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))]
                : null,
            style: const TextStyle(fontSize: 15, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: hint,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              hintStyle: const TextStyle(
                fontSize: 15,
                color: AppColors.inkMuted,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
