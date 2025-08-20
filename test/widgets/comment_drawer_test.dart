import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/services/error_logger.dart';
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

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

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

  testWidgets('logs error when onAdd throws', (tester) async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    final crashlytics = MockCrashlytics();
    ErrorLogger.crashlytics = crashlytics;
    when(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        information: any(named: 'information'),
        printDetails: any(named: 'printDetails'),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: CommentDrawer(
          comments: const <Comment>[],
          onAdd: (_) => Future.error(Exception('fail')),
          commenterName: 'Tester',
        ),
      ),
    );

    final state = tester.state(find.byType(CommentDrawer)) as dynamic;

    await expectLater(state._handleAdd('Oops'), throwsException);

    verify(
      () => crashlytics.recordError(
        any(),
        any(),
        reason: any(named: 'reason'),
        information: any(named: 'information'),
        printDetails: any(named: 'printDetails'),
        fatal: false,
      ),
    ).called(1);
  });
}
