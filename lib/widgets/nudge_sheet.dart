import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

import '../services/friend_service.dart';
import '../services/vibration_service.dart';

/// Encouraging preset notes offered in the nudge sheet. A nudge is a soft tap
/// on the shoulder — never a reminder of what someone missed.
const List<String> kNudgePresets = [
  'Thinking of you today — no pressure, just glad you’re in this with us.',
  'We saved you a seat at the table. Read along whenever you’re ready.',
  'Missed your reflection today. Hope you’re resting well.',
  'Just a gentle wave hello. The Word keeps — and so do we.',
];

/// A person a nudge can be sent to. Kept intentionally lightweight so it works
/// for friends, community entries, and group members alike.
class NudgePerson {
  /// Display name of the person.
  final String name;

  /// Optional profile photo URL.
  final String? photoUrl;

  /// Creates a [NudgePerson].
  const NudgePerson({required this.name, this.photoUrl});

  /// The person's first name, used in warm confirmation copy.
  String get firstName => name.split(' ').first;
}

/// Opens the friendly nudge bottom sheet for [person].
///
/// [onSend] performs the actual send (e.g. `friendService.nudgeFriend`) and
/// returns the [NudgeResult]; the chosen [message] is the sender-side UX note.
Future<void> showNudgeSheet(
  BuildContext context, {
  required NudgePerson person,
  required Future<NudgeResult> Function(String message) onSend,
  VibrationService vibrationService = const VibrationService(),
}) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: AppColors.of(context).scrim,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _NudgeSheet(
      person: person,
      onSend: onSend,
      vibrationService: vibrationService,
    ),
  );
}

class _NudgeSheet extends StatefulWidget {
  const _NudgeSheet({
    required this.person,
    required this.onSend,
    required this.vibrationService,
  });

  final NudgePerson person;
  final Future<NudgeResult> Function(String message) onSend;
  final VibrationService vibrationService;

  @override
  State<_NudgeSheet> createState() => _NudgeSheetState();
}

class _NudgeSheetState extends State<_NudgeSheet> {
  int _choice = 0;
  bool _writing = false;
  bool _sending = false;
  bool _sent = false;
  String? _error;
  final TextEditingController _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _message =>
      _writing ? _custom.text.trim() : kNudgePresets[_choice];

  Future<void> _send() async {
    final message = _message;
    if (message.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    unawaited(widget.vibrationService.lightImpact());
    try {
      final result = await widget.onSend(message);
      if (!mounted) return;
      if (result == NudgeResult.alreadySent) {
        setState(() {
          _sending = false;
          _error = 'You’ve already nudged ${widget.person.firstName} today.';
        });
        return;
      }
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Couldn’t send your nudge. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20,
            color: colorScheme.shadow.withValues(alpha: 0.16),
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_sent) _buildConfirmation(theme) else _buildComposer(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmation(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
          ),
          child: Icon(
            Icons.waving_hand_outlined,
            size: 28,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Nudge sent to ${widget.person.firstName}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A gentle note just landed. No pressure on them — or you.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final canSend = _message.isNotEmpty && !_sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Avatar(person: widget.person, size: 46),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nudge ${widget.person.firstName}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Send an encouraging hello',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_outline,
                  size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A nudge is a soft tap on the shoulder — never a reminder of '
                  'what they missed.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_writing) _buildCustomField(theme) else _buildPresets(theme),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style:
                theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: canSend ? _send : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.waving_hand_outlined, size: 18),
            label: Text(_sending ? 'Sending…' : 'Send nudge'),
          ),
        ),
      ],
    );
  }

  Widget _buildPresets(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < kNudgePresets.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PresetTile(
              text: kNudgePresets[i],
              selected: _choice == i,
              onTap: () => setState(() => _choice = i),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            alignment: Alignment.centerLeft,
            side: BorderSide(
              color: colorScheme.outlineVariant,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => setState(() => _writing = true),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Write your own'),
        ),
      ],
    );
  }

  Widget _buildCustomField(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _custom,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Say something kind…',
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() {
            _writing = false;
            _custom.clear();
          }),
          icon: const Icon(Icons.chevron_left, size: 18),
          label: const Text('Back to notes'),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).primarySoft
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.of(context).primaryLine
                : AppColors.of(context).border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person, required this.size});

  final NudgePerson person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: ClipOval(
        child: person.photoUrl != null
            ? CachedNetworkImage(
                imageUrl: person.photoUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Icon(Icons.person),
                errorWidget: (context, url, error) => const Icon(Icons.person),
              )
            : Icon(Icons.person, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
