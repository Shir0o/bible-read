import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_log_list.dart';
import 'package:bible_read/models/comment.dart';
import 'package:bible_read/models/read_log.dart';

void main() {
  testWidgets('FeedCard displays correctly and like button works', (tester) async {
    String? likedUid;
    final logs = [
      ReadLog(
        uid: '1',
        name: 'Alice',
        liked: false,
        likeNames: const [],
        firstReader: false,
        comments: const <Comment>[],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogList(
            logs: logs,
            onToggleLike: (uid) => likedUid = uid,
            onAddComment: (uid, msg) async => Comment(
              id: 'c1',
              uid: uid,
              authorName: 'Tester',
              message: msg,
              timestamp: DateTime.now(),
            ),
            commenterName: 'Tester',
          ),
        ),
      ),
    );

    // Check for name
    expect(find.text('Alice'), findsOneWidget);
    // Check for "Read today"
    expect(find.text('Read today'), findsOneWidget);

    // Tap like button (Encourage)
    final likeBtn = find.byIcon(Icons.favorite_outline_rounded);
    expect(likeBtn, findsOneWidget);
    await tester.tap(likeBtn);
    await tester.pump();

    expect(likedUid, '1');
  });

  testWidgets('FeedCard expands to show comments and composer', (tester) async {
    String? postedMessage;
    final logs = [
      ReadLog(
        uid: 'user1',
        name: 'Bob',
        liked: false,
        likeNames: const [],
        firstReader: false,
        comments: [
          Comment(
             id: 'c1', 
             uid: 'u2', 
             authorName: 'Charlie', 
             message: 'Great job!', 
             timestamp: DateTime.now()
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadLogList(
            logs: logs,
            onToggleLike: (_) {},
            onAddComment: (uid, msg) async {
              postedMessage = msg;
              return Comment(
                id: 'new',
                uid: 'me',
                authorName: 'Tester',
                message: msg,
                timestamp: DateTime.now(),
              );
            },
            commenterName: 'Tester',
          ),
        ),
      ),
    );

    // Initial check: Comments might be in tree but hidden (AnimatedCrossFade).
    // We just verify we can expand and see the composer.

    // Tap to expand (either comment button or card body)
    await tester.tap(find.text('Bob')); 
    await tester.pumpAndSettle();

    // Now comment should be visible and composer interactive
    expect(find.text('Great job!'), findsOneWidget);

    // Composer should be visible
    expect(find.byType(TextField), findsOneWidget);

    // Enter text
    await tester.enterText(find.byType(TextField), 'Keep it up!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // Tap send (if needed, but onSubmitted handles it too)
    // Find the send button (arrow_upward_rounded)
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();

    expect(postedMessage, 'Keep it up!');
  });
}
