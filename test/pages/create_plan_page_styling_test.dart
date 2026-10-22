import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/widgets/book_picker_sheet.dart';
import 'package:bible_read/widgets/plan_day_list.dart';
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

  String previewText(WidgetTester tester) => tester
      .widget<Text>(find.descendant(
        of: find.byKey(const Key('create_plan_preview')),
        matching: find.byType(Text),
      ))
      .data!;

  testWidgets('a sub-page header and the five sections', (tester) async {
    await pumpPage(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(SubHeader, 'New plan'), findsOneWidget);
    for (final title in [
      "Who's reading",
      'Name',
      'What to read',
      'Pace',
      'Day one',
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
    expect(
      find.text('Today, ${formatPlanDateShort(DateTime.now())}'),
      findsOneWidget,
    );
    expect(find.text('Begins at'), findsOneWidget);
    expect(find.text('Genesis 1'), findsOneWidget);
    // Day one reads the pace, so there is nothing to set apart.
    expect(find.text('Day one reads'), findsNothing);
    // The first three days, then where the plan lands.
    expect(find.text('Genesis 1–4'), findsOneWidget);
    expect(find.textContaining('DAY 3 · ', findRichText: true), findsOneWidget);
    expect(find.textContaining('DAY 4 · ', findRichText: true), findsNothing);
    expect(lengthText(tester), '365 days');
    expect(previewText(tester), startsWith('365 reading days · ends '));
    expect(find.text('Start plan'), findsOneWidget);
  });

  testWidgets('the length stepper moves between lengths', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('create_plan_length_inc')));
    await tester.pumpAndSettle();
    expect(lengthText(tester), '730 days');
    expect(previewText(tester), startsWith('730 reading days · ends '));

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

  testWidgets('Choose books opens the book sheet and daily amounts', (
    tester,
  ) async {
    await pumpPage(tester);

    // Nothing is picked yet, so the book sheet opens straight away.
    await tester.tap(find.text('Choose books'));
    await tester.pumpAndSettle();
    expect(find.byKey(BookPickerKeys.sheet), findsOneWidget);
    await tester.tap(find.byKey(BookPickerKeys.quickSet('Gospels')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BookPickerKeys.done));
    await tester.pumpAndSettle();

    expect(find.byKey(BookPickerKeys.sheet), findsNothing);
    expect(find.text('4 books · 89 chapters scheduled'), findsOneWidget);
    expect(find.text('Change books'), findsOneWidget);
    expect(find.text('Pace by'), findsOneWidget);
    expect(find.text('Chapters a day'), findsOneWidget);
    expect(find.text('Verses a day'), findsOneWidget);

    // A daily amount takes a stepper and reshapes the preview.
    await tester.tap(find.text('Chapters a day'));
    await tester.pumpAndSettle();
    expect(previewText(tester), startsWith('30 reading days'));
    await tester.tap(find.byKey(const Key('create_plan_chapters_inc')));
    await tester.pumpAndSettle();
    expect(previewText(tester), startsWith('23 reading days'));

    // Beginning mid-book trims the books it reads.
    await tester.tap(find.byKey(const Key('create_plan_begins_at')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matthew').last);
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin at Matthew 5'));
    await tester.pumpAndSettle();
    expect(find.text('4 books · 85 chapters scheduled'), findsOneWidget);
    expect(find.text('Matthew 1–4 left out'), findsOneWidget);
    expect(find.text('Matthew · from 5', findRichText: true), findsOneWidget);

    // Removing that book moves day one back to the start of what is left.
    await tester.tap(find.text('Change books'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BookPickerKeys.tile('Matthew')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BookPickerKeys.done));
    await tester.pumpAndSettle();
    expect(find.text('3 books · 61 chapters scheduled'), findsOneWidget);
    expect(find.text('Mark 1'), findsOneWidget);

    // Leaving Choose books goes back to the whole Bible paced by length.
    await tester.tap(find.text('In order'));
    await tester.pumpAndSettle();
    expect(find.text('Pace by'), findsNothing);
    expect(lengthText(tester), '365 days');
  });

  testWidgets('backing out of the book sheet keeps the reading method', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('Choose books'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BookPickerKeys.close));
    await tester.pumpAndSettle();

    expect(find.text('Change books'), findsNothing);
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
    await tester.tap(find.byKey(BookPickerKeys.tile('Genesis')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(BookPickerKeys.done));
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

    // Verify the preview line counts the reading days and names the end:
    // Genesis at 3 chapters a day is 17 reading days.
    expect(previewText(tester), startsWith('17 reading days · ends '));
  });

  testWidgets('a title is required', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Start plan'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a plan title.'), findsOneWidget);
    expect((await firestore.collection('custom_plans').get()).docs, isEmpty);
  });
}
