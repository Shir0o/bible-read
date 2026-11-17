import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/bible_progress_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('BibleProgressPage shows list of books', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: BibleProgressPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Genesis'), findsOneWidget); // Book name
    expect(find.text('PENTATEUCH'), findsOneWidget); // Category header

    // Scroll down to find Revelation
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text('Revelation'), findsOneWidget);
  });

  testWidgets('BibleProgressPage is read-only and displays completed books',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('read_through_state')
        .doc('current')
        .set({
      'ot': {'Genesis': List.generate(50, (i) => i + 1)},
      'nt': <String, dynamic>{},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BibleProgressPage(firestore: firestore, auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Genesis, Read this lap'), findsOneWidget);
    expect(find.bySemanticsLabel('Exodus, Not read yet'), findsOneWidget);

    // Tapping on a book should not trigger any dialog (read-only)
    await tester.tap(find.text('Genesis'));
    await tester.pumpAndSettle();
    expect(find.text('Mark Genesis as unread?'), findsNothing);
    expect(find.text('Complete Genesis?'), findsNothing);
  });

  testWidgets('BibleProgressPage scrolls to initialScrollToBook', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    // Use a book that is far down the list
    await tester.pumpWidget(
      MaterialApp(
        home: BibleProgressPage(
          firestore: firestore,
          auth: auth,
          initialScrollToBook: 'Revelation',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Revelation should be visible
    expect(find.text('Revelation'), findsOneWidget);
  });

  testWidgets(
    'BibleProgressPage scrolls to last checked book if no initial book',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

      // Set last checked book to Revelation
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('bible_books')
          .doc('Revelation')
          .set({'completed': true, 'timestamp': FieldValue.serverTimestamp()});

      await tester.pumpWidget(
        MaterialApp(
          home: BibleProgressPage(firestore: firestore, auth: auth),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Revelation'), findsOneWidget);
    },
  );
}
