import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  testWidgets('Custom Plan section expansion and goal selection', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: CreatePlanPage(auth: auth, firestore: firestore),
      ),
    );
    await tester.pumpAndSettle();

    // Verify basic page structure
    expect(find.text('Enroll in New Plan'), findsOneWidget); // AppBar
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('SELECT READING METHOD'), findsOneWidget);

    // Scroll to Custom Plan section
    final customPlanFinder = find.text('Custom Plan');
    await tester.dragUntilVisible(
      customPlanFinder,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(customPlanFinder, findsOneWidget);

    // Tap to expand
    await tester.tap(customPlanFinder);
    await tester.pumpAndSettle();

    // Verify goal selection radio buttons exist (based on implementation plan)
    expect(find.text('End date:'), findsOneWidget);
    expect(find.text('Amount of verses to read per day:'), findsOneWidget);
    expect(find.text('Amount of chapters to read per day:'), findsOneWidget);

    // Verify fields are present
    expect(find.byIcon(Icons.calendar_today), findsWidgets);
  });

  testWidgets('Hierarchical Bible book selection', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: CreatePlanPage(auth: auth, firestore: firestore),
      ),
    );
    await tester.pumpAndSettle();

    final customPlanFinder = find.text('Custom Plan');
    await tester.dragUntilVisible(
      customPlanFinder,
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(customPlanFinder);
    await tester.pumpAndSettle();

    // Verify categories exist
    expect(find.text('Old Testament'), findsOneWidget);
    expect(find.text('New Testament'), findsOneWidget);

    // Expand Old Testament - find the toggle icon near the text
    await tester.tap(find.text('Old Testament'));
    await tester.pumpAndSettle();

    expect(find.text('Pentateuch'), findsOneWidget);
    expect(find.text('Books of History'), findsOneWidget);
  });
}
