import 'package:bible_read/models/group_member_progress.dart';
import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/group_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:bible_read/pages/create_group_page.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/pages/group_detail_page.dart';
import 'package:bible_read/widgets/group_plan_keys.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import '../helpers/pump_app.dart';

class MockGroupService extends Mock implements GroupService {}

class MockVibrationService extends Mock implements VibrationService {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {
  @override
  String get uid => 'test_uid';
}

class FakeRoute extends Fake implements Route {}

class FakeGroupPlanDraft extends Fake implements GroupPlanDraft {}

void main() {
  late MockGroupService groupService;
  late MockVibrationService vibrationService;
  late MockFirebaseAuth auth;
  late MockUser user;
  late FakeFirebaseFirestore fakeFirestore;

  setUpAll(() {
    registerFallbackValue(FakeRoute());
    registerFallbackValue(FakeGroupPlanDraft());
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
    // The success path lands on GroupDetailPage, so its streams need stubs
    // even though these tests are about the create screen.
    when(() => groupService.memberOverallCompletion(any()))
        .thenAnswer((_) => Stream.value(<GroupMemberProgressData>[]));
    when(
      () => groupService.memberDailyCompletion(
        any(),
        date: any(named: 'date'),
        includeUid: any(named: 'includeUid'),
      ),
    ).thenAnswer((_) => Stream.value(<GroupMemberProgressData>[]));
    when(() => groupService.schedule(any()))
        .thenAnswer((_) => Stream.value(<GroupSchedule>[]));
    when(() => groupService.userProgressForGroup(any(), any()))
        .thenAnswer((_) => Stream.value(<String, int>{}));
  });

  Widget buildSubject() => CreateGroupPage(
        groupService: groupService,
        auth: auth,
        vibrationService: vibrationService,
      );

  /// Types [book] into the book search and picks it from the suggestions.
  Future<void> addBook(WidgetTester tester, String book) async {
    await tester.enterText(find.byKey(GroupPlanKeys.bookSearchField), book);
    await tester.pumpAndSettle();
    await tester.tap(find.text(book).last);
    await tester.pumpAndSettle();
  }

  group('CreateGroupPage', () {
    testWidgets('renders the plan form', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      expect(find.text('New group plan'), findsOneWidget);
      expect(find.byKey(GroupPlanKeys.nameField), findsOneWidget);
      expect(find.byKey(GroupPlanKeys.bookSearchField), findsOneWidget);
      expect(find.byKey(GroupPlanKeys.paceModeSegment), findsOneWidget);
      expect(find.byKey(GroupPlanKeys.submitButton), findsOneWidget);
    });

    testWidgets('cannot submit until a book is chosen', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      expect(find.byKey(GroupPlanKeys.validationMessage), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(GroupPlanKeys.submitButton),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('adding a book shows where the plan starts', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');

      expect(find.byKey(GroupPlanKeys.bookChip('Jonah')), findsOneWidget);
      expect(find.byKey(GroupPlanKeys.startsAtCard), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(GroupPlanKeys.startRefText)).data,
        'Jonah 1',
      );
    });

    testWidgets('the first day is previewed before creating', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(GroupPlanKeys.dayRow(0)),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(GroupPlanKeys.dayRow(0)), findsOneWidget);
      expect(find.textContaining('Jonah 1'), findsWidgets);
    });

    testWidgets('stepping a day marks it as hand-set', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jeremiah');
      await tester.pumpAndSettle();

      expect(find.byKey(GroupPlanKeys.daySetTag(0)), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(GroupPlanKeys.dayStepperInc(0)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(GroupPlanKeys.dayStepperInc(0)));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupPlanKeys.daySetTag(0)), findsOneWidget);
    });

    testWidgets('weekday presets are available', (tester) async {
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(GroupPlanKeys.weekdayPreset('Weekdays')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(GroupPlanKeys.weekdayPreset('Weekdays')));
      await tester.pumpAndSettle();

      verify(() => vibrationService.lightImpact()).called(greaterThan(0));
    });

    testWidgets('creates the plan and saves its configuration', (tester) async {
      when(
        () => groupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => 'group_1');
      when(
        () => groupService.updateScheduleBatch(
          groupId: any(named: 'groupId'),
          schedules: any(named: 'schedules'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => groupService.updatePlanConfig(
          groupId: any(named: 'groupId'),
          config: any(named: 'config'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(GroupPlanKeys.submitButton));
      await tester.pumpAndSettle();

      final captured = verify(
        () => groupService.updateScheduleBatch(
          groupId: 'group_1',
          schedules: captureAny(named: 'schedules'),
        ),
      ).captured.single as List<GroupSchedule>;

      // Jonah is 4 chapters at the default 2 a day.
      expect(captured, hasLength(2));
      expect(captured.first.chapters, ['Jonah 1', 'Jonah 2']);

      final config = verify(
        () => groupService.updatePlanConfig(
          groupId: 'group_1',
          config: captureAny(named: 'config'),
        ),
      ).captured.single as GroupPlanDraft;
      expect(config.startRef, 'Jonah 1');
      expect(config.books, ['Jonah']);

      expect(find.byType(GroupDetailPage), findsOneWidget);
    });

    testWidgets('names the group after its books when left blank',
        (tester) async {
      when(
        () => groupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => 'group_1');
      when(
        () => groupService.updateScheduleBatch(
          groupId: any(named: 'groupId'),
          schedules: any(named: 'schedules'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => groupService.updatePlanConfig(
          groupId: any(named: 'groupId'),
          config: any(named: 'config'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupPlanKeys.submitButton));
      await tester.pumpAndSettle();

      verify(
        () => groupService.createGroup(
          ownerUid: 'test_uid',
          name: 'Jonah Plan',
        ),
      ).called(1);
    });

    testWidgets('uses the typed name over the suggestion', (tester) async {
      when(
        () => groupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        ),
      ).thenAnswer((_) async => 'group_1');
      when(
        () => groupService.updateScheduleBatch(
          groupId: any(named: 'groupId'),
          schedules: any(named: 'schedules'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => groupService.updatePlanConfig(
          groupId: any(named: 'groupId'),
          config: any(named: 'config'),
        ),
      ).thenAnswer((_) async {});
      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');
      await tester.enterText(
        find.byKey(GroupPlanKeys.nameField),
        'Thursday morning group',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupPlanKeys.submitButton));
      await tester.pumpAndSettle();

      verify(
        () => groupService.createGroup(
          ownerUid: 'test_uid',
          name: 'Thursday morning group',
        ),
      ).called(1);
    });

    testWidgets('reports a failure without leaking the exception',
        (tester) async {
      when(
        () => groupService.createGroup(
          ownerUid: any(named: 'ownerUid'),
          name: any(named: 'name'),
        ),
      ).thenThrow(Exception('firestore exploded'));

      await tester.pumpApp(buildSubject());
      await tester.pumpAndSettle();

      await addBook(tester, 'Jonah');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(GroupPlanKeys.submitButton));
      await tester.pumpAndSettle();

      expect(find.text('Could not create the plan.'), findsOneWidget);
      expect(find.textContaining('firestore exploded'), findsNothing);
    });
  });
}
