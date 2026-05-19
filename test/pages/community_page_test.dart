import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/reading_plan_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingVibrationService extends VibrationService {
  @override
  Future<void> lightImpact() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _RecordingVibrationService vibration;
  late GroupService groupService;
  late FriendService friendService;
  late ReadingPlanService readingPlanService;
  late ReadingStatusService readingStatusService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(
          uid: 'u1', displayName: 'Test User', photoURL: 'http://photo.url'),
      signedIn: true,
    );
    vibration = _RecordingVibrationService();
    groupService = GroupService(firestore: firestore);
    friendService = FriendService(firestore: firestore);
    readingPlanService = ReadingPlanService(firestore: firestore);
    readingStatusService =
        ReadingStatusService(firestore: firestore, auth: auth);
  });

  Future<void> pumpPage(WidgetTester tester, {DateTime? date}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityPage(
          auth: auth,
          firestore: firestore,
          groupService: groupService,
          friendService: friendService,
          readingPlanService: readingPlanService,
          readingStatusService: readingStatusService,
          vibrationService: vibration,
          onSendLikeNotification: (
              {required ownerUid, required likerName}) async {},
          onSendCommentNotification: (
              {required ownerUid, required commenterName}) async {},
          dateProvider: () => date ?? DateTime(2024, 1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders header with morning greeting', (tester) async {
    await pumpPage(tester, date: DateTime(2024, 1, 1, 9)); // 9 AM
    expect(find.text('Good Morning,'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('renders header with afternoon greeting', (tester) async {
    await pumpPage(tester, date: DateTime(2024, 1, 1, 14)); // 2 PM
    expect(find.text('Good Afternoon,'), findsOneWidget);
  });

  testWidgets('renders header with evening greeting', (tester) async {
    await pumpPage(tester, date: DateTime(2024, 1, 1, 19)); // 7 PM
    expect(find.text('Good Evening,'), findsOneWidget);
  });

  testWidgets('renders empty group state when no groups', (tester) async {
    await pumpPage(tester);

    expect(find.text('Group Progress'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
    expect(find.text('No active groups'), findsOneWidget);
    expect(find.text('Join a group to see progress here.'), findsOneWidget);
  });

  testWidgets('renders group progress card when group exists', (tester) async {
    // Setup group
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 1,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.now(),
      'name': 'Test User',
    });
    // Setup schedule
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2024-01-01')
        .set({
      'date': Timestamp.fromDate(DateTime(2024, 1, 1)),
      'chapters': ['Gen 1'],
    });

    await pumpPage(tester);

    expect(find.text('My Group'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Day 1'), findsOneWidget);
  });

  testWidgets('renders friends activity including self', (tester) async {
    // Setup friend
    await firestore
        .collection('users')
        .doc('u1')
        .collection('friends')
        .doc('f1')
        .set({
      'uid': 'f1',
      'status': 'accepted',
    });

    // Setup logs
    final dateKey = '2024-01-01';
    await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .set({
      'name': 'Test',
      'timestamp': Timestamp.now(),
    });
    await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('f1')
        .set({
      'name': 'Friend',
      'timestamp': Timestamp.now(),
    });

    await pumpPage(tester);

    expect(find.text('Friends Activity'), findsOneWidget);
    // Use findRichText: true for RichText content
    expect(find.text('Test', findRichText: true), findsWidgets);
    expect(find.textContaining('completed', findRichText: true), findsWidgets);
    expect(find.textContaining('Friend', findRichText: true), findsWidgets);
  });

  testWidgets('renders commented activity', (tester) async {
    final dateKey = '2024-01-01';
    await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .set({
      'name': 'Test',
      'timestamp': Timestamp.now(),
    });
    await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .collection('comments')
        .add({
      'uid': 'u1',
      'name': 'Test',
      'message': 'Great chapter',
      'timestamp': Timestamp.now(),
    });

    await pumpPage(tester);

    expect(find.textContaining('commented on', findRichText: true),
        findsOneWidget);
    expect(find.text('"Great chapter"'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
  });
}
