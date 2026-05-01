import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/models/group.dart';
import 'package:bible_read/pages/edit_group_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:mocktail/mocktail.dart';

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late Group group;
  late MockVibrationService vibrationService;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
    ErrorLogger.muteForTest = true;
    vibrationService = MockVibrationService();
    when(() => vibrationService.lightImpact()).thenAnswer((_) async {});
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize =
        const Size(1080, 2400); // Set a large mobile screen size
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      MaterialApp(
        home: EditGroupPage(
          group: group,
          groupService: GroupService(firestore: firestore),
          auth: auth,
          vibrationService: vibrationService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Frequency presets fire haptic feedback and update selection',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester);

    final scrollableFinder = find.byType(Scrollable).first;
    final frequencyFinder = find.text('Frequency');
    await tester.scrollUntilVisible(frequencyFinder, 500,
        scrollable: scrollableFinder);
    expect(frequencyFinder, findsOneWidget);

    final weekdaysChip = find.widgetWithText(ActionChip, 'Weekdays');
    expect(weekdaysChip, findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Daily'), findsOneWidget);

    final ScrollableState scrollable = tester.state(scrollableFinder);
    await scrollable.position.ensureVisible(
      tester.renderObject(weekdaysChip),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();

    await tester.tap(weekdaysChip);
    await tester.pumpAndSettle();

    verify(() => vibrationService.lightImpact()).called(1);

    // After tapping Weekdays, exactly 5 of the 7 day ChoiceChips
    // (Mon–Fri) should be selected.
    final selectedDayChips = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((c) => c.selected)
        .length;
    expect(selectedDayChips, 5,
        reason: 'Weekdays preset should select Mon–Fri only');
  });
}
