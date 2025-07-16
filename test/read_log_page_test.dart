import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/read_log_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadLogPage', () {
    final fixedDate = DateTime(2025, 7, 15);

    test('writeReadLogEntry creates Firestore document', () async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(
        uid: '123',
        displayName: 'Test User',
        email: 'test@example.com',
      );

      await ReadLogPage.writeReadLogEntry(
        user,
        firestore: firestore,
        dateProvider: () => fixedDate,
      );

      final dateKey = '${fixedDate.year}-${fixedDate.month}-${fixedDate.day}';
      final snapshot = await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid)
          .get();

      expect(snapshot.exists, isTrue);
      expect(snapshot.data()?['name'], 'Test');
      expect(snapshot.data()?['email'], 'test@example.com');
    });

    testWidgets('shows sign in prompt when not authenticated', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth();

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(
              firestore: firestore,
              auth: auth,
              dateProvider: () => fixedDate,
              onSendLikeNotification: (
                  {required String ownerUid,
                  required String likerName}) async {})));
      await tester.pumpAndSettle();

      expect(
          find.text('Please sign in to view your read log.'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loadLogs populates _logs list', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey = '${fixedDate.year}-${fixedDate.month}-${fixedDate.day}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User One',
        'email': 'u1@test.com',
        'timestamp': Timestamp.now()
      });
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .collection('likes')
          .doc('l1')
          .set({'timestamp': Timestamp.now(), 'name': 'Liker'});

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(
              firestore: firestore,
              auth: MockFirebaseAuth(mockUser: user, signedIn: true),
              dateProvider: () => fixedDate,
              onSendLikeNotification: (
                  {required String ownerUid,
                  required String likerName}) async {})));
      await tester.pumpAndSettle();

      expect(find.text('User read today!'), findsOneWidget);
      expect(find.textContaining('Liked by'), findsOneWidget);
    });

    testWidgets('toggleLike adds and removes like', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1', displayName: 'Tester One');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey = '${fixedDate.year}-${fixedDate.month}-${fixedDate.day}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .set({
        'name': 'User Two',
        'email': 'u2@test.com',
        'timestamp': Timestamp.now()
      });

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(
              firestore: firestore,
              auth: auth,
              dateProvider: () => fixedDate,
              onSendLikeNotification: (
                  {required String ownerUid,
                  required String likerName}) async {})));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.runAsync(() async {
        final likeDoc = await firestore
            .collection('read_logs')
            .doc(dateKey)
            .collection('entries')
            .doc('u2')
            .collection('likes')
            .doc(user.uid)
            .get();
        expect(likeDoc.data()?['name'], 'Tester');
      });

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });

    testWidgets('toggleLike triggers push notification', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final liker = MockUser(uid: 'liker', displayName: 'Jane Doe');
      final auth = MockFirebaseAuth(mockUser: liker, signedIn: true);
      final ownerUid = 'owner1';
      final dateKey = '${fixedDate.year}-${fixedDate.month}-${fixedDate.day}';

      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(ownerUid)
          .set({
        'name': 'Owner',
        'email': 'o@test.com',
        'timestamp': Timestamp.now(),
      });

      var called = 0;
      Future<void> mockNotification(
          {required String ownerUid, required String likerName}) async {
        called++;
        expect(ownerUid, 'owner1');
        expect(likerName, 'Jane');
      }

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(
              firestore: firestore,
              auth: auth,
              dateProvider: () => fixedDate,
              onSendLikeNotification: mockNotification)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(called, 1);
    });
  });
}
