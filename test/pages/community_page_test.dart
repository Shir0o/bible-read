import 'package:bible_read/pages/community_page.dart';
import 'package:bible_read/services/group_service.dart';
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
  late ReadingStatusService readingStatusService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'u1',
        displayName: 'Test User',
        photoURL: 'http://photo.url',
      ),
      signedIn: true,
    );
    vibration = _RecordingVibrationService();
    groupService = GroupService(firestore: firestore);
    readingStatusService = ReadingStatusService(
      firestore: firestore,
      auth: auth,
    );
  });

  Future<void> pumpPage(WidgetTester tester, {DateTime? date}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CommunityPage(
          auth: auth,
          firestore: firestore,
          groupService: groupService,
          readingStatusService: readingStatusService,
          vibrationService: vibration,
          dateProvider: () => date ?? DateTime(2024, 1, 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders header with eyebrow and title', (tester) async {
    await pumpPage(tester, date: DateTime(2024, 1, 1, 9)); // 9 AM
    expect(find.text('TOGETHER'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
  });

  testWidgets('renders empty group state when no groups', (tester) async {
    await pumpPage(tester);

    expect(find.text('No active groups'), findsOneWidget);
    expect(find.text('Join a group to see progress here.'), findsOneWidget);
  });

  testWidgets('renders people-first with groups beneath, no reading hero', (
    tester,
  ) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'My Group',
      'ownerUid': 'u1',
      'memberCount': 2,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .set({
      'uid': 'u1',
      'role': 'owner',
      'name': 'Test User',
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u2')
        .set({
      'uid': 'u2',
      'role': 'member',
      'name': 'Bea',
    });
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

    // The reader's own row leads the people list.
    expect(find.text('You'), findsOneWidget);
    // Co-members render from Group membership.
    expect(find.text('Bea'), findsOneWidget);

    // Groups are a section beneath the people, and the duplicate reading
    // hero is gone from this screen.
    expect(find.text('Your groups'), findsOneWidget);
    expect(find.text('My Group'), findsWidgets);
    expect(find.text("THE COMMUNITY'S READING"), findsNothing);
    expect(find.text('Read with the community'), findsNothing);

    // The dead "Manage" passthrough is gone with the hero.
    expect(find.text('Manage'), findsNothing);
  });
}