import 'package:bible_read/widgets/journey/bible_library_grid.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/pump_golden.dart';

void main() {
  testWidgets('BibleLibraryGrid golden test', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    final completedByBook = {
      'Genesis': Set<int>.from(List.generate(50, (i) => i + 1)),
      'Exodus': Set<int>.from(List.generate(40, (i) => i + 1)),
      'Matthew': Set<int>.from(List.generate(28, (i) => i + 1)),
    };

    await pumpGoldenWidget(
      tester,
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: BibleLibraryGrid(
          firestore: firestore,
          auth: auth,
          initialCompletedByBook: completedByBook,
        ),
      ),
    );

    await expectLater(
      find.byType(BibleLibraryGrid),
      matchesGoldenFile('goldens/bible_library_grid.png'),
    );
  });
}
