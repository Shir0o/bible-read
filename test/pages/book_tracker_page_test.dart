import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/book_tracker_page.dart';
import 'package:bible_read/models/achievement_definition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BookTrackerPage shows list of books', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BookTrackerPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Genesis'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text('Revelation'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsWidgets);
  });

  testWidgets('BookTrackerPage shows confirmation dialog when checking a book',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BookTrackerPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // Tap Genesis
    await tester.tap(find.text('Genesis'));
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('Complete Genesis?'), findsOneWidget);
    expect(
      find.text(
          'Are you sure you want to mark Genesis as completed? This cannot be undone.'),
      findsOneWidget,
    );

    // Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Verify dialog closed and checkbox still unchecked (no achievement)
    expect(find.text('Complete Genesis?'), findsNothing);
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(AchievementDefinition.bookAchievementId('Genesis'))
        .get();
    expect(doc.exists, isFalse);
  });

  testWidgets('BookTrackerPage unlocks achievement on confirmation',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BookTrackerPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // Tap Genesis
    await tester.tap(find.text('Genesis'));
    await tester.pumpAndSettle();

    // Confirm
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Verify achievement written
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(AchievementDefinition.bookAchievementId('Genesis'))
        .get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['title'], 'Complete Genesis');
  });

  testWidgets('BookTrackerPage disables checkbox for unlocked books',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    // Pre-unlock Genesis
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(AchievementDefinition.bookAchievementId('Genesis'))
        .set({'title': 'Complete Genesis'});

    await tester.pumpWidget(
      MaterialApp(home: BookTrackerPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    final checkboxFinder = find.descendant(
      of: find.widgetWithText(Card, 'Genesis'),
      matching: find.byType(CheckboxListTile),
    );
    final checkbox = tester.widget<CheckboxListTile>(checkboxFinder);

    expect(checkbox.value, isTrue);
    expect(checkbox.onChanged, isNull); // Disabled
  });
}
