import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/comment_section.dart';
import 'package:bible_read/models/comment.dart';

class RecordingOnAdd {
  String? message;
  bool throwError = false;

  Future<Comment> call(String text) async {
    message = text;
    if (throwError) throw Exception('fail');
    return Comment(
      id: 'id',
      uid: 'u',
      authorName: 'A',
      message: text,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders provided comments', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentSection(
            comments: comments,
            onAdd: (_) async => Comment(
              id: 'id',
              uid: 'u',
              authorName: 'A',
              message: '',
              timestamp: DateTime.now(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice: Hello'), findsOneWidget);
    expect(find.text('Bob: Hi'), findsOneWidget);
  });

  testWidgets('posting calls onAdd and clears field', (tester) async {
    final recorder = RecordingOnAdd();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentSection(
            comments: const [],
            onAdd: recorder.call,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Nice');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(recorder.message, 'Nice');
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, isEmpty);
  });

  testWidgets('displays comment before onAdd completes', (tester) async {
    final comments = <Comment>[];
    final completer = Completer<Comment>();

    Future<Comment> onAdd(String text) {
      final comment = Comment(
        id: 't',
        uid: 'u',
        authorName: 'A',
        message: text,
        timestamp: DateTime.now(),
      );
      comments.add(comment);
      return completer.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentSection(
            comments: comments,
            onAdd: onAdd,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hey');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('A: Hey'), findsOneWidget);
    expect(find.byKey(const ValueKey('progress')), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(completer.isCompleted, isFalse);
  });

  testWidgets('shows snackbar when onAdd throws', (tester) async {
    final recorder = RecordingOnAdd()..throwError = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentSection(
            comments: const [],
            onAdd: recorder.call,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Oops');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(
        find.text('Failed to add comment. Please try again.'), findsOneWidget);
  });
}
