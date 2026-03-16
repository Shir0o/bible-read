import 'package:bible_read/models/achievement.dart';
import 'package:bible_read/services/achievement_service.dart';
import 'package:bible_read/services/book_achievement_refresher.dart';
import 'package:bible_read/services/group_book_achievement_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAchievementService extends Mock implements AchievementService {}

class MockGroupBookAchievementService extends Mock
    implements GroupBookAchievementService {}

class FakeAchievement extends Fake implements Achievement {
  @override
  String get id => 'fake_id';

  @override
  String get title => 'Fake Title';

  @override
  String get type => 'book';

  @override
  DateTime get dateUnlocked => DateTime.now();
}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockAchievementService achievementService;
  late MockGroupBookAchievementService groupBookAchievementService;
  late BookAchievementRefresher refresher;
  const uid = 'user_123';
  final now = DateTime(2024, 1, 1);

  setUpAll(() {
    registerFallbackValue(FakeAchievement());
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    achievementService = MockAchievementService();
    groupBookAchievementService = MockGroupBookAchievementService();

    // Stub the firestore property to return our fake instance
    when(() => achievementService.firestore).thenReturn(firestore);

    // Stub unlockAchievement to return void
    when(() => achievementService.unlockAchievement(any(), any()))
        .thenAnswer((_) async {});

    refresher = BookAchievementRefresher(
      achievementService: achievementService,
      groupBookAchievementService: groupBookAchievementService,
    );
  });

  group('BookAchievementRefresher', () {
    test('does nothing when no chapters are completed', () async {
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {});

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, isEmpty);
      expect(result.alreadyUnlockedAchievementIds, isEmpty);
      verifyNever(() => achievementService.unlockAchievement(any(), any()));
    });

    test('does nothing when book is partially completed', () async {
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'John': {1, 2}, // John has 21 chapters
              });

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, isEmpty);
      verifyNever(() => achievementService.unlockAchievement(any(), any()));
    });

    test('unlocks achievement when book is fully completed', () async {
      // Obadiah has 1 chapter
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'Obadiah': {1},
              });

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, contains('book_obadiah'));
      expect(result.alreadyUnlockedAchievementIds, isEmpty);

      final captured = verify(() => achievementService.unlockAchievement(
            uid,
            captureAny(),
          )).captured;
      final achievement = captured.first as Achievement;
      expect(achievement.id, 'book_obadiah');
      expect(achievement.dateUnlocked, now);
    });

    test('skips achievement if already unlocked in Firestore', () async {
      // Seed existing achievement
      await firestore
          .collection('users')
          .doc(uid)
          .collection('achievements')
          .doc('book_obadiah')
          .set({'title': 'Complete Obadiah'});

      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'Obadiah': {1},
              });

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, isEmpty);
      expect(result.alreadyUnlockedAchievementIds, contains('book_obadiah'));
      verifyNever(() => achievementService.unlockAchievement(any(), any()));
    });

    test('skips achievement if in skip list', () async {
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'Obadiah': {1},
              });

      final result = await refresher.refresh(
        uid: uid,
        completionTimestamp: now,
        skipAchievementIds: {'book_obadiah'},
      );

      expect(result.unlockedAchievementIds, isEmpty);
      verifyNever(() => achievementService.unlockAchievement(any(), any()));
    });

    test('unlocks multiple books', () async {
      // Obadiah (1), Philemon (1), 2 John (1), 3 John (1), Jude (1) are all 1 chapter books
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'Obadiah': {1},
                'Philemon': {1},
              });

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, hasLength(2));
      expect(result.unlockedAchievementIds,
          containsAll(['book_obadiah', 'book_philemon']));

      verify(() => achievementService.unlockAchievement(uid, any())).called(2);
    });

    test('handles partial completion alongside full completion', () async {
      when(() => groupBookAchievementService.completedChaptersByBook(uid))
          .thenAnswer((_) async => {
                'Obadiah': {1},
                'John': {1, 2}, // Incomplete
              });

      final result =
          await refresher.refresh(uid: uid, completionTimestamp: now);

      expect(result.unlockedAchievementIds, contains('book_obadiah'));
      expect(result.unlockedAchievementIds, isNot(contains('book_john')));
      verify(() => achievementService.unlockAchievement(uid, any())).called(1);
    });
  });
}
