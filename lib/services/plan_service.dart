import '../models/group_schedule.dart';

/// Identifiers for built-in reading plans.
enum ReadingPlan {
  /// Three-day plan covering the creation narrative.
  creationFoundations,

  /// Five-day plan highlighting moments from the Gospel of John.
  gospelHighlights,

  /// Four-day plan celebrating Psalms of praise.
  psalmsOfPraise,
}

/// Metadata describing a reading plan and its assignments.
class ReadingPlanDefinition {
  /// Creates a [ReadingPlanDefinition].
  const ReadingPlanDefinition({
    required this.plan,
    required this.title,
    required this.description,
    required this.readings,
  });

  /// Identifier for this plan.
  final ReadingPlan plan;

  /// Display name shown in the UI.
  final String title;

  /// Short summary of the reading plan.
  final String description;

  /// Chapters assigned for each day of the plan.
  final List<List<String>> readings;
}

/// Generates schedules for predefined reading plans.
class PlanService {
  /// Creates a [PlanService].
  const PlanService();

  static const List<ReadingPlanDefinition> _definitions = [
    ReadingPlanDefinition(
      plan: ReadingPlan.creationFoundations,
      title: 'Creation Foundations (3 days)',
      description:
          'Read the opening chapters of Genesis together over three days.',
      readings: [
        ['Gen 1'],
        ['Gen 2'],
        ['Gen 3'],
      ],
    ),
    ReadingPlanDefinition(
      plan: ReadingPlan.gospelHighlights,
      title: 'Gospel Highlights (5 days)',
      description: 'Walk through key moments in the Gospel of John.',
      readings: [
        ['John 1'],
        ['John 3'],
        ['John 6'],
        ['John 11'],
        ['John 15'],
      ],
    ),
    ReadingPlanDefinition(
      plan: ReadingPlan.psalmsOfPraise,
      title: 'Psalms of Praise (4 days)',
      description:
          'Celebrate worship with a selection of Psalms focused on praise.',
      readings: [
        ['Psalm 8'],
        ['Psalm 19'],
        ['Psalm 23'],
        ['Psalm 103'],
      ],
    ),
  ];

  static final Map<ReadingPlan, ReadingPlanDefinition> _lookup = {
    for (final definition in _definitions) definition.plan: definition,
  };

  /// List of available reading plans for selection.
  List<ReadingPlanDefinition> get plans =>
      List<ReadingPlanDefinition>.unmodifiable(_definitions);

  /// Returns the metadata for [plan].
  ReadingPlanDefinition definitionFor(ReadingPlan plan) {
    final definition = _lookup[plan];
    if (definition == null) {
      throw ArgumentError('Unknown plan: $plan');
    }
    return definition;
  }

  /// Builds a series of [GroupSchedule] entries for [plan] starting on
  /// [startDate].
  List<GroupSchedule> createSchedule({
    required ReadingPlan plan,
    required DateTime startDate,
  }) {
    final definition = definitionFor(plan);
    final baseDate = DateTime(startDate.year, startDate.month, startDate.day);
    return List<GroupSchedule>.generate(definition.readings.length, (index) {
      final reading = definition.readings[index];
      return GroupSchedule(
        date: baseDate.add(Duration(days: index)),
        chapters: List<String>.from(reading),
      );
    });
  }
}
