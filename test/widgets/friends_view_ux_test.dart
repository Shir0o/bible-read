import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/views/friends_view.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFriendService extends Mock implements FriendService {}

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  late MockFriendService friendService;
  late MockFirebaseAuth auth;
  late MockVibrationService vibrationService;

  setUp(() {
    friendService = MockFriendService();
    auth = MockFirebaseAuth(signedIn: true);
    vibrationService = MockVibrationService();

    when(
      () => friendService.nudgedToday(any()),
    ).thenAnswer((_) => Stream.value({}));
    when(
      () => friendService.pendingRequests(any()),
    ).thenAnswer((_) => Stream.value(const []));
    when(
      () => friendService.readTodayUids(
        uid: any(named: 'uid'),
        friendUids: any(named: 'friendUids'),
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) => Stream.value({}));
  });

  testWidgets('FriendsView UX: List items should not be tappable (no ripple)', (
    tester,
  ) async {
    final friends = [const Friend(uid: 'f1', name: 'Alice')];
    when(
      () => friendService.friends(any()),
    ).thenAnswer((_) => Stream.value(friends));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendsView(
            friendService: friendService,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find the friend-row Card (the requests entry card is also a Card, so
    // target the one that renders the friend's name).
    final cardFinder = find.ancestor(
      of: find.text('Alice'),
      matching: find.byType(Card),
    );
    expect(cardFinder, findsOneWidget);

    // Verify Card does NOT contain an InkWell as a direct child (or close
    // descendant).
    final card = tester.widget<Card>(cardFinder.first);
    final child = card.child;

    // CommonStyles.buildTappableCard puts InkWell directly inside Card.
    // CommonStyles.buildCard puts Padding directly inside Card.
    // We expect Padding (meaning no ripple on the card itself).
    expect(
      child,
      isA<Padding>(),
      reason: 'Card child should be Padding, not InkWell',
    );
    expect(
      child,
      isNot(isA<InkWell>()),
      reason: 'Card child should NOT be InkWell',
    );
  });

  testWidgets(
      'FriendsView UX: shows a Nudge chip for friends who have not '
      'read today', (tester) async {
    final friends = [const Friend(uid: 'f1', name: 'Alice')];
    when(
      () => friendService.friends(any()),
    ).thenAnswer((_) => Stream.value(friends));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendsView(
            friendService: friendService,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nudge'), findsOneWidget);
    expect(find.text('Not yet today'), findsOneWidget);
  });
}
