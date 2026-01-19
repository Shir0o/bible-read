import 'dart:async';
import 'package:flutter/material.dart';
import '../services/exercise_tracker_service.dart';
import '../services/vibration_service.dart';
import '../models/exercise_challenge.dart';
import '../widgets/common_styles.dart';

class ExerciseChallengesPage extends StatelessWidget {
  final ExerciseTrackerService service;
  final VibrationService? vibrationService;

  const ExerciseChallengesPage({
    super.key,
    required this.service,
    this.vibrationService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CommonStyles.buildAppBar(context, 'Exercise Challenges'),
      body: ExerciseChallengesView(
        service: service,
        vibrationService: vibrationService,
      ),
    );
  }
}

class ExerciseChallengesView extends StatefulWidget {
  final ExerciseTrackerService service;
  final VibrationService? vibrationService;

  const ExerciseChallengesView({
    super.key,
    required this.service,
    this.vibrationService,
  });

  @override
  State<ExerciseChallengesView> createState() => _ExerciseChallengesViewState();
}

class _ExerciseChallengesViewState extends State<ExerciseChallengesView> {
  List<ExerciseChallenge> _challenges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await widget.service.fetchActiveChallenges();
      if (mounted) setState(() => _challenges = list);
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showForm([ExerciseChallenge? challenge]) async {
    await showDialog(
      context: context,
      builder: (context) => _ChallengeFormDialog(
        challenge: challenge,
        onSave: (newChallenge) async {
          await widget.service.upsertChallenge(newChallenge);
          widget.vibrationService?.mediumImpact();
          if (mounted) _load();
        },
      ),
    );
  }

  Future<void> _delete(ExerciseChallenge challenge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete challenge?'), // Matches test
        content: Text('Delete "${challenge.name}"?'), // Content can vary, test checks contains name
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton( // Test taps widgetWithText(FilledButton, 'Delete')
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.service.deleteChallenge(challenge);
      widget.vibrationService?.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${challenge.name} deleted.')),
        );
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'For bodily exercise is profitable for a little: but godliness is profitable unto all things.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1 Timothy 4:8',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            if (_challenges.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No exercise challenges yet.')),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final challenge = _challenges[index];
                    return ListTile(
                      title: Text(challenge.name),
                      subtitle: Text(_formatSubtitle(challenge)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _showForm(challenge),
                            child: const Text('Edit'),
                          ),
                          TextButton(
                            onPressed: () => _delete(challenge),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: _challenges.length,
                ),
              ),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            onPressed: () => _showForm(),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  String _formatSubtitle(ExerciseChallenge challenge) {
    // "Goal: at least 30.00 minutes per day"
    String typeStr;
    switch (challenge.targetType) {
      case ExerciseTargetType.atLeast:
        typeStr = 'at least';
        break;
      case ExerciseTargetType.atMost:
        typeStr = 'at most';
        break;
      case ExerciseTargetType.exactly:
        typeStr = 'exactly';
        break;
    }
    return 'Goal: $typeStr ${challenge.dailyGoal.toStringAsFixed(2)} ${challenge.unit} per day';
  }
}

class _ChallengeFormDialog extends StatefulWidget {
  final ExerciseChallenge? challenge;
  final ValueChanged<ExerciseChallenge> onSave;

  const _ChallengeFormDialog({this.challenge, required this.onSave});

  @override
  State<_ChallengeFormDialog> createState() => _ChallengeFormDialogState();
}

class _ChallengeFormDialogState extends State<_ChallengeFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _goalController;
  late TextEditingController _totalTargetController;
  late TextEditingController _customUnitController;
  String _selectedUnit = 'reps';
  bool _isCustomUnit = false;

  @override
  void initState() {
    super.initState();
    final c = widget.challenge;
    _nameController = TextEditingController(text: c?.name ?? '');
    _goalController = TextEditingController(text: c?.dailyGoal.toString() ?? '');
    _totalTargetController = TextEditingController(text: c?.totalTarget?.toString() ?? '');

    if (c != null) {
      if (['reps', 'minutes'].contains(c.unit)) {
        _selectedUnit = c.unit;
        _customUnitController = TextEditingController();
      } else {
        _selectedUnit = 'Custom unit';
        _isCustomUnit = true;
        _customUnitController = TextEditingController(text: c.unit);
      }
    } else {
      _customUnitController = TextEditingController();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.challenge != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Challenge' : 'Create Challenge'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Challenge name'),
            ),
            DropdownButtonFormField<String>(
              value: _selectedUnit,
              items: const [
                DropdownMenuItem(value: 'reps', child: Text('reps')),
                DropdownMenuItem(value: 'minutes', child: Text('minutes')),
                DropdownMenuItem(value: 'Custom unit', child: Text('Custom unit')),
              ],
              onChanged: (val) {
                setState(() {
                  _selectedUnit = val!;
                  _isCustomUnit = val == 'Custom unit';
                });
              },
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
            if (_isCustomUnit)
              TextFormField(
                controller: _customUnitController,
                decoration: const InputDecoration(labelText: 'Custom unit'),
              ),
            TextFormField(
              controller: _goalController,
              decoration: const InputDecoration(labelText: 'Daily goal'),
              keyboardType: TextInputType.number,
            ),
            TextFormField(
              controller: _totalTargetController,
              decoration: const InputDecoration(labelText: 'Total target (optional)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton( // Test uses tap(find.text('Create')) or 'Save changes'
          onPressed: () {
            final goal = double.tryParse(_goalController.text) ?? 0;
            final total = double.tryParse(_totalTargetController.text);
            final unit = _isCustomUnit ? _customUnitController.text : _selectedUnit;

            final newChallenge = ExerciseChallenge(
              id: widget.challenge?.id ?? '',
              uid: widget.challenge?.uid ?? '',
              name: _nameController.text,
              dailyGoal: goal,
              unit: unit,
              targetType: widget.challenge?.targetType ?? ExerciseTargetType.atLeast,
              totalTarget: total,
              categories: widget.challenge?.categories ?? [],
              archived: false,
            );
            widget.onSave(newChallenge);
            Navigator.pop(context);
          },
          child: Text(isEditing ? 'Save changes' : 'Create'),
        ),
      ],
    );
  }
}
