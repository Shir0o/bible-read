import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_switch_tile.dart';
import 'package:bible_read/services/vibration_service.dart';

class _RecordingVibrationService extends VibrationService {
  int lightCount = 0;

  @override
  Future<void> lightImpact() async {
    lightCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('noAnimation constructor builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReadSwitchTile.noAnimation(value: false, onChanged: null),
        ),
      ),
    );

    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('Tapping the tile toggles the switch and calls onChanged', (
    tester,
  ) async {
    final service = _RecordingVibrationService();
    var value = false;
    bool? callbackValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReadSwitchTile(
              value: value,
              onChanged: (newValue) {
                callbackValue = newValue;
                setState(() => value = newValue);
              },
              vibrationService: service,
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final scaleFinder = find.descendant(
      of: find.byType(ReadSwitchTile),
      matching: find.byType(ScaleTransition),
    );
    final scaleBefore = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleBefore.scale.value, 1.0);

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pump();

    final scaleDuring = tester.widget<ScaleTransition>(scaleFinder);
    expect(scaleDuring.scale.value, lessThan(1.0));

    await tester.pumpAndSettle();

    expect(service.lightCount, 1);
    expect(callbackValue, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('Animations render without throwing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReadSwitchTile(value: false, onChanged: null)),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReadSwitchTile(value: true, onChanged: null)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling the switch triggers vibration', (tester) async {
    final service = _RecordingVibrationService();
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReadSwitchTile(
              value: value,
              onChanged: (newValue) {
                setState(() => value = newValue);
              },
              vibrationService: service,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.lightCount, 1);
  });
}
