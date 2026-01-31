import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';
import 'package:bible_read/models/comment.dart';

void main() {
  testWidgets('FeedCard comment input has correct UX properties',
      (tester) async {
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
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    final textFieldFinder = find.byType(TextField);
    expect(textFieldFinder, findsOneWidget);

    final textField = tester.widget<TextField>(textFieldFinder);

    // Check capitalization
    expect(textField.textCapitalization, TextCapitalization.sentences,
        reason: 'Should capitalize sentences');

    // Check input action
    expect(textField.textInputAction, TextInputAction.send,
        reason: 'Should show send action');

    // Check keyboard type
    expect(textField.keyboardType, TextInputType.multiline,
        reason: 'Should be multiline');

    // Check minLines/maxLines (optional but good)
    expect(textField.minLines, 1);
    expect(
        textField.maxLines, inInclusiveRange(3, 5)); // Allow some flexibility
  });

  testWidgets('FeedCard comment input shows clear button when text is entered',
      (tester) async {
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

    // Expand
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    // Verify no clear button initially
    expect(find.byIcon(Icons.clear), findsNothing);

    // Enter text
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    // Verify clear button appears
    final clearButton = find.byIcon(Icons.clear);
    expect(clearButton, findsOneWidget);

    // Tap clear button
    await tester.tap(clearButton);
    await tester.pump();

    // Verify text is cleared
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, isEmpty);

    // Verify clear button disappears
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
