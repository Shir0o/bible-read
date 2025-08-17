import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/app_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping tiles notifies and closes drawer', (tester) async {
    int? lastIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(),
          drawer: AppDrawer(onNavigate: (index) => lastIndex = index),
        ),
      ),
    );

    Future<void> checkTile(String label, int expectedIndex) async {
      lastIndex = null;
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDrawer), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(lastIndex, expectedIndex);
      expect(find.byType(AppDrawer), findsNothing);
    }

    await checkTile('Leaderboard', 2);
    await checkTile('Friends', 3);
    await checkTile('Groups', 4);
    await checkTile('Achievements', 5);
    await checkTile('History', 6);
    await checkTile('Profile', 8);
  });
}
