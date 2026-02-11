import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/views/all_groups_view.dart';
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
    when(() => mockGroupService.allGroups())
        .thenAnswer((_) => Stream.value([]));
    when(() => mockGroupService.groupsForUser(any()))
        .thenAnswer((_) => Stream.value([]));
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

  testWidgets('Find Groups view renders correctly',
      (WidgetTester tester) async {
    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Find Groups'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // Search bar
    expect(find.byIcon(Icons.filter_list), findsOneWidget); // Filter button
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // Back button
  });
}
