import 'package:bible_read/services/plan_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanGenerator with firstDayChapters', () {
    test('generates 1 chapter on Day 1 and 2 chapters on remaining days', () {
      final plan = PlanGenerator.generatePlan(
        id: 'test_plan',
        title: 'Genesis Walk',
        description: 'Test description',
        type: PlanType.sequential,
        selectedBooks: ['Genesis'], // 50 chapters
        customChaptersPerDay: 2,
        firstDayChapters: 1,
      );

      // Total chapters: 50
      // Day 1: Genesis 1 (1 chapter)
      // Days 2..25: 2 chapters each (48 chapters total, covering Gen 2..49)
      // Day 26: Genesis 50 (1 chapter)
      // Total days: 26
      expect(plan.schedule.length, 26);
      expect(plan.schedule[0].day, 1);
      expect(plan.schedule[0].readings, ['Genesis 1']);

      expect(plan.schedule[1].day, 2);
      expect(plan.schedule[1].readings, ['Genesis 2', 'Genesis 3']);

      expect(plan.schedule[2].day, 3);
      expect(plan.schedule[2].readings, ['Genesis 4', 'Genesis 5']);

      expect(plan.schedule.last.day, 26);
      expect(plan.schedule.last.readings, ['Genesis 50']);

      // All 50 chapters must be accounted for exactly once
      final allReadings = plan.schedule.expand((d) => d.readings).toList();
      expect(allReadings.length, 50);
      expect(allReadings.first, 'Genesis 1');
      expect(allReadings.last, 'Genesis 50');
    });

    test(
        'defaults to customChaptersPerDay on Day 1 when firstDayChapters is null',
        () {
      final plan = PlanGenerator.generatePlan(
        id: 'test_plan',
        title: 'Genesis Walk',
        description: 'Test description',
        type: PlanType.sequential,
        selectedBooks: ['Genesis'],
        customChaptersPerDay: 2,
      );

      expect(plan.schedule.length, 25);
      expect(plan.schedule[0].readings, ['Genesis 1', 'Genesis 2']);
      expect(plan.schedule[1].readings, ['Genesis 3', 'Genesis 4']);
    });
  });
}
