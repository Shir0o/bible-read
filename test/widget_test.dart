// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/main.dart';
import 'package:bible_read/pages/main_page.dart';

void main() {
  testWidgets('Main page loads', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that MainPage is shown.
    expect(find.byType(MainPage), findsOneWidget);
  });
}
