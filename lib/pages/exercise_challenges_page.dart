import 'dart:async';

import 'package:flutter/material.dart';

import '../models/exercise_challenge.dart';
import '../services/error_logger.dart';
import '../services/exercise_tracker_service.dart';
import '../services/vibration_service.dart';
import '../widgets/common_styles.dart';

class ExerciseChallengesPage extends StatefulWidget {
  ExerciseChallengesPage({
    super.key,
    ExerciseTrackerService? trackerService,
    VibrationService? vibrationService,
  })  : trackerService = trackerService ?? ExerciseTrackerService(),
        vibrationService = vibrationService ?? const VibrationService();

  final ExerciseTrackerService trackerService;
  final VibrationService vibrationService;

  @override
  State<ExerciseChallengesPage> createState() => _ExerciseChallengesPageState();
}

class _ExerciseChallengesPageState extends State<ExerciseChallengesPage> {
  bool _loading = true;
  bool _disposed = false;
  String? _error;
  List<ExerciseChallengeSummary> _summaries = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = widget.trackerService.auth.currentUser;
    if (user == null) {
      if (!_disposed && mounted) {
        setState(() {
          _summaries = const [];
          _error = 'Please sign in to manage exercise challenges.';
          _loading = false;
        });
      }
      return;
    }

    if (!_disposed && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final summaries = await widget.trackerService.fetchChallengeSummaries(
        uid: user.uid,
        recentDays: 60,
      );
      if (!_disposed && mounted) {
        setState(() {
          _summaries = summaries;
        });
      }
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        setState(() {
          _error = 'Failed to load exercise challenges.';
        });
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createChallenge() async {
    await _showChallengeForm();
  }

  Future<void> _editChallenge(ExerciseChallenge challenge) async {
    await _showChallengeForm(initial: challenge);
  }

  Future<void> _showChallengeForm({ExerciseChallenge? initial}) async {
    final uid = initial?.uid.isNotEmpty == true
        ? initial!.uid
        : widget.trackerService.auth.currentUser?.uid ?? '';
    final result = await showModalBottomSheet<ExerciseChallenge>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ExerciseChallengeForm(
          initial: initial,
          defaultUid: uid,
        );
      },
    );
    if (result == null) {
      return;
    }

    try {
      await widget.trackerService.upsertChallenge(result);
      if (!_disposed && mounted) {
        unawaited(widget.vibrationService.mediumImpact());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                initial == null ? 'Challenge created.' : 'Challenge updated.',
              ),
            ),
          );
      }
      await _loadData();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Failed to save challenge. Please try again.'),
            ),
          );
      }
    }
  }

  Future<void> _archiveChallenge(ExerciseChallenge challenge) async {
    try {
      await widget.trackerService.upsertChallenge(
        challenge.copyWith(archived: true),
      );
      if (!_disposed && mounted) {
        unawaited(widget.vibrationService.lightImpact());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('${challenge.name} archived.')),
          );
      }
      await _loadData();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Failed to archive challenge. Please try again.'),
            ),
          );
      }
    }
  }

  Future<void> _deleteChallenge(ExerciseChallenge challenge) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete challenge?'),
              content: Text(
                'This will permanently remove ${challenge.name}. '
                'This action cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    try {
      await widget.trackerService.deleteChallenge(challenge);
      if (!_disposed && mounted) {
        unawaited(widget.vibrationService.lightImpact());
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('${challenge.name} deleted.')),
          );
      }
      await _loadData();
    } catch (e, st) {
      await ErrorLogger.log(e, st);
      if (!_disposed && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Failed to delete challenge. Please try again.'),
            ),
          );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.trackerService.auth.currentUser;
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Exercise Challenges'),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => unawaited(_createChallenge()),
              icon: const Icon(Icons.add),
              label: const Text('Add challenge'),
            ),
      body: Container(
        decoration:
            CommonStyles.backgroundDecoration(Theme.of(context).colorScheme),
        child: user == null
            ? const Center(
                child: Text('Please sign in to manage exercise challenges.'),
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                child: _buildList(context),
              ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final children = <Widget>[
      CommonStyles.buildCard(
        context: context,
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For bodily exercise is profitable for a little, but godliness is'
              ' profitable for all things, having promise of the present life'
              ' and of that which is to come.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '1 Timothy 4:8',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    ];

    void addSpacing() {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 16));
      }
    }

    if (_loading) {
      addSpacing();
      children.add(
        CommonStyles.buildCard(
          context: context,
          margin: EdgeInsets.zero,
          child: const Center(
            child: SizedBox(
              height: 32,
              width: 32,
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    } else if (_error != null) {
      addSpacing();
      children.add(
        CommonStyles.buildCard(
          context: context,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(_loadData()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    } else if (_summaries.isEmpty) {
      addSpacing();
      children.add(
        CommonStyles.buildCard(
          context: context,
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No exercise challenges yet.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create your first challenge to track daily activity goals.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(_createChallenge()),
                icon: const Icon(Icons.add),
                label: const Text('Create challenge'),
              ),
            ],
          ),
        ),
      );
    } else {
      addSpacing();
      for (var i = 0; i < _summaries.length; i++) {
        final summary = _summaries[i];
        children.add(
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _summaries.length - 1 ? 0 : 16,
            ),
            child: _ChallengeCard(
              summary: summary,
              onEdit: () => unawaited(_editChallenge(summary.challenge)),
              onArchive: () => unawaited(_archiveChallenge(summary.challenge)),
              onDelete: () => unawaited(_deleteChallenge(summary.challenge)),
            ),
          ),
        );
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.summary,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  final ExerciseChallengeSummary summary;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  ExerciseChallenge get challenge => summary.challenge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goalDescription = _goalLabel();
    final totalTarget = challenge.totalTarget;
    final entries = summary.recentTotals.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    final history = entries.take(7).toList();
    final localizations = MaterialLocalizations.of(context);

    return CommonStyles.buildCard(
      context: context,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.name, style: theme.textTheme.titleMedium),
                    if (goalDescription != null) ...[
                      const SizedBox(height: 4),
                      Text(goalDescription, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              Chip(
                label: Text(
                  summary.goalMetToday ? 'Goal met today' : 'In progress',
                ),
                backgroundColor: summary.goalMetToday
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text(
                'Today: ${_formatAmount(summary.todayTotal)} ${challenge.unit}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                'Streak: ${summary.currentStreak} days',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (totalTarget != null) ...[
            Text(
              'Lifetime: ${_formatAmount(summary.totalRecorded)} / '
              '${_formatAmount(totalTarget)} ${challenge.unit}',
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            Text(
              'Lifetime total: ${_formatAmount(summary.totalRecorded)} ${challenge.unit}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: theme.dividerColor.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Recent history',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text(
              'No recent entries recorded.',
              style: theme.textTheme.bodySmall,
            )
          else
            Column(
              children: history.map((entry) {
                final date = DateTime.tryParse(entry.key);
                final dateLabel = date != null
                    ? localizations.formatMediumDate(date)
                    : entry.key;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dateLabel),
                      Text('${_formatAmount(entry.value)} ${challenge.unit}'),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
              TextButton.icon(
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
              ),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _goalLabel() {
    if (challenge.dailyGoal <= 0) {
      return null;
    }
    final amount = _formatAmount(challenge.dailyGoal);
    final unit = challenge.unit.isEmpty ? '' : ' ${challenge.unit}';
    switch (challenge.targetType) {
      case ExerciseTargetType.atLeast:
        return 'Goal: at least $amount$unit per day';
      case ExerciseTargetType.atMost:
        return 'Goal: at most $amount$unit per day';
      case ExerciseTargetType.exactly:
        return 'Goal: exactly $amount$unit per day';
    }
  }

  static String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed
        .replaceFirst(RegExp(r'\.0+\$'), '')
        .replaceFirst(RegExp(r'(\.\d*?[1-9])0+\$'), r'\1');
    return trimmed.isEmpty ? '0' : trimmed;
  }
}

class _ExerciseChallengeForm extends StatefulWidget {
  const _ExerciseChallengeForm({
    this.initial,
    required this.defaultUid,
  });

  final ExerciseChallenge? initial;
  final String defaultUid;

  @override
  State<_ExerciseChallengeForm> createState() => _ExerciseChallengeFormState();
}

class _ExerciseChallengeFormState extends State<_ExerciseChallengeForm> {
  static const List<String> _unitOptions = <String>[
    'reps',
    'minutes',
    'hours',
    'kilometers',
    'miles',
    'steps',
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dailyGoalController;
  late final TextEditingController _totalTargetController;
  late final TextEditingController _customUnitController;
  late ExerciseTargetType _targetType;
  late bool _useCustomUnit;
  String? _selectedUnit;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _dailyGoalController = TextEditingController(
      text: initial == null ? '' : _formatNumber(initial.dailyGoal),
    );
    _totalTargetController = TextEditingController(
      text: initial?.totalTarget == null
          ? ''
          : _formatNumber(initial!.totalTarget!),
    );
    _targetType = initial?.targetType ?? ExerciseTargetType.atLeast;
    final unit = initial?.unit ?? '';
    _useCustomUnit = unit.isNotEmpty && !_unitOptions.contains(unit);
    _selectedUnit =
        _useCustomUnit ? 'custom' : (unit.isEmpty ? _unitOptions.first : unit);
    _customUnitController = TextEditingController(
      text: _useCustomUnit ? unit : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dailyGoalController.dispose();
    _totalTargetController.dispose();
    _customUnitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initial != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 20,
            color: Colors.black26,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEditing ? 'Edit challenge' : 'New challenge',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Challenge name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a challenge name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _useCustomUnit ? 'custom' : _selectedUnit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                  items: [
                    for (final option in _unitOptions)
                      DropdownMenuItem<String>(
                        value: option,
                        child: Text(option),
                      ),
                    const DropdownMenuItem<String>(
                      value: 'custom',
                      child: Text('Custom unit'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      if (value == 'custom') {
                        _useCustomUnit = true;
                        _selectedUnit = _unitOptions.first;
                      } else {
                        _useCustomUnit = false;
                        _selectedUnit = value;
                      }
                    });
                  },
                ),
                if (_useCustomUnit) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _customUnitController,
                    decoration: const InputDecoration(
                      labelText: 'Custom unit',
                    ),
                    validator: (value) {
                      if (!_useCustomUnit) {
                        return null;
                      }
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter a unit';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<ExerciseTargetType>(
                  initialValue: _targetType,
                  decoration:
                      const InputDecoration(labelText: 'Daily target type'),
                  items: ExerciseTargetType.values
                      .map(
                        (type) => DropdownMenuItem<ExerciseTargetType>(
                          value: type,
                          child: Text(_targetLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _targetType = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _dailyGoalController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Daily goal',
                    helperText:
                        'Use decimals for partial units (e.g., 0.5 hours)',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter a daily goal';
                    }
                    final parsed = double.tryParse(text);
                    if (parsed == null) {
                      return 'Enter a valid number';
                    }
                    if (parsed < 0) {
                      return 'Daily goal must be positive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _totalTargetController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Total target (optional)',
                    helperText:
                        'Leave blank to track lifetime totals without a cap',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return null;
                    }
                    final parsed = double.tryParse(text);
                    if (parsed == null) {
                      return 'Enter a valid number';
                    }
                    if (parsed <= 0) {
                      return 'Total target must be positive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _submit,
                      child: Text(isEditing ? 'Save changes' : 'Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final unit = _useCustomUnit
        ? _customUnitController.text.trim()
        : (_selectedUnit ?? _unitOptions.first);
    final dailyText = _dailyGoalController.text.trim();
    final totalText = _totalTargetController.text.trim();
    final dailyGoal = double.parse(dailyText);
    final double? totalTarget =
        totalText.isEmpty ? null : double.parse(totalText);

    final initial = widget.initial;
    final challenge = ExerciseChallenge(
      id: initial?.id ?? '',
      uid:
          (initial?.uid.isNotEmpty ?? false) ? initial!.uid : widget.defaultUid,
      name: _nameController.text.trim(),
      unit: unit,
      dailyGoal: dailyGoal,
      targetType: _targetType,
      totalTarget: totalTarget,
      categories: initial?.categories ?? const <String>[],
      archived: initial?.archived ?? false,
      createdAt: initial?.createdAt,
      updatedAt: initial?.updatedAt,
    );

    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(challenge);
  }

  String _formatNumber(double value) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed
        .replaceFirst(RegExp(r'\.0+\$'), '')
        .replaceFirst(RegExp(r'(\.\d*?[1-9])0+\$'), r'\1');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  String _targetLabel(ExerciseTargetType type) {
    switch (type) {
      case ExerciseTargetType.atLeast:
        return 'At least';
      case ExerciseTargetType.atMost:
        return 'At most';
      case ExerciseTargetType.exactly:
        return 'Exactly';
    }
  }
}
