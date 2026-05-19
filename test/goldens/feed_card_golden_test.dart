import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';
import 'package:bible_read/models/comment.dart';
import '../helpers/pump_golden.dart';

void main() {
  final log = ReadLog(
    uid: 'u1',
    name: 'Bob',
    likeNames: ['Charlie', 'Dave'],
    comments: [
      Comment(
        id: 'c1',
        uid: 'u2',
        authorName: 'Charlie',
        message: 'Great job!',
        timestamp: DateTime(2023, 1, 1, 12, 0),
      ),
    ],
    liked: true,
    firstReader: false,
    timestamp: DateTime(2023, 1, 1, 8, 0),
  );

  group('FeedCard Golden Test', () {
    testWidgets('FeedCard - Light Mode', (tester) async {
      await tester.pumpGolden(
        FeedCard(
          log: log,
          onToggleLike: () {},
        ),
        brightness: Brightness.light,
      );
      await expectLater(
        find.byType(FeedCard),
        matchesGoldenFile('goldens/feed_card_light.png'),
      );
    });

    testWidgets('FeedCard - Dark Mode', (tester) async {
      await tester.pumpGolden(
        FeedCard(
          log: log,
          onToggleLike: () {},
        ),
        brightness: Brightness.dark,
      );
      await expectLater(
        find.byType(FeedCard),
        matchesGoldenFile('goldens/feed_card_dark.png'),
      );
    });

    testWidgets('FeedCard - Large Text', (tester) async {
      await tester.pumpGolden(
        FeedCard(
          log: log,
          onToggleLike: () {},
        ),
        brightness: Brightness.light,
        textScaleFactor: 1.5,
      );
      await expectLater(
        find.byType(FeedCard),
        matchesGoldenFile('goldens/feed_card_large_text.png'),
      );
    });
  });
}
