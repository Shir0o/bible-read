import '../models/achievement.dart';
import '../models/achievement_definition.dart';
import 'achievement_service.dart';
import 'group_book_achievement_service.dart';
import 'reference_parser.dart';

/// Aggregates book completion data and unlocks the corresponding achievements.
class BookAchievementRefresher {
  /// Creates a refresher that writes unlocks through [achievementService] and
  /// aggregates progress via [groupBookAchievementService].
  BookAchievementRefresher({
    required this.achievementService,
    required this.groupBookAchievementService,
  });

  /// Service responsible for writing achievement unlocks.
  final AchievementService achievementService;

  /// Service that aggregates completed chapters across joined groups.
  final GroupBookAchievementService groupBookAchievementService;

  final Set<String> _pendingAchievementIds = <String>{};

  /// Unlocks any book achievements earned by [uid] as of
  /// [completionTimestamp].
  Future<BookAchievementRefreshResult> refresh({
    required String uid,
    required DateTime completionTimestamp,
    Set<String> skipAchievementIds = const <String>{},
  }) async {
    final completedByBook =
        await groupBookAchievementService.completedChaptersByBook(uid);
    if (completedByBook.isEmpty) {
      return const BookAchievementRefreshResult();
    }

    final unlockedIds = <String>{};
    final alreadyUnlockedIds = <String>{};

    for (final entry in completedByBook.entries) {
      final book = entry.key;
      final chapters = entry.value;
      final totalChapters = ReferenceParser.chapterCount(book);
      if (totalChapters == null || chapters.length < totalChapters) {
        continue;
      }

      final achievementId = _bookAchievementId(book);
      if (skipAchievementIds.contains(achievementId) ||
          _pendingAchievementIds.contains(achievementId)) {
        continue;
      }

      final existingSnap = await achievementService.firestore
          .collection('users')
          .doc(uid)
          .collection(AchievementService.achievementsCollection)
          .doc(achievementId)
          .get();
      if (existingSnap.exists) {
        alreadyUnlockedIds.add(achievementId);
        continue;
      }

      final definition = _findAchievementDefinition(achievementId);
      final achievement = Achievement(
        id: achievementId,
        title: definition?.title ?? 'Complete $book',
        type: 'book',
        dateUnlocked: completionTimestamp,
      );

      _pendingAchievementIds.add(achievementId);
      try {
        await achievementService.unlockAchievement(uid, achievement);
        unlockedIds.add(achievementId);
      } finally {
        _pendingAchievementIds.remove(achievementId);
      }
    }

    return BookAchievementRefreshResult(
      unlockedAchievementIds: unlockedIds,
      alreadyUnlockedAchievementIds: alreadyUnlockedIds,
    );
  }

  String _bookAchievementId(String book) {
    final slug = book
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'book_$slug';
  }

  AchievementDefinition? _findAchievementDefinition(String id) {
    for (final definition in allAchievements) {
      if (definition.id == id) {
        return definition;
      }
    }
    return null;
  }
}

/// Summary of achievements touched by a refresh operation.
class BookAchievementRefreshResult {
  /// Creates a result describing which achievements changed state.
  const BookAchievementRefreshResult({
    this.unlockedAchievementIds = const <String>{},
    this.alreadyUnlockedAchievementIds = const <String>{},
  });

  /// Achievements newly unlocked by this refresh.
  final Set<String> unlockedAchievementIds;

  /// Achievements that were already unlocked when evaluated.
  final Set<String> alreadyUnlockedAchievementIds;
}
