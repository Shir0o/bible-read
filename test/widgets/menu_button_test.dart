import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

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
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    int? lastIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: NavigationMenuScope(
            onNavigate: (index) => lastIndex = index,
            friendlyStreakIndex: 8,
            friendsIndex: 4,
            vibrationService: menuService,
            auth: auth,
            firestore: firestore,
            child: Scaffold(
              appBar: AppBar(
                leading: MenuButton(vibrationService: buttonService),
              ),
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

    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);

    await tester.tap(find.text('Challenges'));
    await tester.pumpAndSettle();

    expect(menuService.lightCount, 1);
    expect(find.byType(AppMenuSheet), findsNothing);
    expect(lastIndex, 5); // Challenges index
  });
}
