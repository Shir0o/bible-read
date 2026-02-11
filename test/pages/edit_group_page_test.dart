import 'package:cloud_firestore/cloud_firestore.dart';
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

class FakeVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(id: 'g1', name: 'Study', ownerUid: 'u1');
    ErrorLogger.muteForTest = true;
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required GroupService service,
    required MockFirebaseAuth auth,
    VibrationService? vibrationService,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditGroupPage(
          group: group,
          groupService: service,
          auth: auth,
          vibrationService: vibrationService ?? const VibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Public Group switch uses SwitchListTile and triggers haptic feedback', (tester) async {
    // Setup group and schedule
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore.collection('groups').doc('g1').collection('schedule').doc('2024-01-01').set({
      'date': Timestamp.fromDate(DateTime(2024, 1, 1)),
      'chapters': ['Gen 1'],
    });

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final vibration = FakeVibrationService();
    final service = GroupService(firestore: firestore);

    await pumpPage(
      tester,
      service: service,
      auth: auth,
      vibrationService: vibration,
    );

    // Should find SwitchListTile
    final switchTileFinder = find.byType(SwitchListTile);
    expect(switchTileFinder, findsOneWidget);

    // Tap call haptic feedback
    await tester.dragUntilVisible(
      switchTileFinder, // what to look for
      find.byType(SingleChildScrollView), // what to scroll
      const Offset(0, -500), // delta to scroll
    );
    await tester.pumpAndSettle();
    await tester.tap(switchTileFinder);
    await tester.pump();
    expect(vibration.lightCount, 1);
  });

  testWidgets('Member removal button has tooltip', (tester) async {
    // Setup group with a member
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore.collection('groups').doc('g1').collection('schedule').doc('2024-01-01').set({
      'date': Timestamp.fromDate(DateTime(2024, 1, 1)),
      'chapters': ['Gen 1'],
    });

    // Add member
    await firestore.collection('groups').doc('g1').collection('members').doc('u2').set({
      'uid': 'u2',
      'role': 'member',
      'joinedAt': Timestamp.now(),
    });
    await firestore.collection('users').doc('u2').set({'name': 'Alice'});

    // Add owner (me)
    await firestore.collection('groups').doc('g1').collection('members').doc('u1').set({
      'uid': 'u1',
      'role': 'owner',
      'joinedAt': Timestamp.now(),
    });

    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    final service = GroupService(firestore: firestore);

    await pumpPage(
      tester,
      service: service,
      auth: auth,
    );

    expect(find.text('Alice'), findsOneWidget);

    // Check for tooltip
    final tooltipFinder = find.byTooltip('Remove Alice');
    expect(tooltipFinder, findsOneWidget);
  });
}
