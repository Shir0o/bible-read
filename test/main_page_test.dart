import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/main_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MainPage navigation to profile', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainPage()));

    // HomePage should be shown by default
    expect(find.text('Bible Reading Challenge'), findsOneWidget);

    // Tap Profile navigation item
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
