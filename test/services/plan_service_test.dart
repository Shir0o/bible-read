import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/services/plan_service.dart';

void main() {
  group('PlanService', () {
    const service = PlanService();

    test('createSchedule generates creation plan assignments', () {
      final start = DateTime(2024, 5, 10, 9, 30);

      final schedule = service.createSchedule(
        plan: ReadingPlan.creationFoundations,
        startDate: start,
      );

      expect(schedule, hasLength(3));
      expect(schedule[0], isA<GroupSchedule>());
      expect(schedule[0].date, DateTime(2024, 5, 10));
      expect(schedule[0].chapters, ['Gen 1']);
      expect(schedule[1].date, DateTime(2024, 5, 11));
      expect(schedule[1].chapters, ['Gen 2']);
      expect(schedule[2].date, DateTime(2024, 5, 12));
      expect(schedule[2].chapters, ['Gen 3']);
    });

    test('createSchedule produces gospel highlights readings', () {
      final start = DateTime(2024, 6, 1);

      final schedule = service.createSchedule(
        plan: ReadingPlan.gospelHighlights,
        startDate: start,
      );

      expect(schedule, hasLength(5));
      expect(schedule.first.date, DateTime(2024, 6, 1));
      expect(schedule.first.chapters, ['John 1']);
      expect(schedule.last.date, DateTime(2024, 6, 5));
      expect(schedule.last.chapters, ['John 15']);
    });

    test('exposes metadata for each plan', () {
      final plans = service.plans;

      expect(plans, hasLength(3));
      expect(
        plans.map((p) => p.plan),
        containsAll(const [
          ReadingPlan.creationFoundations,
          ReadingPlan.gospelHighlights,
          ReadingPlan.psalmsOfPraise,
        ]),
      );
      expect(
        plans.map((p) => p.title),
        contains('Psalms of Praise (4 days)'),
      );
    });
  });
}
