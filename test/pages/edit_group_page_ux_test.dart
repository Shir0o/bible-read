import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/models/group.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:bible_read/pages/reschedule_page.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/plan_pace_service.dart';
import 'package:bible_read/services/vibration_service.dart';

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late MockVibrationService vibrationService;
  late Group group;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    group = const Group(
      id: 'g1',
      name: 'Morning Crew',
      ownerUid: 'u1',
      memberCount: 5,
    );
    auth = MockFirebaseAuth();
    vibrationService = MockVibrationService();
    ErrorLogger.muteForTest = true;
    when(() => vibrationService.lightImpact()).thenAnswer((_) async {});
  });

  Future<void> seedGroup() async {
    await firestore.collection('groups').doc('g1').set(group.toFirestore());
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2026-01-01')
        .set(
          GroupSchedule(
            date: DateTime(2026, 1, 1),
            chapters: const ['Gen 1'],
          ).toFirestore(),
        );
    await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .doc('2026-01-02')
        .set(
          GroupSchedule(
            date: DateTime(2026, 1, 2),
            chapters: const ['Gen 2'],
          ).toFirestore(),
        );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReschedulePage(
          group: group,
          groupService: GroupService(firestore: firestore),
          paceService: PlanPaceService(firestore: firestore),
          auth: auth,
          schedule: [
            GroupSchedule(
              date: DateTime(2026, 1, 1),
              chapters: const ['Gen 1'],
            ),
            GroupSchedule(
              date: DateTime(2026, 1, 2),
              chapters: const ['Gen 2'],
            ),
          ],
          completedDateIds: const {},
          daysBehind: 4,
          today: DateTime(2026, 1, 3),
          vibrationService: vibrationService,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('states the consequence before the owner commits',
      (tester) async {
    await seedGroup();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester);

    expect(find.text('Move the dates for Morning Crew'), findsOneWidget);
    expect(find.text('This changes everyone\'s dates'), findsOneWidget);
    expect(find.text('Stretch the schedule'), findsOneWidget);
    expect(find.text('Keep the finish date'), findsOneWidget);
    expect(find.text('Begin again'), findsOneWidget);
    expect(find.text('Reschedule for everyone'), findsOneWidget);
    expect(find.text('Adjust my pace instead'), findsOneWidget);
  });

  testWidgets('owner stretch moves every Group reading later', (tester) async {
    await seedGroup();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    await pumpPage(tester);

    await tester.tap(find.text('Stretch the schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reschedule for everyone'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    final schedule = await firestore
        .collection('groups')
        .doc('g1')
        .collection('schedule')
        .get();
    expect(
      schedule.docs.map((doc) => doc.id).toSet(),
      {'2026-01-05', '2026-01-06'},
    );
  });

  testWidgets('non-owner cannot commit a Reschedule', (tester) async {
    await seedGroup();
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'm2'), signedIn: true);
    await pumpPage(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reschedule for everyone'),
    );
    expect(button.onPressed, isNull);
  });
}
