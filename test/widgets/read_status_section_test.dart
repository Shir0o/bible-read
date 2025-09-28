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
            vibrationService: vibration,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();
    expect(called, isTrue);
  });
}
