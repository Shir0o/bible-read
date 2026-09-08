import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';

void main() {
  testWidgets('FeedCard action buttons have correct semantics', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: true, // Test liked state
      likeNames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(log: log, onToggleLike: () {}),
        ),
      ),
    );

    // 1. Check "Amen" button semantics
    // We look for the Semantics widget we explicitly added.
    // It should have label "Amen" and selected: true.
    final amenSemanticsFinder = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label == 'Amen' &&
            widget.properties.selected == true;
      }
      return false;
    });

    expect(amenSemanticsFinder, findsOneWidget);

    final amenNode = tester.getSemantics(amenSemanticsFinder);
    final amenData = amenNode.getSemanticsData();

    // We expect it to have button flag
    // ignore: deprecated_member_use
    expect(
      amenData.hasFlag(SemanticsFlag.isButton),
      isTrue,
      reason: 'Amen should be a button',
    );
    expect(
      amenData.hasFlag(SemanticsFlag.isEnabled),
      isTrue,
      reason: 'Amen should be enabled',
    );
    expect(
      amenData.hasFlag(SemanticsFlag.isSelected),
      isTrue,
      reason: 'Amen should be selected',
    );

    expect(find.text('Comment'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
  });

  testWidgets('FeedCard does not expose comment composer', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: false,
      likeNames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(log: log, onToggleLike: () {}),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.send_rounded), findsNothing);
  });

  testWidgets('FeedCard Read today uses MergeSemantics', (tester) async {
    final log = ReadLog(
      uid: 'user1',
      name: 'Bob',
      liked: false,
      likeNames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedCard(log: log, onToggleLike: () {}),
        ),
      ),
    );

    // Find MergeSemantics wrapping the Read today row.
    // We can look for MergeSemantics ancestor of "Read today" text.
    final readTodayText = find.text('Read today');
    final mergeSemantics = find.ancestor(
      of: readTodayText,
      matching: find.byType(MergeSemantics),
    );
    expect(mergeSemantics, findsOneWidget);
  });
}
