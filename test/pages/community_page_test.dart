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

    expect(find.text('No one here yet'), findsOneWidget);
    expect(
      find.text('Your Circle is everyone you share a group with.'),
      findsOneWidget,
    );
    expect(find.text('Have a code?'), findsOneWidget);
    expect(find.text('Find a group'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  testWidgets('renders people-first with no groups beneath, no reading hero', (
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

    // "Your groups" section is removed; groups exist only as filter chips.
    expect(find.text('Your groups'), findsNothing);
    expect(find.text('My Group'), findsOneWidget);
    expect(find.text("THE COMMUNITY'S READING"), findsNothing);
    expect(find.text('Read with the community'), findsNothing);

    // The dead "Manage" passthrough is gone with the hero.
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('filter chips have shrinkWrap and centered label',
      (tester) async {
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

    await pumpPage(tester);

    final everyoneChipFinder = find.widgetWithText(FilterChip, 'Everyone');
    expect(everyoneChipFinder, findsOneWidget);
    final filterChip = tester.widget<FilterChip>(everyoneChipFinder);
    expect(filterChip.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);
    expect(filterChip.padding, EdgeInsets.zero);

    final chipBox = tester.renderObject<RenderBox>(everyoneChipFinder);
    final textBox = tester.renderObject<RenderBox>(find.text('Everyone'));
    final chipTop = chipBox.localToGlobal(Offset.zero).dy;
    final textTop = textBox.localToGlobal(Offset.zero).dy;
    final chipBottom = chipTop + chipBox.size.height;
    final textBottom = textTop + textBox.size.height;

    final topDiff = (textTop - chipTop).abs();
    final bottomDiff = (chipBottom - textBottom).abs();
    expect((topDiff - bottomDiff).abs(), lessThanOrEqualTo(1.0));
  });
}
