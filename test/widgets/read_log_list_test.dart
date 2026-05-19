import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_log_list.dart';
import 'package:bible_read/models/read_log.dart';

void main() {
  testWidgets('FeedCard displays correctly and like button works',
      (tester) async {
    String? likedUid;
    final logs = [
      ReadLog(
        uid: '1',
        name: 'Alice',
        liked: false,
        likeNames: const [],
        firstReader: false,
        comments: const [],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogList(
            logs: logs,
            onToggleLike: (uid) => likedUid = uid,
          ),
        ),
      ),
    );

    // Check for name
    expect(find.text('Alice'), findsOneWidget);
    // Check for "Read today"
    expect(find.text('Read today'), findsOneWidget);

    // Tap like button.
    final likeBtn = find.byIcon(Icons.favorite_border_rounded);
    expect(likeBtn, findsOneWidget);
    await tester.tap(likeBtn);
    await tester.pump();

    expect(likedUid, '1');
  });

  testWidgets('FeedCard omits comment controls', (tester) async {
    final logs = [
      ReadLog(
        uid: 'user1',
        name: 'Bob',
        liked: false,
        likeNames: const [],
        firstReader: false,
        comments: const [],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogList(
            logs: logs,
            onToggleLike: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Comment'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
