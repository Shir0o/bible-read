import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/app_drawer.dart';
import 'package:bible_read/widgets/menu_button.dart';
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

  testWidgets('tapping MenuButton opens ancestor drawer', (tester) async {
    final service = _RecordingVibrationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(onNavigate: (_) {}),
          body: Scaffold(
            appBar: AppBar(
              leading: MenuButton(vibrationService: service),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppDrawer), findsNothing);

    await tester.tap(find.byType(MenuButton));
    await tester.pumpAndSettle();

    expect(service.lightCount, 1);
    expect(find.byType(AppDrawer), findsOneWidget);
  });
}
