import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/schedule_mode.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/widgets/group_preview_sheet.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stub_vibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late GroupService groupService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
    groupService = GroupService(firestore: firestore);
  });

  Group buildGroup({
    String name = 'Tuesday Evenings',
    int memberCount = 9,
    GroupPlanDraft? planConfig,
  }) {
    return Group(
      id: 'g1',
      name: name,
      ownerUid: 'owner',
      memberCount: memberCount,
      isPublic: true,
      planConfig: planConfig ??
          GroupPlanDraft(
            books: const ['Romans'],
            startRef: 'Romans 1',
            mode: ScheduleMode.chaptersPerDay,
            chaptersPerDay: 2,
            startDate: DateTime(2024, 1, 1),
            endDate: null,
            weekdays: const [1, 2, 3, 4, 5, 6, 7],
            bookBoundary: true,
            dayOverrides: const {},
          ),
    );
  }

  Widget wrapSheet(Group group) {
    return MaterialApp(
      home: Scaffold(
        body: GroupPreviewSheet(
          group: group,
          groupService: groupService,
          auth: auth,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
  }

  testWidgets('previews a public group without names or progress', (
    tester,
  ) async {
    await tester.pumpWidget(wrapSheet(buildGroup()));

    expect(find.text('Tuesday Evenings'), findsOneWidget);
    expect(find.text('Reading Romans'), findsOneWidget);
    expect(find.text('9 members'), findsOneWidget);
    expect(find.text('A member approves new readers'), findsOneWidget);
    expect(find.text('Request to join'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(
      find.textContaining('names and daily progress'),
      findsOneWidget,
    );

    // The sheet has no member avatar/name/status surface at all.
    expect(find.byIcon(Icons.person), findsNothing);
    expect(find.text('Read today'), findsNothing);
  });

  testWidgets('falls back to a reading plan label for legacy groups', (
    tester,
  ) async {
    final group = Group(
      id: 'g1',
      name: 'Legacy Readers',
      ownerUid: 'owner',
      memberCount: 3,
      isPublic: true,
    );

    await tester.pumpWidget(wrapSheet(group));

    expect(find.text('Bible reading plan'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
  });
}
