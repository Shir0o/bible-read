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
  });
}
