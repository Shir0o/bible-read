import 'package:bible_read/models/circle_member.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/nudge_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/friend_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ADR-0012: Unfriending is silent, and the copy has to say whether the person
// leaves the Circle or stays because of a shared Group.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late FriendService friendService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    friendService = FriendService(
      firestore: firestore,
      unfriendFn: (_) async {},
    );
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<String> sharedGroups,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFriendSheet(
                context,
                friend: CircleMember(
                  uid: 'mei',
                  name: 'Mei',
                  groupIds: sharedGroups.toSet(),
                  isFriend: true,
                  friendSince: DateTime(2026, 10, 3),
                ),
                sharedGroupNames: sharedGroups,
                shownUpDateKeys: const {'2026-10-18', '2026-10-17'},
                reading: 'John',
                friendService: friendService,
                nudgeService: NudgeService(firestore: firestore),
                vibrationService: const VibrationService(),
                myUid: 'me',
                myName: 'Me',
                today: DateTime(2026, 10, 18),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('says a Friend without a shared Group will leave the Circle',
      (tester) async {
    await pumpSheet(tester, sharedGroups: const []);

    expect(find.text('Mei'), findsOneWidget);
    expect(find.text('Friend'), findsOneWidget);
    expect(find.text('since 3 October'), findsOneWidget);
    expect(find.text('Shown up 2 of 7 days · Reading John'), findsOneWidget);
    expect(
      find.text(
        'Mei won’t be told. You don’t share a group, so they’ll leave your '
        'Circle.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('says a Friend with a shared Group stays in the Circle',
      (tester) async {
    await pumpSheet(tester, sharedGroups: const ['Morning Crew']);

    expect(
      find.text(
        'Mei won’t be told. You share Morning Crew, so they’ll stay in your '
        'Circle.',
      ),
      findsOneWidget,
    );
  });
}
