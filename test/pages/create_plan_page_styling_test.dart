import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/widgets/sub_header.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import '../helpers/stub_vibration_service.dart';

/// The Create plan page as rebuilt to the third-pass mock (#988).
void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: CreatePlanPage(
          auth: auth,
          firestore: firestore,
          vibrationService: const StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String lengthText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('create_plan_length'))).data!;

  testWidgets('a sub-page header and the five sections', (tester) async {
    await pumpPage(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(SubHeader, 'New plan'), findsOneWidget);
    for (final title in [
      "Who's reading",
      'Name',
      'What to read',
      'Pace',
      'Start',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    for (final row in [
      'In order',
      'Balanced',
      '3 in Old, 1 in New',
      'Old Testament',
      'New Testament',
      'Choose books',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Starting point'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(lengthText(tester), '365 days');
    expect(find.textContaining('about 3 chapters a day'), findsOneWidget);
    expect(find.text('Start plan'), findsOneWidget);
  });

  testWidgets('the length stepper moves between lengths', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('create_plan_length_inc')));
    await tester.pumpAndSettle();
    expect(lengthText(tester), '730 days');
    expect(find.textContaining('about 2 chapters a day'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create_plan_length_dec')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_plan_length_dec')));
    await tester.pumpAndSettle();
    expect(lengthText(tester), '180 days');
  });

  testWidgets('the fixed distribution keeps its own length and days', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('3 in Old, 1 in New'));
    await tester.pumpAndSettle();

    expect(find.text('Reading days'), findsNothing);
    expect(
        find.textContaining('three OT chapters on six days'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create_plan_length_inc')));
    await tester.pumpAndSettle();
    expect(lengthText(tester), isNot('730 days'));
  });

  testWidgets('Choose books opens the book picker and daily amounts', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('Pentateuch'), findsNothing);
    await tester.tap(find.text('Choose books'));
    await tester.pumpAndSettle();

    expect(find.text('Pace by'), findsOneWidget);
    expect(find.text('Chapters a day'), findsOneWidget);
    expect(find.text('Verses a day'), findsOneWidget);

    // Expand the Old Testament category of the book picker.
    await tester.tap(
      find.byKey(const Key('create_plan_category_Old Testament')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pentateuch'), findsOneWidget);
    expect(find.text('Books of History'), findsOneWidget);

    // A daily amount takes a stepper and reshapes the preview.
    await tester.tap(find.text('Chapters a day'));
    await tester.pumpAndSettle();
    expect(find.textContaining('about 3 chapters a day'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create_plan_chapters_inc')));
    await tester.pumpAndSettle();
    expect(find.textContaining('about 4 chapters a day'), findsOneWidget);

    // Leaving Choose books goes back to the whole Bible paced by length.
    await tester.tap(find.text('In order'));
    await tester.pumpAndSettle();
    expect(find.text('Pace by'), findsNothing);
    expect(lengthText(tester), '365 days');
  });

  testWidgets('the preview line opens the full schedule', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('create_plan_preview')));
    await tester.pumpAndSettle();

    expect(find.text('Full Schedule'), findsOneWidget);
    expect(find.textContaining('Genesis 1'), findsWidgets);
  });

  testWidgets(
      'the full schedule and preview line respect selected reading days', (
    tester,
  ) async {
    await pumpPage(tester);

    // Switch to Choose books with 1 chapter a day to keep schedule small and inspectable
    await tester.tap(find.text('Choose books'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chapters a day'));
    await tester.pumpAndSettle();

    // Toggle off Saturday (6). Note: Sunday (7) is already off by default.
    await tester.ensureVisible(find.text('Reading days'));
    await tester.tap(find.byKey(const Key('create_plan_day_6')));
    await tester.pumpAndSettle();

    // Open full schedule
    await tester.tap(find.byKey(const Key('create_plan_preview')));
    await tester.pumpAndSettle();

    expect(find.text('Full Schedule'), findsOneWidget);

    // Compute expected reading dates for Mon-Fri starting from today
    final expectedDates = <DateTime>[];
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    while (expectedDates.length < 5) {
      if (cursor.weekday >= DateTime.monday &&
          cursor.weekday <= DateTime.friday) {
        expectedDates.add(cursor);
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    // Day 1 reading should be on expectedDates[0], Day 2 on expectedDates[1]
    final firstItemText =
        '${months[expectedDates[0].month - 1]} ${expectedDates[0].day}';
    final secondItemText =
        '${months[expectedDates[1].month - 1]} ${expectedDates[1].day}';

    expect(
      tester
          .widget<Text>(find.byKey(const Key('create_plan_schedule_date_0')))
          .data,
      firstItemText,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('create_plan_schedule_date_1')))
          .data,
      secondItemText,
    );

    // Close sheet
    Navigator.of(tester.element(find.text('Full Schedule'))).pop();
    await tester.pumpAndSettle();

    // Verify preview line text has Ends <expected end date>
    final previewText = tester
        .widget<Text>(find.descendant(
          of: find.byKey(const Key('create_plan_preview')),
          matching: find.byType(Text),
        ))
        .data!;
    expect(previewText, startsWith('Ends '));
    expect(previewText, contains('about 3 chapters a day'));
  });

  testWidgets('a title is required', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a plan title.'), findsOneWidget);
    expect((await firestore.collection('custom_plans').get()).docs, isEmpty);
  });
}
