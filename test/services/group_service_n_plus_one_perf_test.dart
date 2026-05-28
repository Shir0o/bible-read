import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/services/group_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('GroupService N+1 Performance Benchmark', () {
    late FakeFirebaseFirestore firestore;
    late GroupService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = GroupService(firestore: firestore);
    });

    test('groupsForUser baseline performance (60 groups)', () async {
      final uid = 'user1';
      // Create 60 groups and memberships
      for (var i = 0; i < 60; i++) {
        final groupId = 'group_$i';
        await firestore.collection('groups').doc(groupId).set({
          'name': 'Group $i',
          'ownerUid': 'other',
        });
        await firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(uid)
            .set({'uid': uid});
      }

      final stopwatch = Stopwatch()..start();
      // The stream might emit multiple times (once for members, once for owners, once for join requests).
      // We wait for it to have 60 groups.
      final stream = service.groupsForUser(uid);
      final groups = await stream.firstWhere((list) => list.length >= 60);
      stopwatch.stop();

      debugPrint(
        'PERF: groupsForUser (60 groups) took ${stopwatch.elapsedMilliseconds}ms',
      );
      expect(groups.length, 60);
    });

    test(
      'fixMemberProgressSummariesForUser baseline performance (60 groups)',
      () async {
        final uid = 'user1';
        for (var i = 0; i < 60; i++) {
          final groupId = 'group_$i';
          await firestore.collection('groups').doc(groupId).set({
            'name': 'Group $i',
            'ownerUid': 'other',
          });
          await firestore
              .collection('groups')
              .doc(groupId)
              .collection('members')
              .doc(uid)
              .set({'uid': uid});
        }

        final stopwatch = Stopwatch()..start();
        await service.fixMemberProgressSummariesForUser(uid);
        stopwatch.stop();

        debugPrint(
          'PERF: fixMemberProgressSummariesForUser (60 groups) took ${stopwatch.elapsedMilliseconds}ms',
        );
      },
    );
  });
}
