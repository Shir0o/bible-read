import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/models/group_plan_config.dart';
import 'package:bible_read/models/schedule_mode.dart';
import 'package:bible_read/pages/adjust_days_page.dart';
import 'package:bible_read/services/schedule_generator.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/group_plan_form.dart';
import 'package:bible_read/widgets/plan_day_list.dart';
import 'package:bible_read/widgets/starts_at_card.dart';

import '../helpers/pump_golden.dart';
import '../helpers/stub_vibration_service.dart';

/// The reported case: Isaiah then Jeremiah, starting at Jeremiah 1, with day
/// one held to a single chapter and day two to a pair.
GroupPlanDraft _reportedCase() => GroupPlanDraft(
      books: const ['Isaiah', 'Jeremiah'],
      startRef: 'Jeremiah 1',
      mode: ScheduleMode.chaptersPerDay,
      chaptersPerDay: 2,
      startDate: DateTime(2026, 9, 1),
      endDate: null,
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      bookBoundary: true,
      dayOverrides: const {0: 1, 1: 2},
    );

/// Registers the app's bundled faces so golden text renders as type rather
/// than as the test framework's placeholder boxes.
Future<void> _loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Spectral', [
    'Spectral-Regular.ttf',
    'Spectral-Medium.ttf',
    'Spectral-SemiBold.ttf',
  ]);
  await load('Hanken Grotesk', ['HankenGrotesk-VariableFont_wght.ttf']);
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('StartsAtCard golden', (tester) async {
    await tester.pumpGolden(
      SizedBox(
        width: 390,
        child: StartsAtCard(
          startRef: 'Jeremiah 1',
          skippedBefore: 66,
          onChange: () {},
        ),
      ),
      surfaceSize: const Size(430, 240),
    );

    await expectLater(
      find.byType(StartsAtCard),
      matchesGoldenFile('starts_at_card.png'),
    );
  });

  testWidgets('PlanDayList golden', (tester) async {
    final plan = ScheduleGenerator.planFromDraft(_reportedCase());

    await tester.pumpGolden(
      SizedBox(
        width: 390,
        child: PlanDayList(
          days: plan.days,
          overriddenDays: const {0, 1},
          maxRows: 3,
          onSetCount: (_, __) {},
          vibrationService: StubVibrationService(),
        ),
      ),
      surfaceSize: const Size(430, 340),
    );

    await expectLater(
      find.byType(PlanDayList),
      matchesGoldenFile('plan_day_list.png'),
    );
  });

  testWidgets('GroupPlanForm golden', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: Scaffold(
          backgroundColor: AppTheme.designLightScheme.surface,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.hPadding),
            child: GroupPlanForm(
              initial: _reportedCase(),
              onChanged: (_, __) {},
              vibrationService: StubVibrationService(),
            ),
          ),
        ),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(GroupPlanForm),
      matchesGoldenFile('group_plan_form.png'),
    );
  });

  testWidgets('AdjustDaysPage golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.appTheme(AppTheme.designLightScheme),
        home: AdjustDaysPage(
          draft: _reportedCase(),
          vibrationService: StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AdjustDaysPage),
      matchesGoldenFile('adjust_days_page.png'),
    );
  });
}
