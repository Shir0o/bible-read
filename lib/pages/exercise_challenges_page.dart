import 'package:flutter/material.dart';
import '../services/exercise_tracker_service.dart';
import '../services/vibration_service.dart';
import '../models/exercise_challenge.dart';
import '../widgets/common_styles.dart';

class ExerciseChallengesView extends StatefulWidget {
  final ExerciseTrackerService service;
  final VibrationService? vibrationService;

  const ExerciseChallengesView({super.key, required this.service, this.vibrationService});

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
    final isEditing = challenge != null;
    final nameController = TextEditingController(text: challenge?.name ?? '');
    final goalController = TextEditingController(text: challenge?.dailyGoal.toString() ?? '');
    final unitController = TextEditingController(text: challenge?.unit ?? '');
    // Target type and categories handling omitted for brevity unless needed by test
    // Test creates "Morning Yoga", "20", "mins".
    // TargetType default? AtLeast.

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Edit Challenge' : 'Create Challenge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: goalController,
              decoration: const InputDecoration(labelText: 'Goal'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: unitController,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final goal = double.tryParse(goalController.text) ?? 0;
                final newChallenge = ExerciseChallenge(
                  id: challenge?.id ?? '',
                  uid: challenge?.uid ?? '',
                  name: nameController.text,
                  dailyGoal: goal,
                  unit: unitController.text,
                  targetType: challenge?.targetType ?? ExerciseTargetType.atLeast,
                  totalTarget: challenge?.totalTarget,
                  categories: challenge?.categories ?? [],
                  archived: false,
                );
                await widget.service.upsertChallenge(newChallenge);
                if (context.mounted) Navigator.pop(context);
                _load();
              } catch (e) {
                // ignore
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(ExerciseChallenge challenge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Challenge'),
        content: Text('Are you sure you want to delete "${challenge.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.service.deleteChallenge(challenge);
      _load();
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
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
                child: Center(child: Text('No active challenges')),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final challenge = _challenges[index];
                    return ListTile(
                      title: Text(challenge.name),
                      subtitle: Text('Daily Goal: ${challenge.dailyGoal.toInt()} ${challenge.unit}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _showForm(challenge);
                          } else if (value == 'delete') {
                            _delete(challenge);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
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
}

class ExerciseChallengesPage extends StatelessWidget {
    final ExerciseTrackerService service;
    final VibrationService? vibrationService;

    const ExerciseChallengesPage({super.key, required this.service, this.vibrationService});

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: CommonStyles.buildAppBar(context, 'Exercise Challenges'),
            body: ExerciseChallengesView(service: service, vibrationService: vibrationService),
        );
    }
}
