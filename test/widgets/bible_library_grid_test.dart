import 'package:bible_read/widgets/journey/bible_library_grid.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BibleLibraryGrid displays progress correctly from initial data',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    // Mock completion data: Genesis (50 chapters), Exodus (40 chapters), Matthew (28 chapters)
    final completedByBook = {
      'Genesis': Set<int>.from(List.generate(50, (i) => i + 1)),
      'Exodus': Set<int>.from(List.generate(40, (i) => i + 1)),
      'Matthew': Set<int>.from(List.generate(28, (i) => i + 1)),
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BibleLibraryGrid(
            firestore: firestore,
            auth: auth,
            initialCompletedByBook: completedByBook,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title
    expect(find.text('Bible Library'), findsOneWidget);

    // Verify Progress Summary (3 books total)
    expect(find.text('3'), findsOneWidget);
    expect(find.text('of 66 Books'), findsOneWidget);

    // OT: 2 books (Genesis, Exodus), NT: 1 book (Matthew)
    expect(find.text('2/39'), findsOneWidget);
    expect(find.text('1/27'), findsOneWidget);

    // Verify See All button
    expect(find.text('See All'), findsOneWidget);
  });
}
