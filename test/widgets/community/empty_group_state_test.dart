import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/pages/join_by_code_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/community/empty_group_state.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockVibrationService extends VibrationService {
  int lightImpactCalls = 0;
  @override
  Future<void> lightImpact() async {
    lightImpactCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late GroupService groupService;
  late _MockVibrationService vibrationService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
    groupService = GroupService(firestore: firestore);
    vibrationService = _MockVibrationService();
  });

  Widget createWidget() {
    return MaterialApp(
      home: Scaffold(
        body: EmptyGroupState(
          auth: auth,
          firestore: firestore,
          groupService: groupService,
          vibrationService: vibrationService,
        ),
      ),
    );
  }

  testWidgets('renders all copy and action buttons', (tester) async {
    await tester.pumpWidget(createWidget());

    expect(find.text('No one here yet'), findsOneWidget);
    expect(
      find.text('Your Circle is everyone you share a group with.'),
      findsOneWidget,
    );
    expect(find.text('Have a code?'), findsOneWidget);
    expect(find.text('Find a group'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  testWidgets('tapping Have a code navigates to JoinByCodePage',
      (tester) async {
    await tester.pumpWidget(createWidget());

    await tester.tap(find.text('Have a code?'));
    await tester.pumpAndSettle();

    expect(find.byType(JoinByCodePage), findsOneWidget);
    expect(vibrationService.lightImpactCalls, 1);
  });

  testWidgets('tapping Create a group navigates to CreatePlanPage', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget());

    await tester.tap(find.text('Create a group'));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePlanPage), findsOneWidget);
    expect(vibrationService.lightImpactCalls, 1);
  });

  testWidgets('tapping Find a group opens the public-group preview sheet', (
    tester,
  ) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Public Reading Group',
      'ownerUid': 'u2',
      'isPublic': true,
      'memberCount': 1,
    });
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('alice')
        .set({
      'uid': 'alice',
      'name': 'Alice',
      'role': 'member',
    });

    await tester.pumpWidget(createWidget());

    await tester.tap(find.text('Find a group'));
    await tester.pumpAndSettle();

    expect(find.text('Join an open group to read together.'), findsOneWidget);
    expect(find.text('Public Reading Group'), findsOneWidget);
    // Member names live behind the approval gate, so browse shows none.
    expect(find.text('Alice'), findsNothing);
    expect(vibrationService.lightImpactCalls, 1);

    await tester.tap(find.text('Public Reading Group'));
    await tester.pumpAndSettle();

    expect(find.text('Bible reading plan'), findsOneWidget);
    expect(find.text('1 member'), findsOneWidget);
    expect(find.text('Request to join'), findsOneWidget);
    expect(
      find.textContaining('names and daily progress'),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Read today'), findsNothing);
  });

  testWidgets('requesting to join creates an approval request, not a member', (
    tester,
  ) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Public Reading Group',
      'ownerUid': 'u2',
      'isPublic': true,
      'memberCount': 1,
    });

    await tester.pumpWidget(createWidget());

    await tester.tap(find.text('Find a group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Public Reading Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request to join'));
    await tester.pumpAndSettle();

    final request = await firestore
        .collection('groups')
        .doc('g1')
        .collection('joinRequests')
        .doc('u1')
        .get();
    final member = await firestore
        .collection('groups')
        .doc('g1')
        .collection('members')
        .doc('u1')
        .get();

    expect(request.exists, isTrue);
    expect(member.exists, isFalse);
  });
}
