import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/account_linking_service.dart';
import 'package:bible_read/services/reading_status_service.dart';
import 'package:bible_read/widgets/merge_dry_run_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MergeDryRunData createSampleDryRun() {
    final guestDates = {
      DateTime(2026, 10, 20),
      DateTime(2026, 10, 21),
    };
    final cloudDates = {
      DateTime(2026, 10, 21),
      DateTime(2026, 10, 22),
    };
    final mergedDates = {
      DateTime(2026, 10, 20),
      DateTime(2026, 10, 21),
      DateTime(2026, 10, 22),
    };
    final guestStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: guestDates,
      today: DateTime(2026, 10, 22),
    );
    final cloudStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: cloudDates,
      today: DateTime(2026, 10, 22),
    );
    final mergedStatus = ReadingStatusService.deriveStatusFromDates(
      readDates: mergedDates,
      today: DateTime(2026, 10, 22),
    );

    return MergeDryRunData(
      guestDates: guestDates,
      cloudDates: cloudDates,
      mergedDates: mergedDates,
      guestStatus: guestStatus,
      cloudStatus: cloudStatus,
      mergedStatus: mergedStatus,
      guestPlans: [],
      cloudPlans: [],
      mergedPlans: [
        UserPlanProgress(
          planId: 'psalms_30',
          userId: 'cloud_uid',
          startDate: DateTime(2026, 10, 1),
          completedDays: [1, 2, 3],
        ),
        UserPlanProgress(
          planId: 'gospels_90',
          userId: 'cloud_uid',
          startDate: DateTime(2026, 10, 5),
          completedDays: [1],
        ),
      ],
      targetUid: 'cloud_uid',
    );
  }

  testWidgets('renders dry run sheet with headline and comparison stats',
      (tester) async {
    final dryRun = createSampleDryRun();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MergeDryRunSheet(dryRunData: dryRun),
        ),
      ),
    );

    // Headline
    expect(find.text('Merge reading history'), findsOneWidget);

    // Stat labels
    expect(find.text('Guest Days'), findsOneWidget);
    expect(find.text('Account Days'), findsOneWidget);
    expect(find.text('Merged Total Days'), findsOneWidget);
    expect(find.text('Merged Current Streak'), findsOneWidget);

    // Stat values
    expect(find.text('${dryRun.guestDays}'), findsWidgets);
    expect(find.text('${dryRun.cloudDays}'), findsWidgets);
    expect(find.text('${dryRun.mergedTotalDays}'), findsWidgets);
    expect(find.text('${dryRun.mergedStreak}'), findsWidgets);

    // Plan list
    expect(find.text('psalms_30'), findsOneWidget);
    expect(find.text('gospels_90'), findsOneWidget);
    expect(find.text('3 days completed'), findsOneWidget);
    expect(find.text('1 days completed'), findsOneWidget);

    // Buttons
    expect(find.text('Merge & Continue'), findsOneWidget);
    expect(find.text('Keep Account Only'), findsOneWidget);
  });

  testWidgets('tapping Merge & Continue confirms callback with selected plans',
      (tester) async {
    final dryRun = createSampleDryRun();
    List<UserPlanProgress>? submittedPlans;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MergeDryRunSheet(
            dryRunData: dryRun,
            onMerge: (plans) async {
              submittedPlans = plans;
            },
          ),
        ),
      ),
    );

    // Uncheck gospels_90
    final gospelsCheckbox = find.widgetWithText(CheckboxListTile, 'gospels_90');
    expect(gospelsCheckbox, findsOneWidget);
    await tester.tap(gospelsCheckbox);
    await tester.pumpAndSettle();

    // Tap Merge & Continue
    await tester.tap(find.text('Merge & Continue'));
    await tester.pumpAndSettle();

    expect(submittedPlans, isNotNull);
    expect(submittedPlans!.length, 1);
    expect(submittedPlans!.first.planId, 'psalms_30');
  });

  testWidgets('tapping Keep Account Only confirms callback', (tester) async {
    final dryRun = createSampleDryRun();
    var keepOnlyCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MergeDryRunSheet(
            dryRunData: dryRun,
            onKeepAccountOnly: () async {
              keepOnlyCalled = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Keep Account Only'));
    await tester.pumpAndSettle();

    expect(keepOnlyCalled, isTrue);
  });
}
