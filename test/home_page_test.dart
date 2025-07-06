import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HomePage shows static UI elements', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    expect(find.text('Bible Reading Challenge'), findsOneWidget);
    expect(find.textContaining('Streak:'), findsOneWidget);
    expect(find.text('Bible Read Today'), findsOneWidget);
    expect(find.text('This Week'), findsOneWidget);
    expect(find.text('This Month'), findsOneWidget);
  });

  testWidgets('HomePage week row has seven icons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    // There should be exactly seven icons for the week status row. All are
    // unchecked by default since no data is loaded in tests.
    final unchecked = find.byIcon(Icons.radio_button_unchecked);
    expect(unchecked, findsNWidgets(7));
  });

  testWidgets('HomePage month calendar matches current month', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    // Verify the month header text
    final now = DateTime.now();
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    final header = '${now.year} – ${months[now.month - 1]}';
    expect(find.text(header), findsOneWidget);

    // Calendar should include one icon per day of the month
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final filled = tester.widgetList(find.byIcon(Icons.circle));
    final empty = tester.widgetList(find.byIcon(Icons.circle_outlined));
    expect(filled.length + empty.length, daysInMonth);
  });
}
