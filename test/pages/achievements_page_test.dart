import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/achievements_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders achievements from Firestore', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('firstReader')
        .set({
      'title': 'First Reader',
      'type': 'first',
      'dateUnlocked': Timestamp.fromDate(DateTime(2025, 1, 1)),
    });

    await tester.pumpWidget(MaterialApp(
      home: AchievementsPage(firestore: firestore, auth: auth),
    ));
    await tester.pumpAndSettle();

    expect(find.text('First Reader'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
