import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/read_through.dart';
import '../services/error_logger.dart';
import '../services/read_through_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sub_header.dart';

/// Records a read-through the user finished before or outside the app, and
/// edits the human-supplied parts of one already recorded.
///
/// People remember "2011" far more often than a date, so the form asks how
/// precisely they remember rather than forcing a day they would have to invent.
class AddReadThroughPage extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  /// When given, the page edits this record instead of adding a new one.
  final ReadThrough? existing;

  final ReadThroughService? service;

  const AddReadThroughPage({
    super.key,
    required this.firestore,
    required this.auth,
    this.existing,
    this.service,
  });

  @override
  State<AddReadThroughPage> createState() => _AddReadThroughPageState();
}

class _AddReadThroughPageState extends State<AddReadThroughPage> {
  late final ReadThroughService _service;
  late final TextEditingController _location;

  ReadThroughScope _scope = ReadThroughScope.wholeBible;
  DatePrecision _precision = DatePrecision.year;
  late DateTime _completedAt;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ReadThroughService(firestore: widget.firestore);
    final existing = widget.existing;
    _completedAt = existing?.completedAt ?? DateTime.now();
    _precision = existing?.datePrecision ?? DatePrecision.year;
    _scope = existing?.scope ?? ReadThroughScope.wholeBible;
    _location = TextEditingController(text: existing?.location ?? '');
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _completedAt.isAfter(now) ? now : _completedAt,
      firstDate: DateTime(1930),
      lastDate: now,
      helpText: switch (_precision) {
        DatePrecision.year => 'Pick any day in that year',
        DatePrecision.month => 'Pick any day in that month',
        DatePrecision.day => 'When did you finish?',
      },
    );
    if (picked != null) setState(() => _completedAt = picked);
  }

  Future<void> _save() async {
    final user = widget.auth.currentUser;
    if (user == null || _saving) return;
    setState(() => _saving = true);

    final location = _location.text.trim();
    try {
      if (_isEditing) {
        await _service.updateDetails(
          user.uid,
          widget.existing!.id,
          completedAt: _completedAt,
          datePrecision: _precision,
          location: location,
        );
      } else {
        await _service.addBackfilled(
          uid: user.uid,
          scope: _scope,
          completedAt: _completedAt,
          precision: _precision,
          location: location,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save that. Please try again.")),
      );
    }
  }

  Future<void> _delete() async {
    final user = widget.auth.currentUser;
    final existing = widget.existing;
    if (user == null || existing == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.of(context).scrim,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Remove this read-through?'),
        content: Text(
          'This removes ${existing.scope.label.toLowerCase()} '
          '(${existing.dateLabel}) from your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.delete(user.uid, existing.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, st) {
      ErrorLogger.log(e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't remove that. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final existing = widget.existing;
    final canDelete = existing != null && existing.source.isDeletable;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            SubHeader(
              title: _isEditing ? 'Edit read-through' : 'A past read-through',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  if (!_isEditing) ...[
                    const _FieldLabel('What did you finish?'),
                    const SizedBox(height: 10),
                    for (final scope in ReadThroughScope.values) ...[
                      _ScopeOption(
                        scope: scope,
                        selected: _scope == scope,
                        onTap: () => setState(() => _scope = scope),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 18),
                  ],
                  const _FieldLabel('When did you finish?'),
                  const SizedBox(height: 10),
                  _PrecisionTabs(
                    value: _precision,
                    onChanged: (p) => setState(() => _precision = p),
                  ),
                  const SizedBox(height: 10),
                  _FieldBox(
                    icon: Icons.calendar_today_rounded,
                    onTap: _pickDate,
                    child: Text(
                      ReadThrough(
                        id: '',
                        scope: _scope,
                        completedAt: _completedAt,
                        datePrecision: _precision,
                        source: ReadThroughSource.backfilled,
                      ).dateLabel,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Hint(switch (_precision) {
                    DatePrecision.year =>
                      'Only remember the year? That is enough.',
                    DatePrecision.month =>
                      'Narrow it down if you remember the season.',
                    DatePrecision.day =>
                      'Pick the day you read the last chapter.',
                  }),
                  const SizedBox(height: 26),
                  const _FieldLabel('Where were you? — optional'),
                  const SizedBox(height: 10),
                  _FieldBox(
                    icon: Icons.place_outlined,
                    child: TextField(
                      controller: _location,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.sentences,
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        counterText: '',
                        hintText: 'Fuller, Pasadena',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _Hint(
                    "A city, a church, a season of life — whatever you'll "
                    'recognise later.',
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 26),
                    const _PrivacyNote(),
                  ],
                  if (canDelete) ...[
                    const SizedBox(height: 26),
                    Center(
                      child: TextButton(
                        onPressed: _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.error,
                        ),
                        child: const Text('Remove from my history'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    _isEditing ? 'Save changes' : 'Add to my history',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall);
}

class _FieldBox extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  const _FieldBox({required this.icon, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final box = Container(
      height: AppSpacing.buttonHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.rField),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 11),
          Expanded(child: child),
        ],
      ),
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.rField),
      child: box,
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final ReadThroughScope scope;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.rField),
        child: Container(
          height: AppSpacing.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected
                ? appColors.primarySoft
                : colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.rField),
            border: Border.all(
              color: selected ? appColors.primaryLine : appColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(
                scope.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? appColors.primaryPress
                          : colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrecisionTabs extends StatelessWidget {
  final DatePrecision value;
  final ValueChanged<DatePrecision> onChanged;

  const _PrecisionTabs({required this.value, required this.onChanged});

  static const _labels = {
    DatePrecision.year: 'Just the year',
    DatePrecision.month: 'Month & year',
    DatePrecision.day: 'Exact date',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.of(context).bg2,
        borderRadius: BorderRadius.circular(AppSpacing.rField),
      ),
      child: Row(
        children: [
          for (final entry in _labels.entries)
            Expanded(
              child: Semantics(
                selected: value == entry.key,
                button: true,
                child: InkWell(
                  onTap: () => onChanged(entry.key),
                  borderRadius: BorderRadius.circular(AppSpacing.rChip),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == entry.key
                          ? colorScheme.surfaceContainerLowest
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.rChip),
                    ),
                    child: Text(
                      entry.value,
                      style:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: value == entry.key
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Says plainly that hand-entered records never reach the feed.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 19,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Past read-throughs stay yours. They are added to your history, '
              'but never posted to the feed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
