import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'common_styles.dart';

/// Gentle reflection prompts — rotate day to day, never demanding.
const List<String> kReflectionPrompts = [
  'What stayed with you?',
  'Where did this meet you today?',
  'One line — what is God saying?',
];

/// Picks the day's rotating prompt deterministically from [date], so it's
/// stable within a day but cycles from day to day.
String reflectionPromptFor(DateTime date) {
  final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
  return kReflectionPrompts[dayOfYear % kReflectionPrompts.length];
}

/// Opens the reflection editor sheet. [initialText] pre-fills the field when
/// editing an existing reflection; pass `null` for a fresh entry. [onSave] is
/// called with the trimmed text and should persist it; the sheet closes once
/// it resolves. [onSkip] fires if the user skips/dismisses without saving —
/// either way the daily habit mark this sheet is opened from is untouched.
Future<void> showReflectSheet(
  BuildContext context, {
  required String? initialText,
  required String prompt,
  required Future<void> Function(String text) onSave,
  VoidCallback? onSkip,
}) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: AppColors.of(context).scrim,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ReflectSheet(
      initialText: initialText,
      prompt: prompt,
      onSave: onSave,
      onSkip: onSkip,
    ),
  );
}

class _ReflectSheet extends StatefulWidget {
  const _ReflectSheet({
    required this.initialText,
    required this.prompt,
    required this.onSave,
    required this.onSkip,
  });

  final String? initialText;
  final String prompt;
  final Future<void> Function(String text) onSave;
  final VoidCallback? onSkip;

  @override
  State<_ReflectSheet> createState() => _ReflectSheetState();
}

class _ReflectSheetState extends State<_ReflectSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  bool _saving = false;

  bool get _isEditing => (widget.initialText ?? '').isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _controller.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text.trim());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _skip() {
    widget.onSkip?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canSave = _controller.text.trim().isNotEmpty && !_saving;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.rSheet),
        ),
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
              Text(
                'REFLECTION',
                style: AppTextStyles.caption(context).copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.prompt,
                style: AppTextStyles.title(context).copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: !_isEditing,
                minLines: 4,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'A sentence is plenty…',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rField),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rField),
                    borderSide: BorderSide(color: colorScheme.outlineVariant),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: canSave ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : _skip,
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(_isEditing ? 'Cancel' : 'Skip for today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
