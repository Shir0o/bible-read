import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/widgets/comment_drawer.dart';
import 'package:bible_read/widgets/comment_section.dart';
import 'package:bible_read/models/comment.dart';

import 'package:bible_read/pages/read_log_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadLogPage comments', () {
    final fixedDate = DateTime(2025, 7, 15);

    Future<void> pumpPage(
      WidgetTester tester, {
      required FakeFirebaseFirestore firestore,
      required MockFirebaseAuth auth,
      required Future<void> Function(
              {required String ownerUid, required String commenterName})
          onSend,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: ReadLogPage(
          firestore: firestore,
          auth: auth,
          dateProvider: () => fixedDate,
          onSendLikeNotification: (
              {required String ownerUid, required String likerName}) async {},
          onSendCommentNotification: onSend,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('loads comments from Firestore', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User',
        'email': 'u@test.com',
        'timestamp': Timestamp.now()
      });
      final commentsRef = firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .collection('comments');
      await commentsRef.add({
        'uid': 'u2',
        'authorName': 'Alice',
        'message': 'First',
        'timestamp': Timestamp.now(),
      });
      await commentsRef.add({
        'uid': 'u3',
        'authorName': 'Bob',
        'message': 'Second',
        'timestamp': Timestamp.now(),
      });
      await commentsRef.add({
        'uid': 'u4',
        'authorName': 'Cat',
        'message': 'Third',
        'timestamp': Timestamp.now(),
      });

      await pumpPage(tester,
          firestore: firestore,
          auth: auth,
          onSend: ({required ownerUid, required commenterName}) async {});

      final commentSection = find.byType(CommentSection);
      Future<void> expectTile(String author, String message) async {
        final tileFinder = find.descendant(
          of: commentSection,
          matching: find.widgetWithText(ListTile, author),
        );
        expect(tileFinder, findsOneWidget);
        final tile = tester.widget<ListTile>(tileFinder);
        expect(tile.subtitle, isA<Text>());
        expect((tile.subtitle as Text).data, message);
      }

      await expectTile('Alice', 'First');
      await expectTile('Bob', 'Second');
      await expectTile('Cat', 'Third');
    });

    testWidgets('posting comment writes to Firestore', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final ownerUid = 'u1';
      final user = MockUser(uid: 'u2', displayName: 'Bob Jones');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(ownerUid)
          .set({
        'name': 'Owner',
        'email': 'o@test.com',
        'timestamp': Timestamp.now()
      });

      await pumpPage(tester,
          firestore: firestore,
          auth: auth,
          onSend: ({required ownerUid, required commenterName}) async {});

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(CommentDrawer), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Nice');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final snap = await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(ownerUid)
          .collection('comments')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['message'], 'Nice');

      final bobTiles = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title as Text).data == 'Bob' &&
            widget.subtitle is Text &&
            (widget.subtitle as Text).data == 'Nice',
      );
      expect(bobTiles, findsNWidgets(2));
    });

    testWidgets('adding comment notifies owner', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final ownerUid = 'u1';
      final commenter = MockUser(uid: 'u2', displayName: 'Jane Doe');
      final auth = MockFirebaseAuth(mockUser: commenter, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(ownerUid)
          .set({
        'name': 'Owner',
        'email': 'o@test.com',
        'timestamp': Timestamp.now()
      });

      var called = 0;
      Future<void> notify(
          {required String ownerUid, required String commenterName}) async {
        called++;
        expect(ownerUid, 'u1');
        expect(commenterName, 'Jane');
      }

      await pumpPage(tester, firestore: firestore, auth: auth, onSend: notify);

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(CommentDrawer), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Hi');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(called, 1);
    });

    testWidgets('shows comment without progress indicator while posting',
        (tester) async {
      final completer = Completer<Comment>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommentDrawer(
              comments: const [],
              onAdd: (_) => completer.future,
              commenterName: 'Temp',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Quick');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      final tempTile = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title as Text).data == 'Temp' &&
            widget.subtitle is Text &&
            (widget.subtitle as Text).data == 'Quick',
      );
      expect(tempTile, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(completer.isCompleted, isFalse);
    });

    testWidgets('comment drawer opens at one third height', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User',
        'email': 'u@test.com',
        'timestamp': Timestamp.now(),
      });

      await pumpPage(tester,
          firestore: firestore,
          auth: auth,
          onSend: ({required ownerUid, required commenterName}) async {});

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();

      final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(sheet.initialChildSize, closeTo(0.33, 0.01));
    });
  });
}
