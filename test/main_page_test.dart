import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';

import 'package:bible_read/pages/main_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('MainPage navigation to profile', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MainPage()));

    // HomePage should be shown by default
    expect(find.text('Bible Reading Challenge'), findsOneWidget);

    // Tap Profile navigation item
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.text('Please sign in'), findsOneWidget);
  });
}
