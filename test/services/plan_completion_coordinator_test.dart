import 'package:bible_read/services/plan_completion_coordinator.dart';
import 'package:bible_read/services/read_log_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'coupling a plan reading to the habit refreshes the stored streak',
      (tester) async {
    final user = MockUser(uid: 'u1', displayName: 'Reader');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final firestore = FakeFirebaseFirestore();
    final userRef = firestore.collection('users').doc('u1');
    await userRef
        .collection('settings')
        .doc('general')
        .set({'autoMarkPlanRead': true, 'syncPromptAnswered': true});

    // Ten consecutive days already shown up, but the stored streak is stale
    // because the last summary recompute happened when it was 1.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var i = 1; i <= 10; i++) {
      final key = ReadLogService.dateKeyFor(
        DateTime(today.year, today.month, today.day - i),
      );
      await userRef.collection('reading').doc(key).set({'read': true});
    }
    await userRef.collection('summary').doc('data').set({'streak': 1});

    final coordinator = PlanCompletionCoordinator(
      firestore: firestore,
      readingStatusService: ReadingStatusService(
        firestore: firestore,
        auth: auth,
      ),
    );

    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));

    final coupled = await coordinator.maybeCoupleHabit(
      context: context,
      user: user,
    );

    expect(coupled, isTrue);
    final summary = await userRef.collection('summary').doc('data').get();
    expect(summary.data()?['streak'], 11);
  });
}
