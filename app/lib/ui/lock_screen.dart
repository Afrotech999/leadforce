import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/applock.dart';
import '../state/providers.dart';
import '../theme.dart';

/// The keypad in front of the app.
///
/// Its own screen rather than a dialog: a dialog can be dismissed, and half of
/// the point of this is that it cannot. Nothing of the app is drawn behind it,
/// so a name or a number cannot be read off the page underneath.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String _entered = '';
  String? _error;
  Duration _wait = Duration.zero;
  Timer? _ticker;

  /// How long the code is, so a guess is checked once — when it is complete —
  /// rather than after every digit.
  int _length = 4;

  @override
  void initState() {
    super.initState();
    _readCooldown();
    _readLength();
  }

  Future<void> _readLength() async {
    final n = await ref.read(repoProvider).lockLength();
    if (mounted) setState(() => _length = n);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The wait outlives the process, so it is read from the database on open
  /// and counted down against the clock rather than trusted to a timer.
  Future<void> _readCooldown() async {
    final left = await ref.read(repoProvider).lockCooldownLeft();
    if (!mounted) return;
    setState(() => _wait = left);
    _ticker?.cancel();
    if (left > Duration.zero) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (t) async {
        final now = await ref.read(repoProvider).lockCooldownLeft();
        if (!mounted) return t.cancel();
        setState(() => _wait = now);
        if (now <= Duration.zero) t.cancel();
      });
    }
  }

  Future<void> _press(String digit) async {
    if (_wait > Duration.zero || _entered.length >= _length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _error = null;
    });
    if (_entered.length == _length) await _submit();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = null;
    });
  }

  /// One guess, checked once. Called when the last digit lands, or from the
  /// arrow key for anyone who prefers to press it.
  Future<void> _submit() async {
    if (_wait > Duration.zero || _entered.length < 4) return;
    if (await ref.read(repoProvider).checkLockPin(_entered)) {
      HapticFeedback.mediumImpact();
      widget.onUnlocked();
      return;
    }
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    setState(() {
      _entered = '';
      _error = 'That is not the code.';
    });
    await _readCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _wait > Duration.zero;

    return PopScope(
      // Back must not be a way past the lock.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.lock,
                  size: 26,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'LeadForce is locked',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  waiting
                      ? 'Too many wrong codes. Try again in ${_wait.inSeconds}s.'
                      : _error ?? 'Enter your code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _error == null && !waiting
                        ? AppColors.inkMuted
                        : AppColors.danger,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _entered.length
                              ? AppColors.ink
                              : Colors.transparent,
                          border: Border.all(
                            color: i < _entered.length
                                ? AppColors.ink
                                : AppColors.muted,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(flex: 2),
              _Keypad(
                enabled: !waiting,
                onDigit: _press,
                onBackspace: _backspace,
                onSubmit: _submit,
                canSubmit: _entered.length >= 4 && _entered.length <= _length,
              ),
              const SizedBox(height: 10),
              // No "forgot my code" that lets anyone past — there is no server
              // to prove anything to. Saying so plainly beats a dead end.
              const Padding(
                padding: EdgeInsets.fromLTRB(34, 0, 34, 10),
                child: Text(
                  'Forgotten it? Nobody can unlock this for you. Reinstall the '
                  'app and restore your last backup.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The three-by-four grid. Big targets: this gets tapped one-handed, often in
/// a car, sometimes in the sun.
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    required this.onSubmit,
    required this.canSubmit,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onSubmit;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Semantics(
          label: icon == null
              ? label
              : (icon == LucideIcons.delete ? 'Delete' : 'Unlock'),
          button: true,
          child: Material(
            color: icon == null ? AppColors.cardHigh : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? (onTap ?? () => onDigit(label)) : null,
              child: SizedBox(
                height: 66,
                child: Center(
                  child: icon != null
                      ? Icon(
                          icon,
                          size: 23,
                          color: enabled ? AppColors.inkMuted : AppColors.muted,
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w500,
                            color: enabled ? AppColors.ink : AppColors.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 38),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(children: [for (final d in row) key(d)]),
          Row(
            children: [
              key('', onTap: onBackspace, icon: LucideIcons.delete),
              key('0'),
              key(
                '',
                onTap: canSubmit ? onSubmit : null,
                icon: LucideIcons.arrowRight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Setting, changing or removing the code.
///
/// One screen for all three so the rules — twice to confirm, current code to
/// change or remove — live in one place rather than three dialogs.
class LockSetupScreen extends ConsumerStatefulWidget {
  const LockSetupScreen({super.key, required this.alreadySet});

  /// Whether a code exists. Decides whether this asks for the current one
  /// first, and whether "Turn off" is offered at all.
  final bool alreadySet;

  @override
  ConsumerState<LockSetupScreen> createState() => _LockSetupScreenState();
}

class _LockSetupScreenState extends ConsumerState<LockSetupScreen> {
  final _current = TextEditingController();
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(repoProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.alreadySet && !await repo.checkLockPin(_current.text)) {
        setState(() => _error = 'That is not your current code.');
        return;
      }
      if (!AppLock.looksValid(_first.text)) {
        setState(() => _error = 'A code is four to eight digits.');
        return;
      }
      if (_first.text.trim() != _second.text.trim()) {
        setState(() => _error = 'The two codes are different.');
        return;
      }
      await repo.setLockPin(_first.text.trim());
      bumpRefresh(ref);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final repo = ref.read(repoProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await repo.clearLockPin(_current.text)) {
        setState(() => _error = 'That is not your current code.');
        return;
      }
      bumpRefresh(ref);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.alreadySet ? 'Change your code' : 'Set a code'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        const Text(
          'A code in front of the app, for when the phone is handed to '
          'somebody. Your messages, your people and your notes stay behind it.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 18),
        if (widget.alreadySet) ...[
          _PinField(controller: _current, label: 'Your current code'),
          const SizedBox(height: 12),
        ],
        _PinField(
          controller: _first,
          label: widget.alreadySet ? 'New code' : 'Code',
        ),
        const SizedBox(height: 12),
        _PinField(controller: _second, label: 'The same code again'),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            style: const TextStyle(fontSize: 13, color: AppColors.danger),
          ),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.alreadySet ? 'Change it' : 'Turn the lock on'),
        ),
        if (widget.alreadySet) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy ? null : _remove,
            child: const Text('Turn the lock off'),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Nobody can reset this for you — there is no account and no server. '
          'If you forget it, the only way back in is to reinstall the app and '
          'restore a backup, so take one now if you have not.',
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: AppColors.inkMuted,
          ),
        ),
      ],
    ),
  );
}

class _PinField extends StatelessWidget {
  const _PinField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    obscureText: true,
    maxLength: 8,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: const TextStyle(fontSize: 17, letterSpacing: 4),
    decoration: InputDecoration(labelText: label, counterText: ''),
  );
}
