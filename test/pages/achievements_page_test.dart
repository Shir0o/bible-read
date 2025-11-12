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

  testWidgets('shows locked achievements when none unlocked', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: AchievementsPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    final listFinder = find.byType(ListView);
    final listView = tester.widget<ListView>(listFinder);
    final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.estimatedChildCount, allAchievements.length);

    expect(find.byIcon(Icons.lock), findsWidgets);

    await tester.dragUntilVisible(
      find.text('Complete Genesis'),
      listFinder,
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

    final listFinder = find.byType(ListView);
    final firstReaderItem =
        find.widgetWithText(AchievementListItem, 'First Reader');
    expect(
      find.descendant(
        of: firstReaderItem,
        matching: find.byIcon(Icons.lock),
      ),
      findsNothing,
    );

    await tester.dragUntilVisible(
      find.text('Complete Genesis'),
      listFinder,
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
