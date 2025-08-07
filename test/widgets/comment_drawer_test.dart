import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/comment_drawer.dart';
import 'package:bible_read/models/comment.dart';

class RecordingOnAdd {
  String? message;
  final completer = Completer<Comment>();

  Future<Comment> call(String text) {
    message = text;
    return completer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('show displays bottom sheet and passes comments', (tester) async {
    final comments = [
      Comment(
        id: '1',
        uid: 'u1',
        authorName: 'Alice',
        message: 'Hello',
        timestamp: DateTime.now(),
      ),
      Comment(
        id: '2',
        uid: 'u2',
        authorName: 'Bob',
        message: 'Hi',
        timestamp: DateTime.now(),
      ),
    ];

    final recorder = RecordingOnAdd();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => CommentDrawer.show(
                context,
                comments: comments,
                onAdd: recorder.call,
                commenterName: 'Tester',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(CommentDrawer), findsOneWidget);
    expect(find.text('Alice: Hello'), findsOneWidget);
    expect(find.text('Bob: Hi'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Nice');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Tester: Nice'), findsOneWidget);

    recorder.completer.complete(
      Comment(
        id: 'id',
        uid: 'u',
        authorName: 'Recorder',
        message: 'Nice',
        timestamp: DateTime.now(),
      ),
    );

    await tester.pumpAndSettle();

    expect(recorder.message, 'Nice');
  });
}
