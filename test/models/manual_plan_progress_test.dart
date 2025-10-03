import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/manual_plan_progress.dart';

void main() {
  group('ManualPlanProgress.fromMap', () {
    test('reads manualPlanProgress map when present', () {
      final progress = ManualPlanProgress.fromMap({
        'manualPlanProgress': {
          'nextChapterReference': 'Gen 1',
          'defaultChaptersPerDay': 2,
          'lastMaterializedDate': Timestamp.fromDate(DateTime.utc(2024, 5, 1)),
        },
      });

      expect(progress.nextChapterReference, 'Gen 1');
      expect(progress.defaultChaptersPerDay, 2);
      expect(progress.lastMaterializedDate, DateTime.utc(2024, 5, 1));
    });

    test('falls back to legacy top-level keys', () {
      final progress = ManualPlanProgress.fromMap({
        'nextChapterRef': 'Ex 2',
        'chaptersPerDay': 3,
        'lastGeneratedAt': Timestamp.fromDate(DateTime.utc(2024, 6, 15, 12, 0)),
      });

      expect(progress.nextChapterReference, 'Ex 2');
      expect(progress.defaultChaptersPerDay, 3);
      expect(progress.lastMaterializedDate, DateTime.utc(2024, 6, 15));
    });

    test('parses string and numeric date fallbacks', () {
      final progress = ManualPlanProgress.fromMap({
        'manual': {
          'lastMaterialized': '2024-07-04',
        },
        'cursorRef': 'Matt 1',
        'defaultChapterCount': 1,
      });

      expect(progress.lastMaterializedDate, DateTime.utc(2024, 7, 4));
    });

    test('treats empty strings as null', () {
      final progress = ManualPlanProgress.fromMap({
        'manualPlanProgress': {
          'nextChapterReference': '   ',
          'defaultChaptersPerDay': 0,
        },
      });

      expect(progress.nextChapterReference, isNull);
      expect(progress.defaultChaptersPerDay, isNull);
    });
  });

  group('ManualPlanProgress.toFirestore', () {
    test('omits null fields', () {
      final progress = ManualPlanProgress();
      expect(progress.toFirestore(), isEmpty);
    });

    test('serialises values with UTC dates', () {
      final progress = ManualPlanProgress(
        nextChapterReference: 'Luke 3',
        defaultChaptersPerDay: 4,
        lastMaterializedDate: DateTime(2024, 8, 20, 10, 30),
      );

      final map = progress.toFirestore();
      expect(map['nextChapterReference'], 'Luke 3');
      expect(map['defaultChaptersPerDay'], 4);
      expect(map['lastMaterializedDate'],
          Timestamp.fromDate(DateTime.utc(2024, 8, 20)));
    });
  });

  test('copyWith overrides fields selectively', () {
    final base = ManualPlanProgress(
      nextChapterReference: 'Acts 1',
      defaultChaptersPerDay: 2,
      lastMaterializedDate: DateTime.utc(2024, 9, 1),
    );

    final copy = base.copyWith(
      nextChapterReference: 'Acts 2',
      defaultChaptersPerDay: 3,
    );

    expect(copy.nextChapterReference, 'Acts 2');
    expect(copy.defaultChaptersPerDay, 3);
    expect(copy.lastMaterializedDate, DateTime.utc(2024, 9, 1));
  });

  test('copyWith clears fields when requested', () {
    final base = ManualPlanProgress(
      nextChapterReference: 'Acts 1',
      defaultChaptersPerDay: 2,
      lastMaterializedDate: DateTime.utc(2024, 9, 1),
    );

    final cleared = base.copyWith(
      clearNextChapterReference: true,
      clearDefaultChaptersPerDay: true,
      clearLastMaterializedDate: true,
    );

    expect(cleared.nextChapterReference, isNull);
    expect(cleared.defaultChaptersPerDay, isNull);
    expect(cleared.lastMaterializedDate, isNull);
  });
}
