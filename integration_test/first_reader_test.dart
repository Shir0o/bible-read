import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bible_read/pages/read_log_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('only one first reader per day', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final date = DateTime(2030, 1, 1);
    Future<void> markFirstReader(
        {required String dateKey, required String uid}) async {
      final rewardRef = firestore.collection('daily_rewards').doc(dateKey);
      final rewardDoc = await rewardRef.get();
      if (!rewardDoc.exists) {
        await rewardRef.set({'uid': uid});
        await firestore
            .collection('read_logs')
            .doc(dateKey)
            .collection('entries')
            .doc(uid)
            .set({'firstReader': true}, SetOptions(merge: true));
      }
    }

    final user1 = MockUser(uid: 'u1', displayName: 'First');
    final user2 = MockUser(uid: 'u2', displayName: 'Second');

    await ReadLogPage.writeReadLogEntry(
      user1,
      firestore: firestore,
      dateProvider: () => date,
      markFirstReader: markFirstReader,
    );
    await ReadLogPage.writeReadLogEntry(
      user2,
      firestore: firestore,
      dateProvider: () => date,
      markFirstReader: markFirstReader,
    );

    final dateKey = '${date.year}-${date.month}-${date.day}';
    final firstDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u1')
        .get();
    final secondDoc = await firestore
        .collection('read_logs')
        .doc(dateKey)
        .collection('entries')
        .doc('u2')
        .get();

    expect(firstDoc.data()?['firstReader'], isTrue);
    expect(secondDoc.data()?['firstReader'], isNot(equals(true)));
  });
}
