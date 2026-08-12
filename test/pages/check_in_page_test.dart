import 'package:bible_read/pages/check_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CheckInPage Widget Tests', () {
    testWidgets('renders initial un-read check-in screen correctly', (
      tester,
    ) async {
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CheckInPage(
            readToday: false,
            seasonDays: 42,
            onClose: () {
              closed = true;
            },
          ),
        ),
      );

      expect(find.text('Did you read today?'), findsOneWidget);
      expect(find.text('I READ'), findsOneWidget);

      // Dismiss button tap
      final dismissBtn = find.bySemanticsLabel('Dismiss check-in');
      expect(dismissBtn, findsOneWidget);
      await tester.tap(dismissBtn);
      expect(closed, isTrue);
    });

    testWidgets('tapping I READ triggers rise animation and payoff screen', (
      tester,
    ) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: CheckInPage(
              readToday: false,
              seasonDays: 42,
              onConfirmRead: () async {
                confirmed = true;
              },
              onClose: () {},
            ),
          ),
        ),
      );

      expect(find.text('Did you read today?'), findsOneWidget);
      await tester.tap(find.text('I READ'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 1000));

      expect(confirmed, isTrue);
      expect(find.text('Thank you for being here'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('days this season'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets(
      'renders initial read state payoff screen when readToday is true',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TickerMode(
              enabled: false,
              child: CheckInPage(
                readToday: true,
                seasonDays: 15,
                onClose: () {},
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 1000));
        expect(find.text('Thank you for being here'), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
        expect(find.text('days this season'), findsOneWidget);
      },
    );

    testWidgets('evaluates timeOfDay gradients correctly', (tester) async {
      final dawnDate = DateTime(2026, 8, 11, 8, 0); // 8 AM = dawn
      final dayDate = DateTime(2026, 8, 11, 14, 0); // 2 PM = day
      final duskDate = DateTime(2026, 8, 11, 19, 0); // 7 PM = dusk
      final nightDate = DateTime(2026, 8, 11, 23, 0); // 11 PM = night

      expect(getTimeOfDay(dawnDate), CheckInTimeOfDay.dawn);
      expect(getTimeOfDay(dayDate), CheckInTimeOfDay.day);
      expect(getTimeOfDay(duskDate), CheckInTimeOfDay.dusk);
      expect(getTimeOfDay(nightDate), CheckInTimeOfDay.night);
    });

    testWidgets(
      'sky gradient tracks the provided time of day on the rendered screen',
      (tester) async {
        LinearGradient skyGradient() {
          final container = tester.widget<Container>(
            find.byKey(const ValueKey('checkin_sky')),
          );
          return (container.decoration! as BoxDecoration).gradient!
              as LinearGradient;
        }

        Future<void> pumpAt(DateTime date) async {
          await tester.pumpWidget(
            MaterialApp(
              home: TickerMode(
                enabled: false,
                child: CheckInPage(
                  readToday: false,
                  dateProvider: () => date,
                  onClose: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        await pumpAt(DateTime(2026, 8, 11, 8, 0)); // dawn
        expect(
          skyGradient().colors,
          const [
            Color(0xFFFFD3A6),
            Color(0xFFFFB4B8),
            Color(0xFFD9BDE8),
            Color(0xFFC3BCEE),
          ],
        );

        await pumpAt(DateTime(2026, 8, 11, 14, 0)); // day
        expect(
          skyGradient().colors,
          const [
            Color(0xFFBFE6F7),
            Color(0xFFD8ECF6),
            Color(0xFFEFE6D8),
            Color(0xFFF6E9D4),
          ],
        );

        await pumpAt(DateTime(2026, 8, 11, 23, 0)); // night
        expect(
          skyGradient().colors,
          const [
            Color(0xFF241F3C),
            Color(0xFF332A55),
            Color(0xFF463A72),
            Color(0xFF5A4B8C),
          ],
        );
      },
    );

    testWidgets(
      'payoff blessing clears the risen sun after confirming (no overlap)',
      (tester) async {
        // Match the design frame (390x844) so the sun's risen position and the
        // centered payoff have realistic room.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: CheckInPage(
              readToday: false,
              seasonDays: 42,
              onConfirmRead: () async {},
              onClose: () {},
            ),
          ),
        );

        await tester.tap(find.text('I READ'));
        await tester.pump();
        // Let the sun rise and the flood/payoff settle (both ~800ms).
        await tester.pump(const Duration(milliseconds: 900));

        final sunRect = tester.getRect(
          find.byKey(const ValueKey('checkin_sun')),
        );
        final blessingRect = tester.getRect(
          find.text('Thank you for being here'),
        );

        expect(
          sunRect.bottom <= blessingRect.top,
          isTrue,
          reason: 'Payoff blessing must not overlap the risen sun: '
              'sun=$sunRect blessing=$blessingRect',
        );
      },
    );

    testWidgets('I READ button is gone once the payoff screen shows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CheckInPage(
            readToday: false,
            seasonDays: 42,
            onConfirmRead: () async {},
            onClose: () {},
          ),
        ),
      );

      // Ask screen: the button is fully visible.
      FadeTransition sunFade() => tester.widget<FadeTransition>(
            find.byKey(const ValueKey('checkin_sun_fade')),
          );
      expect(sunFade().opacity.value, 1.0);

      await tester.tap(find.text('I READ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      // Payoff screen is a clean second screen: the "I READ" button has
      // dissolved completely.
      expect(find.text('Thank you for being here'), findsOneWidget);
      expect(sunFade().opacity.value, 0.0);
    });
  });
}
