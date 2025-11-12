import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/achievements_page.dart';
import 'package:bible_read/models/achievement_definition.dart';
import 'package:bible_read/widgets/achievement_list_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows locked achievements grouped by category', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: AchievementsPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    final featuredListFinder =
        find.byKey(const ValueKey('achievementsList_featured'));
    final featuredListView = tester.widget<ListView>(featuredListFinder);
    final featuredDelegate =
        featuredListView.childrenDelegate as SliverChildBuilderDelegate;
    expect(
      featuredDelegate.estimatedChildCount,
      achievementsForCategory(AchievementCategory.featured).length,
    );

    expect(find.byIcon(Icons.lock), findsWidgets);

    await tester.tap(find.text(AchievementCategory.book.label));
    await tester.pumpAndSettle();

    final bookListFinder = find.byKey(const ValueKey('achievementsList_book'));
    await tester.dragUntilVisible(
      find.text('Complete Genesis'),
      bookListFinder,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(AchievementListItem, 'Complete Genesis'),
        matching: find.byIcon(Icons.lock),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unlocked achievements omit lock icon', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('firstReader')
        .set({
      'title': 'First Reader',
      'type': 'first',
      'dateUnlocked': Timestamp.fromDate(DateTime(2025)),
    });

    await tester.pumpWidget(
      MaterialApp(home: AchievementsPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    final firstReaderItem =
        find.widgetWithText(AchievementListItem, 'First Reader');
    expect(
      find.descendant(
        of: firstReaderItem,
        matching: find.byIcon(Icons.lock),
      ),
      findsNothing,
    );

    await tester.tap(find.text(AchievementCategory.book.label));
    await tester.pumpAndSettle();

    final bookListFinder = find.byKey(const ValueKey('achievementsList_book'));
    await tester.dragUntilVisible(
      find.text('Complete Genesis'),
      bookListFinder,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.widgetWithText(AchievementListItem, 'Complete Genesis'),
        matching: find.byIcon(Icons.lock),
      ),
      findsOneWidget,
    );
  });
}
