import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/feed_card.dart';
import 'package:bible_read/models/read_log.dart';
import 'package:bible_read/models/comment.dart';
import '../helpers/pump_app.dart';
import '../helpers/stub_vibration_service.dart';

void main() {
  late StubVibrationService vibrationService;

  setUp(() {
    vibrationService = StubVibrationService();
  });

  testWidgets('FeedCard handles likes and comments interactions',
      (tester) async {
    bool likeCalled = false;
    String? submittedComment;

    final log = ReadLog(
      uid: 'user1',
      name: 'Alice',
      liked: false,
      likeNames: [],
      firstReader: false,
      comments: [],
      timestamp: DateTime.now(),
    );

    await tester.pumpApp(
      Scaffold(
        body: SingleChildScrollView(
          child: FeedCard(
            log: log,
            currentUserName: 'Bob',
            onToggleLike: () async {
              likeCalled = true;
            },
            onAddComment: (msg) async {
              submittedComment = msg;
              return Comment(
                id: 'c1',
                uid: 'u2',
                authorName: 'Bob',
                message: msg,
                timestamp: DateTime.now(),
              );
            },
            vibrationService: vibrationService,
          ),
        ),
      ),
    );

    // Verify initial state
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Encourage'), findsOneWidget);

    // Test Like
    await tester.tap(find.text('Encourage'));
    await tester.pump();
    expect(likeCalled, isTrue);

    // Test Comment Expand
    // Find comment button
    final commentBtn = find.text('Comment'); // Label is 'Comment' if empty
    await tester.tap(commentBtn);
    await tester.pumpAndSettle(); // Animation

    // Verify input appears
    expect(find.byType(TextField), findsOneWidget);

    // Enter text
    await tester.enterText(find.byType(TextField), 'Great job!');
    await tester.pump();

    // Send
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();

    expect(submittedComment, 'Great job!');
  });
}
