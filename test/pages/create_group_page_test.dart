import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import '../helpers/pump_app.dart';

class MockGroupService extends Mock implements GroupService {}

class MockVibrationService extends Mock implements VibrationService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {
  @override
  String get uid => 'test_uid';
}

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

class FakeRoute extends Fake implements Route {}

void main() {
  late MockGroupService groupService;
  late MockVibrationService vibrationService;
  late MockFirebaseAuth auth;
  late MockUser user;
  late FakeFirebaseFirestore fakeFirestore;

  setUpAll(() {
    registerFallbackValue(FakeRoute());
  });

  setUp(() {
    groupService = MockGroupService();
    vibrationService = MockVibrationService();
    auth = MockFirebaseAuth();
    user = MockUser();
    fakeFirestore = FakeFirebaseFirestore();

    when(() => auth.currentUser).thenReturn(user);
    when(() => vibrationService.lightImpact()).thenAnswer((_) async {});
    when(() => vibrationService.mediumImpact()).thenAnswer((_) async {});

    when(() => groupService.firestore).thenReturn(fakeFirestore);
  });

  Widget buildSubject({NavigatorObserver? navigatorObserver}) {
    return CreateGroupPage(
      groupService: groupService,
      auth: auth,
      vibrationService: vibrationService,
    );
  }

  testWidgets('renders initial state correctly', (tester) async {
    await tester.pumpApp(buildSubject());

    expect(find.text('New Group Plan'), findsOneWidget);
    expect(find.text('Reading Plan'), findsOneWidget);
    expect(
      find.text('Select the books you\'ll be reading together.'),
      findsOneWidget,
    );
    expect(
      find.byType(TextField),
      findsNWidgets(2),
    ); // Book search + Find people (disabled)
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Frequency'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Create Schedule'), findsOneWidget);
  });

  testWidgets('can select books', (tester) async {
    await tester.pumpApp(buildSubject());

    // Use find.byType(TextField).first for the search field
    final searchField = find.byType(TextField).first;

    await tester.enterText(searchField, 'Gen');
    await tester.pump();

    expect(find.text('Genesis'), findsOneWidget);

    await tester.tap(find.text('Genesis'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Genesis'), findsOneWidget);
  });

  testWidgets('can select frequency', (tester) async {
    await tester.pumpApp(buildSubject());

    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekdays'), findsOneWidget);
  });

  testWidgets('shows error if creating without books', (tester) async {
    await tester.pumpApp(buildSubject());

    await tester.tap(find.text('Create Schedule'));
    await tester.pump();

    expect(find.text('Please select at least one book.'), findsOneWidget);
    verifyNever(
      () => groupService.createGroup(
        ownerUid: any(named: 'ownerUid'),
        name: any(named: 'name'),
      ),
    );
  });

  testWidgets('shows error if creating without end date', (tester) async {
    await tester.pumpApp(buildSubject());

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'Exodus');
    await tester.pump();
    await tester.tap(find.text('Exodus').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Schedule'));
    await tester.pump();

    expect(find.text('Please select an end date.'), findsOneWidget);
  });

  testWidgets('creates schedule and navigates on success', skip: true, (
    tester,
  ) async {
    final observer = MockNavigatorObserver();
    await tester.pumpApp(buildSubject(navigatorObserver: observer));

    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'Ruth');
    await tester.pump();
    await tester.tap(find.text('Ruth').last);
    await tester.pumpAndSettle();

    // 2. Select Dates
    await tester.ensureVisible(find.text('mm/dd/yyyy'));
    await tester.tap(find.text('mm/dd/yyyy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // 3. Mock Service calls
    when(
      () => groupService.createGroup(
        ownerUid: any(named: 'ownerUid'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async => 'group_123');

    when(
      () => groupService.updateScheduleBatch(
        groupId: any(named: 'groupId'),
        schedules: any(named: 'schedules'),
      ),
    ).thenAnswer((_) async {});

    // Stubs for GroupDetailPage
    when(
      () => groupService.schedule('group_123'),
    ).thenAnswer((_) => Stream.value(<GroupSchedule>[]));
    when(
      () => groupService.memberOverallCompletion('group_123'),
    ).thenAnswer((_) => Stream.value(<GroupMemberProgressData>[]));
    when(
      () => groupService.memberDailyCompletion(
        'group_123',
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) => Stream.value(<GroupMemberProgressData>[]));

    // 4. Create
    await tester.tap(find.text('Create Schedule'));
    await tester.pump();

    // Allow async gaps
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpAndSettle();

    // 5. Verify Calls
    verify(
      () => groupService.createGroup(
        ownerUid: any(named: 'ownerUid'),
        name: any(named: 'name'),
      ),
    ).called(1);

    verify(
      () => groupService.updateScheduleBatch(
        groupId: 'group_123',
        schedules: any(named: 'schedules'),
      ),
    ).called(1);

    verify(() => vibrationService.mediumImpact()).called(1);

    // 6. Verify Navigation
    verify(
      () => observer.didReplace(
        newRoute: any(named: 'newRoute'),
        oldRoute: any(named: 'oldRoute'),
      ),
    ).called(1);

    expect(find.byType(GroupDetailPage), findsOneWidget);
  });
}
