import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/achievement_summary.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import '../helpers/pump_golden.dart';

void main() {
  group('AchievementSummary Golden Test', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockUser user;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      user = MockUser(uid: 'u1');
      auth = MockFirebaseAuth(mockUser: user);
    });

    testWidgets('AchievementSummary - Empty State', (tester) async {
      await tester.pumpGolden(
        AchievementSummary(
          firestore: firestore,
          auth: auth,
        ),
        brightness: Brightness.light,
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AchievementSummary),
        matchesGoldenFile('goldens/achievement_summary_empty.png'),
      );
    });

    testWidgets('AchievementSummary - Populated - Light', (tester) async {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .doc('streak7')
          .set({
        'title': '7-Day Streak',
        'type': 'streak',
        'dateUnlocked': DateTime(2023, 1, 1),
      });

      await tester.pumpGolden(
        AchievementSummary(
          firestore: firestore,
          auth: auth,
        ),
        brightness: Brightness.light,
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AchievementSummary),
        matchesGoldenFile('goldens/achievement_summary_light.png'),
      );
    });

    testWidgets('AchievementSummary - Populated - Dark', (tester) async {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .doc('streak7')
          .set({
        'title': '7-Day Streak',
        'type': 'streak',
        'dateUnlocked': DateTime(2023, 1, 1),
      });

       await tester.pumpGolden(
        AchievementSummary(
          firestore: firestore,
          auth: auth,
        ),
        brightness: Brightness.dark,
      );

      await tester.pumpAndSettle();

      await expectLater(
        find.byType(AchievementSummary),
        matchesGoldenFile('goldens/achievement_summary_dark.png'),
      );
    });
  });
}
