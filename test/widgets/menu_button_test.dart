import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/app_drawer.dart';
import 'package:bible_read/widgets/menu_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping MenuButton opens ancestor drawer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(onNavigate: (_) {}),
          body: Scaffold(
            appBar: AppBar(
              leading: const MenuButton(),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AppDrawer), findsNothing);

    await tester.tap(find.byType(MenuButton));
    await tester.pumpAndSettle();

    expect(find.byType(AppDrawer), findsOneWidget);
  });
}
