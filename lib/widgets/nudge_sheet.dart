import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_bottom_sheet.dart';

import '../services/nudge_service.dart';
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
/// for Circle members anywhere in the app.
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
/// [onSend] performs the actual send (e.g. `nudgeService.nudgeMember`) and
/// returns the [NudgeResult]; the chosen [message] is the sender-side UX note.
Future<void> showNudgeSheet(
  BuildContext context, {
  required NudgePerson person,
  required Future<NudgeResult> Function(String message) onSend,
  VibrationService vibrationService = const VibrationService(),
}) {
  return showAppSheet<void>(
    context: context,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gap20, AppSpacing.gap16,
          AppSpacing.gap20, AppSpacing.gap24),
      child: _sent ? _buildConfirmation(theme) : _buildComposer(theme),
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
        const SizedBox(height: AppSpacing.gap12),
        Text(
          'Nudge sent to ${widget.person.firstName}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.gap8),
        Text(
          'A gentle note just landed. No pressure on them — or you.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.gap20),
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
            const SizedBox(width: AppSpacing.gap12),
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
        const SizedBox(height: AppSpacing.gap16),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.gap12, vertical: AppSpacing.gap12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.rChip),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.favorite_outline,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.gap8),
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
        const SizedBox(height: AppSpacing.gap12),
        if (_writing) _buildCustomField(theme) else _buildPresets(theme),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.gap12),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.gap20),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: canSend ? _send : null,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
// token-exempt: button submitting
                      strokeWidth: 2,
                    ),
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
            padding: const EdgeInsets.only(bottom: AppSpacing.gap8),
            child: _PresetTile(
              text: kNudgePresets[i],
              selected: _choice == i,
              onTap: () => setState(() => _choice = i),
            ),
          ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            // token-exempt: left-aligned list-row action; layout only
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.gap12, horizontal: AppSpacing.gap12),
            alignment: Alignment.centerLeft,
            side: BorderSide(
              color: colorScheme.outlineVariant,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.rInset),
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
          ),
        ),
        const SizedBox(height: AppSpacing.gap8),
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
      borderRadius: BorderRadius.circular(AppSpacing.rInset),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.gap12, vertical: AppSpacing.gap12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.of(context).primarySoft
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.rInset),
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
            const SizedBox(width: AppSpacing.gap12),
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
        border: Border.all(color: colorScheme.outlineVariant),
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
