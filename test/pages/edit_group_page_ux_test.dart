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
    tester.view.physicalSize = const Size(1080, 2400); // Set a large mobile screen size
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

  testWidgets('Frequency cards have correct semantics and haptic feedback', (tester) async {
    final handle = tester.ensureSemantics();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Setup initial data (empty schedule so defaults to daily)
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester);

    // Scroll to Frequency section
    final scrollableFinder = find.byType(Scrollable).first;
    final frequencyFinder = find.text('Frequency');
    await tester.scrollUntilVisible(frequencyFinder, 500, scrollable: scrollableFinder);

    expect(frequencyFinder, findsOneWidget);

    // Find the cards by semantics label
    final dailyCard = find.bySemanticsLabel(RegExp(r'Daily, Every single day'));
    final weekdaysCard = find.bySemanticsLabel(RegExp(r'Weekdays, Mon - Fri only'));

    expect(dailyCard, findsOneWidget);

    // Ensure visible before interacting, centering it to avoid bottom button
    await tester.scrollUntilVisible(weekdaysCard, 500, scrollable: scrollableFinder);

    // Manually ensure visible with alignment to center it
    final ScrollableState scrollable = tester.state(scrollableFinder);
    await scrollable.position.ensureVisible(
      tester.renderObject(weekdaysCard),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();

    // Verify Semantics for "Daily" (should be selected/checked)
    final dailySemantics = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label?.contains('Daily') == true &&
               widget.properties.checked == true &&
               widget.properties.inMutuallyExclusiveGroup == true;
      }
      return false;
    });

    expect(dailySemantics, findsOneWidget, reason: 'Daily card should have correct semantics (checked)');

    // Verify Semantics for "Weekdays" (should be unchecked)
    final weekdaysSemantics = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label?.contains('Weekdays') == true &&
               widget.properties.label?.contains('Mon - Fri only') == true &&
               widget.properties.checked == false &&
               widget.properties.inMutuallyExclusiveGroup == true;
      }
      return false;
    });

    expect(weekdaysSemantics, findsOneWidget, reason: 'Weekdays card should have correct semantics (unchecked)');

    // Test Interaction and Haptics
    await tester.tap(weekdaysCard);
    await tester.pump();

    verify(() => vibrationService.lightImpact()).called(1);

    // Verify state change in semantics
    // Now Weekdays should be checked
    final weekdaysSemanticsChecked = find.byWidgetPredicate((widget) {
      if (widget is Semantics) {
        return widget.properties.label?.contains('Weekdays') == true &&
               widget.properties.checked == true;
      }
      return false;
    });
    expect(weekdaysSemanticsChecked, findsOneWidget);
    handle.dispose();
  });
}
