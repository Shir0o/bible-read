import 'package:bible_read/models/group.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/views/all_groups_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

class MockGroupService extends Mock implements GroupService {}

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  late MockGroupService mockGroupService;
  late MockFirebaseAuth mockAuth;
  late MockVibrationService mockVibrationService;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    mockGroupService = MockGroupService();
    // Initialize with a user
    final user = MockUser(
      isAnonymous: false,
      uid: 'test_uid',
      email: 'test@example.com',
      displayName: 'Test User',
    );
    mockAuth = MockFirebaseAuth(mockUser: user, signedIn: true);
    mockVibrationService = MockVibrationService();
    fakeFirestore = FakeFirebaseFirestore();

    // Stub GroupService methods
    when(() => mockGroupService.allGroups()).thenAnswer((_) => Stream.value([]));
    when(() => mockGroupService.groupsForUser(any())).thenAnswer((_) => Stream.value([]));
    when(() => mockGroupService.firestore).thenReturn(fakeFirestore);
    // Stub fixMemberProgressSummariesForUser as it is called in init
    when(() => mockGroupService.fixMemberProgressSummariesForUser(any()))
        .thenAnswer((_) async {});
    when(() => mockVibrationService.lightImpact()).thenAnswer((_) async {});
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: AllGroupsView(
        groupService: mockGroupService,
        auth: mockAuth,
        vibrationService: mockVibrationService,
      ),
    );
  }

  testWidgets('Create Group dialog UX flow', (WidgetTester tester) async {
    // Arrange
    when(() => mockGroupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => 'new_group_id');

    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle(); // Wait for streams

    // Tap FAB to open dialog
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Assert Dialog Open
    // Use descendent to ensure we are looking at the dialog title, or just check existence
    // Since "Create Group" is also on the empty state button, we expect 2 or need to be specific.
    // Let's verify the AlertDialog exists.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Create Group')), findsOneWidget);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // The "Create" button in the dialog
    final createButtonFinder = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Create'));
    expect(createButtonFinder, findsOneWidget);

    // Initial State: Create button should be disabled
    final TextButton createButton = tester.widget(createButtonFinder);
    // In current implementation, it is enabled (onPressed is not null).
    // The test expects it to be disabled (null).
    expect(createButton.onPressed, isNull);

    // Enter text
    await tester.enterText(find.byType(TextField), 'Test Group');
    await tester.pump(); // Rebuild for State changes

    // Verify Create button is enabled
    final createButtonEnabled = tester.widget<TextButton>(createButtonFinder);
    expect(createButtonEnabled.onPressed, isNotNull);

    // Tap Create
    await tester.tap(createButtonFinder);
    await tester.pumpAndSettle(); // Wait for dialog to close and async operations

    // Verify createGroup called
    verify(() => mockGroupService.createGroup(
          ownerUid: 'test_uid',
          name: 'Test Group',
        )).called(1);

    // Verify vibration
    verify(() => mockVibrationService.lightImpact()).called(greaterThan(0));
  });

  testWidgets('Create Group button disabled when empty', (WidgetTester tester) async {
     // Arrange
    when(() => mockGroupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        )).thenAnswer((_) async => 'new_group_id');

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Verify disabled initially
    final createButtonFinder = find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Create'));
    final TextButton createButton = tester.widget(createButtonFinder);
    expect(createButton.onPressed, isNull);

    // Enter text
    await tester.enterText(find.byType(TextField), '  ');
    await tester.pump();

    // Still disabled for whitespace
    final createButtonWhitespace = tester.widget<TextButton>(createButtonFinder);
    expect(createButtonWhitespace.onPressed, isNull);
  });

  testWidgets('Create Group dialog cancels correctly', (WidgetTester tester) async {
    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Tap Cancel
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Assert Dialog Closed
    expect(find.byType(AlertDialog), findsNothing);
    verifyNever(() => mockGroupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        ));
  });
}
