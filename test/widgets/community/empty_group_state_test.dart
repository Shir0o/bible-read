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

  testWidgets('tapping Find a group opens the sheet', (tester) async {
    await firestore.collection('groups').doc('g1').set({
      'name': 'Public Reading Group',
      'ownerUid': 'u2',
      'isPublic': true,
      'memberCount': 1,
    });

    await tester.pumpWidget(createWidget());

    await tester.tap(find.text('Find a group'));
    await tester.pumpAndSettle();

    expect(find.text('Join an open group to read together.'), findsOneWidget);
    expect(find.text('Public Reading Group'), findsOneWidget);
    expect(vibrationService.lightImpactCalls, 1);
  });
}
