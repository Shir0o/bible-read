import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetchUserInfos benchmark baseline vs mapped', () async {
    final firestore = FakeFirebaseFirestore();

    final uids = List.generate(300, (i) => 'user_$i');

    var batch = firestore.batch();
    for (var i = 0; i < uids.length; i++) {
      batch.set(firestore.collection('users').doc(uids[i]), {
        'uid': uids[i],
        'name': 'User $i',
        'photoURL': 'url_$i',
      });
    }
    await batch.commit();

    // Baseline: using `whereIn` chunks and `Future.wait`
    final stopwatch1 = Stopwatch()..start();
    final futures1 = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < uids.length; i += 30) {
      final end = i + 30 > uids.length ? uids.length : i + 30;
      final chunk = uids.sublist(i, end);
      futures1.add(
        firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      );
    }
    await Future.wait(futures1);
    stopwatch1.stop();
    print(
      'Baseline (whereIn with Future.wait): ${stopwatch1.elapsedMicroseconds} us',
    );

    // Opt 1: using chunked maps with individual `get()` and `Future.wait`
    final stopwatch2 = Stopwatch()..start();
    final futures2 = <Future<List<DocumentSnapshot<Map<String, dynamic>>>>>[];
    for (var i = 0; i < uids.length; i += 30) {
      final end = i + 30 > uids.length ? uids.length : i + 30;
      final chunk = uids.sublist(i, end);
      futures2.add(
        Future.wait(
          chunk.map((uid) => firestore.collection('users').doc(uid).get()),
        ),
      );
    }
    await Future.wait(futures2);
    stopwatch2.stop();
    print(
      'Optimized (chunked mapped gets): ${stopwatch2.elapsedMicroseconds} us',
    );
  });
}
