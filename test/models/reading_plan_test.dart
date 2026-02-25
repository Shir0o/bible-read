import 'package:bible_read/models/reading_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadingPlanDay', () {
    test('fromJson and toJson work correctly', () {
      final json = {
        'day': 1,
        'readings': ['Gen 1', 'Matt 1'],
      };

      final day = ReadingPlanDay.fromJson(json);

      expect(day.day, 1);
      expect(day.readings, ['Gen 1', 'Matt 1']);
      expect(day.toJson(), json);
    });
  });

  group('ReadingPlan', () {
    test('fromJson and toJson work correctly', () {
      final dayJson = {
        'day': 1,
        'readings': ['Gen 1', 'Matt 1'],
      };
      final json = {
        'id': 'plan1',
        'title': 'My Plan',
        'description': 'A test plan',
        'durationDays': 30,
        'tags': ['test', 'bible'],
        'schedule': [dayJson],
      };

      final plan = ReadingPlan.fromJson(json);

      expect(plan.id, 'plan1');
      expect(plan.title, 'My Plan');
      expect(plan.description, 'A test plan');
      expect(plan.durationDays, 30);
      expect(plan.tags, ['test', 'bible']);
      expect(plan.schedule.length, 1);
      expect(plan.schedule.first.day, 1);
      
      expect(plan.toJson(), json);
    });

    test('fromJson handles null tags', () {
      final json = {
        'id': 'plan1',
        'title': 'My Plan',
        'description': 'A test plan',
        'durationDays': 30,
        'schedule': [],
      };

      final plan = ReadingPlan.fromJson(json);

      expect(plan.tags, isEmpty);
    });
  });
}
