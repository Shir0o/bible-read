import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/friend_streak_link.dart';
import 'package:bible_read/pages/friendly_streak_page.dart';
import 'package:bible_read/services/friendly_streak_service.dart';

void main() {
  testWidgets('renders summary banner and partner lists', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await _writeSummaryDoc(firestore);
    final summary = FriendlyStreakLinksSummary(
      activeLinks: [
        _testLink(uid: 'p1', name: 'Alice', streak: 5),
        _testLink(uid: 'p2', name: 'Bob', streak: 3),
      ],
      pendingLinks: [
        _testLink(
            uid: 'p3',
            name: 'Charlie',
            streak: 0,
            status: FriendStreakStatus.pending),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FriendlyStreakPage(
          firestore: firestore,
          auth: auth,
          friendlyStreakService: _StubFriendlyStreakService(summary),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Friendly streaks'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Active partners'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Active partners'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pending invites'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pending invites'), findsOneWidget);
    expect(find.text('Active partners: 2'), findsOneWidget);

    expect(find.text('Streak with Alice: 5 days'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob').last);
    await tester.pumpAndSettle();
    expect(find.text('Streak with Bob: 3 days'), findsOneWidget);
  });

  testWidgets('shows invite call to action when no partners', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await _writeSummaryDoc(firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: FriendlyStreakPage(
          firestore: firestore,
          auth: auth,
          friendlyStreakService:
              _StubFriendlyStreakService(FriendlyStreakLinksSummary.empty),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No streak partners yet. Invite a friend to share progress.'),
      findsWidgets,
    );
    expect(find.text('Invite a friend'), findsWidgets);
  });

  testWidgets('shows error notice when friendly streak load fails',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await _writeSummaryDoc(firestore);

    await tester.pumpWidget(
      MaterialApp(
        home: FriendlyStreakPage(
          firestore: firestore,
          auth: auth,
          friendlyStreakService: _ThrowingFriendlyStreakService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
          "We couldn't refresh friendly streaks. Pull down to try again."),
      findsOneWidget,
    );
  });
}

Future<void> _writeSummaryDoc(FakeFirebaseFirestore firestore) async {
  await firestore
      .collection('users')
      .doc('u1')
      .collection('summary')
      .doc('data')
      .set({
    'streak': 4,
    'longestStreak': 9,
    'totalReadDays': 30,
    'graceCreditsMonth': '2024-04',
    'graceCreditsAvailable': 1,
  });
}

class _StubFriendlyStreakService extends FriendlyStreakService {
  _StubFriendlyStreakService(this.summary)
      : super(firestore: FakeFirebaseFirestore());

  final FriendlyStreakLinksSummary summary;

  @override
  Future<FriendlyStreakLinksSummary> fetchLinks(String uid) async {
    return summary;
  }
}

class _ThrowingFriendlyStreakService extends FriendlyStreakService {
  _ThrowingFriendlyStreakService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<FriendlyStreakLinksSummary> fetchLinks(String uid) async {
    throw Exception('network error');
  }
}

FriendStreakLink _testLink({
  required String uid,
  required String name,
  required int streak,
  FriendStreakStatus status = FriendStreakStatus.active,
}) {
  final now = DateTime(2024);
  return FriendStreakLink(
    partnerUid: uid,
    partnerName: name,
    initiatedBy: 'u1',
    status: status,
    currentStreak: streak,
    lastUserCovered: now,
    lastPartnerCovered: now,
    createdAt: now,
    updatedAt: now,
    ownerUid: 'u1',
  );
}
