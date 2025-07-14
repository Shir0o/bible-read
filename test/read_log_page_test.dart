import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/read_log_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadLogPage', () {
    test('writeReadLogEntry creates Firestore document', () async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(
        uid: '123',
        displayName: 'Test User',
        email: 'test@example.com',
      );

      await ReadLogPage.writeReadLogEntry(user, firestore: firestore);

      final dateKey =
          '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
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

    testWidgets('shows "User not signed in" when not authenticated', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(signedIn: false);

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(firestore: firestore, auth: auth)));
      await tester.pumpAndSettle();

      expect(find.text('User not signed in.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loadLogs populates _logs list', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey =
          '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
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

      await tester.pumpWidget(MaterialApp(
          home: ReadLogPage(
              firestore: firestore,
              auth: MockFirebaseAuth(mockUser: user, signedIn: true))));
      await tester.pumpAndSettle();

      expect(find.text('User read today!'), findsOneWidget);
    });

    testWidgets('toggleLike adds and removes like', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth =
          MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
      final dateKey =
          '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
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

      await tester.pumpWidget(
          MaterialApp(home: ReadLogPage(firestore: firestore, auth: auth)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });
}
