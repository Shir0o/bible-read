import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/bible_progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BibleProgressService', () {
    const userId = 'user1';
    late FakeFirebaseFirestore firestore;
    late BibleProgressService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = BibleProgressService(firestore: firestore);
    });

    Future<void> seedGroup(String groupId) async {
      final groupRef = firestore.collection('groups').doc(groupId);
      await groupRef.set({'name': 'Group $groupId', 'ownerUid': userId});
      await groupRef.collection('members').doc(userId).set({'uid': userId});
    }

    Future<void> seedSchedule({
      required String groupId,
      required DateTime date,
      required List<String> chapters,
      Iterable<int> completed = const <int>{},
      bool? doneOverride,
    }) async {
      final groupRef = firestore.collection('groups').doc(groupId);
      final dateId = _dateId(date);
      await groupRef.collection('schedule').doc(dateId).set({
        'date': Timestamp.fromDate(
          DateTime.utc(date.year, date.month, date.day),
        ),
        'chapters': chapters,
      });
      if (completed.isEmpty && doneOverride != true) {
        return;
      }
      final entryRef = groupRef
          .collection('progress')
          .doc(dateId)
          .collection('entries')
          .doc(userId);
      final count = completed.length;
      await entryRef.set({
        'uid': userId,
        'groupId': groupId,
        'dateId': dateId,
        'done':
            doneOverride ?? (chapters.isNotEmpty && count == chapters.length),
        'count': count,
      });
      for (final idx in completed) {
        await entryRef.collection('items').doc(idx.toString()).set({
          'done': true,
          'ts': Timestamp.fromDate(DateTime.utc(2024)),
        });
      }
    }

    test('returns partial completion across books', () async {
      await seedGroup('g1');
      await seedSchedule(
        groupId: 'g1',
        date: DateTime(2024, 5, 1),
        chapters: const ['John 1', 'John 2', 'Genesis 1'],
        completed: const {0, 2},
      );

      final result = await service.completedChaptersByBook(userId);

      expect(result.length, 2);
      expect(result['John'], equals({1}));
      expect(result['Genesis'], equals({1}));
      expect(result['John']!.contains(2), isFalse);
    });

    test('deduplicates chapters completed in multiple groups', () async {
      await seedGroup('g1');
      await seedGroup('g2');

      await seedSchedule(
        groupId: 'g1',
        date: DateTime(2024, 5, 1),
        chapters: const ['John 1'],
        completed: const {0},
      );

      await seedSchedule(
        groupId: 'g2',
        date: DateTime(2024, 5, 2),
        chapters: const ['John 1'],
        completed: const {0},
      );

      final result = await service.completedChaptersByBook(userId);

      expect(
        result,
        equals({
          'John': {1},
        }),
      );
    });

    test('handles full book completion including legacy done flag', () async {
      await seedGroup('g1');

      await seedSchedule(
        groupId: 'g1',
        date: DateTime(2024, 6, 1),
        chapters: const ['Ruth 1', 'Ruth 2'],
        completed: const {0, 1},
      );

      await seedSchedule(
        groupId: 'g1',
        date: DateTime(2024, 6, 2),
        chapters: const ['Ruth 3', 'Ruth 4'],
        completed: const <int>{},
        doneOverride: true,
      );

      final result = await service.completedChaptersByBook(userId);

      expect(result['Ruth'], equals({1, 2, 3, 4}));
    });

    test('includes manual book completions', () async {
      // Genesis has 50 chapters
      await firestore
          .collection('users')
          .doc(userId)
          .collection('bible_books')
          .doc('Genesis')
          .set({'completed': true});

      final result = await service.completedChaptersByBook(userId);

      expect(result['Genesis'], isNotNull);
      expect(result['Genesis']!.length, 50);
      expect(result['Genesis']!.contains(1), isTrue);
      expect(result['Genesis']!.contains(50), isTrue);
    });

    test('merges group progress and manual completion seamlessly', () async {
      await seedGroup('g1');
      // Group progress: Ruth 1, 2
      await seedSchedule(
        groupId: 'g1',
        date: DateTime(2024, 6, 1),
        chapters: const ['Ruth 1', 'Ruth 2'],
        completed: const {0, 1},
      );

      // Manual progress: Ruth (all chapters 1-4)
      await firestore
          .collection('users')
          .doc(userId)
          .collection('bible_books')
          .doc('Ruth')
          .set({'completed': true});

      final result = await service.completedChaptersByBook(userId);

      // Should have all chapters due to manual override
      expect(result['Ruth'], equals({1, 2, 3, 4}));
    });
  });
}

String _dateId(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
