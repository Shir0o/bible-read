import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';
import 'package:bible_read/models/comment.dart';

void main() {
  testWidgets('FeedCard action buttons have correct semantics', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: true, // Test liked state
      likeNames: const [],
      firstReader: false,
      comments: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(
            log: log,
            onToggleLike: () {},
            onAddComment: (msg) async {
              return Comment(
                id: 'new',
                uid: 'me',
                authorName: 'Tester',
                message: msg,
                timestamp: DateTime.now(),
              );
            },
            currentUserName: 'Tester',
          ),
        ),
      ),
    );

    // 1. Check "Encourage" button semantics
    // We look for the Semantics widget we explicitly added.
    // It should have label "Encourage" and selected: true.
    final encourageSemanticsFinder = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label == 'Encourage' &&
            widget.properties.selected == true;
      }
      return false;
    });

    expect(encourageSemanticsFinder, findsOneWidget);

    final encourageNode = tester.getSemantics(encourageSemanticsFinder);
    final encourageData = encourageNode.getSemanticsData();

    // We expect it to have button flag
    // ignore: deprecated_member_use
    expect(encourageData.hasFlag(SemanticsFlag.isButton), isTrue,
        reason: 'Encourage should be a button');
    // We expect it to be enabled
    // ignore: deprecated_member_use
    expect(encourageData.hasFlag(SemanticsFlag.isEnabled), isTrue,
        reason: 'Encourage should be enabled');
    // We expect it to be selected (because liked=true)
    // ignore: deprecated_member_use
    expect(encourageData.hasFlag(SemanticsFlag.isSelected), isTrue,
        reason: 'Encourage should be selected');

    // 2. Check "Comment" button semantics
    // It should have label "Comment" (or "0" if using count logic, here empty comments so "Comment")
    // and selected should be null (so not flagged as selected).
    final commentSemanticsFinder = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label == 'Comment';
      }
      return false;
    });
    expect(commentSemanticsFinder, findsOneWidget);

    final commentNode = tester.getSemantics(commentSemanticsFinder);
    final commentData = commentNode.getSemanticsData();

    // ignore: deprecated_member_use
    expect(commentData.hasFlag(SemanticsFlag.isButton), isTrue,
        reason: 'Comment should be a button');
    // ignore: deprecated_member_use
    expect(commentData.hasFlag(SemanticsFlag.isEnabled), isTrue,
        reason: 'Comment should be enabled');
    // It should NOT be selected
    // ignore: deprecated_member_use
    expect(commentData.hasFlag(SemanticsFlag.isSelected), isFalse,
        reason: 'Comment should not be selected');
  });

  testWidgets('FeedCard send button has tooltip', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: false,
      likeNames: const [],
      firstReader: false,
      comments: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(
            log: log,
            onToggleLike: () {},
            onAddComment: (msg) async {
              return Comment(
                id: 'new',
                uid: 'me',
                authorName: 'Tester',
                message: msg,
                timestamp: DateTime.now(),
              );
            },
            currentUserName: 'Tester',
          ),
        ),
      ),
    );

    // Expand to show input
    await tester.tap(find.text('Bob')); // Tap header to expand
    await tester.pumpAndSettle();

    // Find the send button (IconButton.filled)
    final sendButtonFinder = find.byIcon(Icons.send_rounded);
    expect(sendButtonFinder, findsOneWidget);

    // Check tooltip
    final tooltipFinder = find.byTooltip('Send comment');
    expect(tooltipFinder, findsOneWidget);
  });

  testWidgets('FeedCard Read today uses MergeSemantics', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: false,
      likeNames: const [],
      firstReader: false,
      comments: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(
            log: log,
            onToggleLike: () {},
            onAddComment: (msg) async {
              return Comment(
                id: 'new',
                uid: 'me',
                authorName: 'Tester',
                message: msg,
                timestamp: DateTime.now(),
              );
            },
            currentUserName: 'Tester',
          ),
        ),
      ),
    );

    // Find MergeSemantics wrapping the Read today row.
    // We can look for MergeSemantics ancestor of "Read today" text.
    final readTodayText = find.text('Read today');
    final mergeSemantics =
        find.ancestor(of: readTodayText, matching: find.byType(MergeSemantics));
    expect(mergeSemantics, findsOneWidget);
  });
}
