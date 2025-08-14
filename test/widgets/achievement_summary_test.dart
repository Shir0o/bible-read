import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/widgets/achievement_summary.dart';
import 'package:bible_read/widgets/success_animation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('returns empty widget when no user', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
      MaterialApp(home: AchievementSummary(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('shows count and badge when achievements exist', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('a1')
        .set({
      'title': 'First',
      'type': 'test',
      'dateUnlocked': Timestamp.fromDate(DateTime(2023)),
    });

    await tester.pumpWidget(
      MaterialApp(home: AchievementSummary(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('shows message when no achievements', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: AchievementSummary(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No achievements yet'), findsOneWidget);
  });

  testWidgets('shows success animation when achievement unlocked',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: AchievementSummary(firestore: firestore, auth: auth)),
    );
    await tester.pump();

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('a1')
        .set({
      'title': 'First',
      'type': 'test',
      'dateUnlocked': Timestamp.fromDate(DateTime(2023)),
    });

    await tester.pump();
    await tester.pump();

    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });
  });
}
