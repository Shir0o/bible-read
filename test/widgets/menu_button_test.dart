import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/menu_button.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
import 'package:bible_read/widgets/navigation_menu_scope.dart';
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

  testWidgets('tapping MenuButton opens menu sheet and handles selection',
      (tester) async {
    final buttonService = _RecordingVibrationService();
    final menuService = _RecordingVibrationService();
    int? lastIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: NavigationMenuScope(
          onNavigate: (index) => lastIndex = index,
          friendlyStreakIndex: 8,
          vibrationService: menuService,
          child: Scaffold(
            appBar: AppBar(
              leading: MenuButton(vibrationService: buttonService),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppMenuSheet), findsNothing);

    await tester.tap(find.byType(MenuButton));
    await tester.pumpAndSettle();

    expect(buttonService.lightCount, 1);
    expect(find.byType(AppMenuSheet), findsOneWidget);

    expect(find.text('Leaderboard'), findsOneWidget);

    await tester.tap(find.text('Leaderboard'));
    await tester.pumpAndSettle();

    expect(lastIndex, 3);
    expect(menuService.lightCount, 1);
    expect(find.byType(AppMenuSheet), findsNothing);
  });
}
