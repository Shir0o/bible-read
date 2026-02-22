import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/bible_progress_page.dart';
import 'package:bible_read/models/achievement_definition.dart';

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
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gen'), findsOneWidget); // Abbreviation
    expect(find.text('PENTATEUCH'), findsOneWidget); // Category header

    // Scroll down to find Revelation
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text('Rev'), findsOneWidget);
  });

  testWidgets('BibleProgressPage marks book as read', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // Tap Genesis (Gen)
    await tester.tap(find.text('Gen'));
    await tester.pumpAndSettle();

    // Verify dialog
    expect(find.text('Complete Genesis?'), findsOneWidget);

    // Confirm
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Verify achievement
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(AchievementDefinition.bookAchievementId('Genesis'))
        .get();
    expect(doc.exists, isTrue);
  });

  testWidgets('BibleProgressPage unmarks book as read', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    // Pre-unlock Genesis
    final achievementId = AchievementDefinition.bookAchievementId('Genesis');
    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(achievementId)
        .set({'title': 'Complete Genesis'});

    await tester.pumpWidget(
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // Tap Genesis (Gen)
    await tester.tap(find.text('Gen'));
    await tester.pumpAndSettle();

    // Verify dialog for unmarking
    expect(find.text('Mark Genesis as unread?'), findsOneWidget);

    // Confirm
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Verify achievement removed
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc(achievementId)
        .get();
    expect(doc.exists, isFalse);
  });

  testWidgets('BibleProgressPage book items have correct semantics',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // Verify initial semantics for Genesis
    final genesisFinder = find.bySemanticsLabel('Genesis, Not completed');
    expect(genesisFinder, findsOneWidget);

    // Verify tap action
    expect(
        tester
            .getSemantics(genesisFinder)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue);

    // Tap to mark as read
    await tester.tap(genesisFinder);
    await tester.pumpAndSettle();

    // Confirm dialog
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Verify updated semantics
    expect(
      find.bySemanticsLabel('Genesis, Completed'),
      findsOneWidget,
    );
  });
}
