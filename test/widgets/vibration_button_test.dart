import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/widgets/vibration_button.dart';
import 'package:bible_read/services/vibration_service.dart';

class _MockVibrationService extends Mock implements VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('triggers vibration and onPressed on tap', (tester) async {
    final vibrationService = _MockVibrationService();
    var pressed = false;
    final error = Exception('boom');

    when(() => vibrationService.lightImpact()).thenAnswer((_) async {});

    await tester.pumpWidget(
      MaterialApp(
        home: VibrationButton(
          vibrationService: vibrationService,
          onPressed: () {
            pressed = true;
            throw error;
          },
          child: const Text('Tap me'),
        ),
      ),
    );

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(tester.takeException(), error);
    verify(() => vibrationService.lightImpact()).called(1);
    expect(pressed, isTrue);
    expect(find.text('Tap me'), findsOneWidget);
  });
}
