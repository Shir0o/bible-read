import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/animated_action_button.dart';
import 'package:bible_read/services/vibration_service.dart';

class _RecordingVibrationService extends VibrationService {
  int tapCount = 0;

  @override
  Future<void> tap() async {
    tapCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scales down on press and returns on release', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {},
          vibrationService: _RecordingVibrationService(),
          child: const Text('Tap'),
        ),
      ),
    );

    final state =
        tester.state<State<AnimatedActionButton>>(
              find.byType(AnimatedActionButton),
            )
            as dynamic;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pumpAndSettle();

    expect(state.animation.value, closeTo(0.96, 0.02));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.animation.value, 1.0);
  });

  testWidgets('triggers vibration by default', (tester) async {
    final service = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {},
          vibrationService: service,
          child: const Text('Tap'),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pump();
    expect(service.tapCount, 1);
    await gesture.up();
  });

  testWidgets('does not vibrate when disabled', (tester) async {
    final service = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {},
          enableHapticFeedback: false,
          vibrationService: service,
          child: const Text('Tap'),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FilledButton)),
    );
    await tester.pump();
    expect(service.tapCount, 0);
    await gesture.up();
  });

  testWidgets('shows loading indicator and disables onPressed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {
            pressed = true;
          },
          isLoading: true,
          enableHapticFeedback: false,
          child: const Text('Submit'),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(pressed, isFalse);
  });

  testWidgets('cross-fades between label and spinner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {},
          isLoading: false,
          enableHapticFeedback: false,
          child: const Text('Go'),
        ),
      ),
    );

    // Start loading
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedActionButton(
          onPressed: () {},
          isLoading: true,
          enableHapticFeedback: false,
          child: const Text('Go'),
        ),
      ),
    );

    // During the transition both widgets are present.
    await tester.pump();
    expect(find.text('Go'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // After the animation only the spinner remains.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Go'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
