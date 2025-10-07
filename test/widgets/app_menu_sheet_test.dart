import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:bible_read/services/vibration_service.dart';

class _StubVibrationService extends VibrationService {
  int calls = 0;

  @override
  Future<void> lightImpact() async {
    calls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('selecting menu item notifies listener and closes sheet',
      (tester) async {
    final vibrationService = _StubVibrationService();
    int? lastIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    AppMenuSheet.show(
                      context: context,
                      onNavigate: (index) => lastIndex = index,
                      vibrationService: vibrationService,
                    );
                  },
                  child: const Text('Open menu'),
                ),
              );
            },
          ),
        ),
      ),
    );

    Future<void> openMenu() async {
      await tester.tap(find.text('Open menu'));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSheet), findsOneWidget);
    }

    Future<void> select(String label, int expectedIndex) async {
      final previousCalls = vibrationService.calls;
      lastIndex = null;
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(lastIndex, expectedIndex);
      expect(vibrationService.calls, previousCalls + 1);
      expect(find.byType(AppMenuSheet), findsNothing);
    }

    await openMenu();
    await select('Seasonal Challenges', 2);

    await openMenu();
    await select('Leaderboard', 3);

    await openMenu();
    await select('Friends', 4);

    await openMenu();
    await select('Groups', 5);

    await openMenu();
    await select('Achievements', 6);

    await openMenu();
    await select('History', 7);

    await openMenu();
    await select('Notifications', 10);

    await openMenu();
    await select('Profile', 9);
  });
}
