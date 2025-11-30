import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_status_section.dart';
import 'package:bible_read/widgets/read_switch_tile.dart';
import 'package:bible_read/services/vibration_service.dart';

class _TestVibrationService extends VibrationService {
  const _TestVibrationService() : super();

  @override
  Future<void> lightImpact() async {}
}

void main() {
  testWidgets('shows loading indicator when toggling', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadStatusSection(
            toggleLoading: true,
            readToday: false,
            readDates: {},
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('tapping switch calls onToggle', (tester) async {
    var called = false;
    const vibration = _TestVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReadStatusSection(
            toggleLoading: false,
            readToday: false,
            readDates: {},
            onToggle: () {
              called = true;
            },
            streakFreezesLeft: 3,
            vibrationService: vibration,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    expect(called, isTrue);
  });

  testWidgets('shows streak freezes label when provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadStatusSection(
            toggleLoading: false,
            readToday: false,
            readDates: {},
            streakFreezesLeft: 2,
          ),
        ),
      ),
    );

    expect(find.text('Streak freezes left: 2'), findsOneWidget);
  });

  testWidgets('streak freezes info icon and tooltip are present', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadStatusSection(
            toggleLoading: false,
            readToday: false,
            readDates: {},
            streakFreezesLeft: 2,
          ),
        ),
      ),
    );

    // Verify info icon is present
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Verify tooltip
    final tooltipFinder = find.byType(Tooltip);
    expect(tooltipFinder, findsOneWidget);

    final tooltip = tester.widget<Tooltip>(tooltipFinder);
    expect(
      tooltip.message,
      'Each month includes two automatic grace credits to freeze a missed day. Every 15-day streak earns one extra credit.',
    );
  });
}
