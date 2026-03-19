import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/pages/bible_progress_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('BibleProgressPage shows list of books', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gen'), findsOneWidget); // Abbreviation
    expect(find.text('PENTATEUCH'), findsOneWidget); // Category header

    // Scroll down to find Revelation
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text('Rev'), findsOneWidget);
  });

  testWidgets('BibleProgressPage shows completed status and handles optimistic toggle', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(home: BibleProgressPage(firestore: firestore, auth: auth)),
    );
    await tester.pumpAndSettle();

    // 1. Initially Genesis is not completed
    expect(
      find.bySemanticsLabel('Genesis, Not completed'),
      findsOneWidget,
    );

    // 2. Tap to complete
    await tester.tap(find.text('Gen'));
    await tester.pumpAndSettle();
    
    expect(find.text('Complete Genesis?'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    
    // 3. OPTIMISTIC CHECK: UI should update immediately after Confirm, 
    // even without waiting for Firestore or pumpAndSettle (though pump() is needed for next frame)
    await tester.pump();
    
    expect(
      find.bySemanticsLabel('Genesis, Completed'),
      findsOneWidget,
    );

    // 4. Verify Firestore was eventually called (optional but good)
    final doc = await firestore
        .collection('users')
        .doc(user.uid)
        .collection('bible_books')
        .doc('Genesis')
        .get();
    expect(doc.exists, isTrue);
  });
}
