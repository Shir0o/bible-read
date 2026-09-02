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
import 'package:bible_read/widgets/group_plan_keys.dart';
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
    auth = MockFirebaseAuth();
    vibrationService = MockVibrationService();
    ErrorLogger.muteForTest = true;
    when(() => vibrationService.lightImpact()).thenAnswer((_) async {});
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(
      1080,
      2400,
    ); // Set a large mobile screen size
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

  testWidgets('Frequency presets fire haptic feedback and update selection', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);

    await pumpPage(tester);

    // The shared form exposes the Daily / Weekdays presets as keys.
    final weekdaysChip = find.byKey(GroupPlanKeys.weekdayPreset('Weekdays'));
    expect(weekdaysChip, findsOneWidget);
    expect(
      find.byKey(GroupPlanKeys.weekdayPreset('Daily')),
      findsOneWidget,
    );

    final scrollableFinder = find.byType(Scrollable).first;
    final ScrollableState scrollable = tester.state(scrollableFinder);
    await scrollable.position.ensureVisible(
      tester.renderObject(weekdaysChip),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();

    await tester.tap(weekdaysChip);
    await tester.pumpAndSettle();

    verify(() => vibrationService.lightImpact()).called(greaterThan(0));

    // After tapping Weekdays, the form's weekday chips show Mon–Fri only.
    for (var i = 1; i <= 7; i++) {
      // Walk up to find the Semantics widget above the InkWell.
      final semantics = tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.byKey(GroupPlanKeys.weekday(i)),
              matching: find.byType(Semantics),
            ),
          )
          .first;
      final expectedSelected = i >= 1 && i <= 5;
      final label = expectedSelected ? 'selected' : 'deselected';
      expect(
        semantics.properties.selected,
        expectedSelected,
        reason: 'Weekday $i should be $label',
      );
    }
  });
}
