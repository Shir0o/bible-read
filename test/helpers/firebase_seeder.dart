import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/models/group_schedule.dart';

class FirebaseSeeder {
  final FakeFirebaseFirestore firestore;

  FirebaseSeeder(this.firestore);

  Future<void> seedUser({
    required String uid,
    String? name,
    String? email,
  }) async {
    await firestore.collection('users').doc(uid).set({
      'displayName': name ?? 'Test User',
      'email': email ?? 'test@example.com',
      'photoUrl': 'https://example.com/avatar.png',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Seed summary/data for streaks
    await firestore
        .collection('users')
        .doc(uid)
        .collection('summary')
        .doc('data')
        .set({'streak': 0});
  }

  Future<void> seedGroup({
    required String groupId,
    required String ownerUid,
    String name = 'Test Group',
    List<String> members = const [],
    int progress = 0,
    int? memberCount,
  }) async {
    await firestore.collection('groups').doc(groupId).set({
      'name': name,
      'ownerUid': ownerUid,
      'memberCount': memberCount ?? members.length,
      'createdAt': FieldValue.serverTimestamp(),
      'progress': progress,
      'planId': 'plan1', // Mock plan ID
    });

    for (final memberUid in members) {
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(memberUid)
          .set({
        'joinedAt': FieldValue.serverTimestamp(),
        'role': memberUid == ownerUid ? 'owner' : 'member',
      });

      // Initialize member progress
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('progress')
          .doc(memberUid)
          .set({'count': 0, 'lastRead': null});
    }
  }

  Future<void> seedReadingPlan({
    required String planId,
    required String name,
    int chaptersPerDay = 1,
  }) async {
    await firestore.collection('reading_plans').doc(planId).set({
      'name': name,
      'description': 'A test plan',
      'chaptersPerDay': chaptersPerDay,
      'totalChapters': 100,
    });

    // Seed chapters
    for (int i = 1; i <= 100; i++) {
      await firestore
          .collection('reading_plans')
          .doc(planId)
          .collection('items')
          .doc(i.toString())
          .set({'ref': 'Gen $i', 'desc': 'Description $i'});
    }
  }

  Future<void> seedGroupSchedule({
    required String groupId,
    required List<GroupSchedule> schedule,
  }) async {
    for (final s in schedule) {
      final dateKey =
          '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('groups')
          .doc(groupId)
          .collection('schedule')
          .doc(dateKey)
          .set(s.toFirestore());
    }
  }
}
