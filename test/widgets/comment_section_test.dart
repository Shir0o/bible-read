import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/comment_section.dart';
import 'package:bible_read/models/comment.dart';

class RecordingOnAdd {
  String? message;
  bool throwError = false;

  Future<void> call(String text) async {
    message = text;
    if (throwError) throw Exception('fail');
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
            onAdd: (_) async {},
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post'));
    await tester.pumpAndSettle();

    expect(recorder.message, 'Nice');
    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, isEmpty);
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
    await tester.tap(find.widgetWithText(ElevatedButton, 'Post'));
    await tester.pumpAndSettle();

    expect(
        find.text('Failed to add comment. Please try again.'), findsOneWidget);
  });
}
