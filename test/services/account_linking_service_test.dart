import 'package:bible_read/models/reading_plan_progress.dart';
import 'package:bible_read/services/account_linking_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCredential extends Fake implements AuthCredential {}

class _FakeUserCredential extends Fake implements UserCredential {
  @override
  final User user;
  _FakeUserCredential(this.user);
}

class _CollisionAuth extends MockFirebaseAuth {
  final User cloudUser;

  _CollisionAuth({
    required super.mockUser,
    required this.cloudUser,
    super.signedIn,
  });

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) {
    return Future.value(_FakeUserCredential(cloudUser));
  }
}

// ignore: must_be_immutable
class _CollidingMockUser extends MockUser {
  final AuthCredential expectedCredential;

  _CollidingMockUser({
    required this.expectedCredential,
  }) : super(uid: 'guest_uid', isAnonymous: true);

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) {
    if (credential == expectedCredential) {
      throw FirebaseAuthException(
        code: 'credential-already-in-use',
        message: 'The account is already linked to another user.',
      );
    }
    return Future.value(_FakeUserCredential(this));
  }
}

// ignore: must_be_immutable
class _SuccessMockUser extends MockUser {
  final AuthCredential expectedCredential;

  _SuccessMockUser({
    required this.expectedCredential,
  }) : super(uid: 'guest_uid', isAnonymous: true);

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) {
    return Future.value(_FakeUserCredential(this));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccountLinkingService - computeMerge', () {
    test('computes date union and derives status and streaks', () {
      final service = AccountLinkingService();
      final today = DateTime(2026, 10, 22);

      // Guest read day before yesterday (20) and yesterday (21).
      final guestDates = {
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
      };

      // Cloud read today (22) and yesterday (21).
      final cloudDates = {
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 22),
      };

      final dryRun = service.computeMerge(
        guestDates: guestDates,
        cloudDates: cloudDates,
        guestPlans: [],
        cloudPlans: [],
        today: today,
        targetUid: 'cloud_user_1',
      );

      expect(dryRun.guestDays, 2);
      expect(dryRun.cloudDays, 2);
      expect(dryRun.mergedTotalDays, 3);
      expect(dryRun.mergedDates, {
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 22),
      });

      // Guest didn't read today (22), so streak without today is evaluated.
      // Cloud read today (22) and yesterday (21), streak is 2.
      expect(dryRun.cloudStreak, 2);
      // Merged read 20, 21, 22 consecutively up to today, streak is 3.
      expect(dryRun.mergedStreak, 3);
      expect(dryRun.targetUid, 'cloud_user_1');
    });

    test('deduplicates and merges reading plans', () {
      final service = AccountLinkingService();
      final today = DateTime(2026, 10, 22);

      // Shared plan: psalms
      final guestPsalms = UserPlanProgress(
        planId: 'psalms',
        userId: 'guest_1',
        startDate: DateTime(2026, 10, 1),
        completedDays: [1, 2],
        lastReadDate: DateTime(2026, 10, 2),
      );
      final cloudPsalms = UserPlanProgress(
        planId: 'psalms',
        userId: 'cloud_1',
        startDate: DateTime(2026, 10, 3),
        completedDays: [2, 3],
        lastReadDate: DateTime(2026, 10, 5),
      );

      // Guest-only plan: gospels
      final guestGospels = UserPlanProgress(
        planId: 'gospels',
        userId: 'guest_1',
        startDate: DateTime(2026, 10, 10),
        completedDays: [1, 5],
      );

      // Cloud-only plan: epistles
      final cloudEpistles = UserPlanProgress(
        planId: 'epistles',
        userId: 'cloud_1',
        startDate: DateTime(2026, 10, 15),
        completedDays: [4],
      );

      final dryRun = service.computeMerge(
        guestDates: {},
        cloudDates: {},
        guestPlans: [guestPsalms, guestGospels],
        cloudPlans: [cloudPsalms, cloudEpistles],
        today: today,
        targetUid: 'target_cloud_uid',
      );

      expect(dryRun.mergedPlans.length, 3);

      final psalms = dryRun.mergedPlans.firstWhere((p) => p.planId == 'psalms');
      expect(psalms.completedDays, [1, 2, 3]);
      expect(psalms.startDate, DateTime(2026, 10, 1));
      expect(psalms.lastReadDate, DateTime(2026, 10, 5));
      expect(psalms.userId, 'target_cloud_uid');

      final gospels =
          dryRun.mergedPlans.firstWhere((p) => p.planId == 'gospels');
      expect(gospels.completedDays, [1, 5]);
      expect(gospels.userId, 'target_cloud_uid');

      final epistles =
          dryRun.mergedPlans.firstWhere((p) => p.planId == 'epistles');
      expect(epistles.completedDays, [4]);
      expect(epistles.userId, 'target_cloud_uid');
    });
  });

  group('AccountLinkingService - commitMerge', () {
    test('writes merged reading dates and plan progress to target user',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = AccountLinkingService(firestore: firestore);

      final dates = {
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 21),
      };
      final plans = [
        UserPlanProgress(
          planId: 'plan_nt',
          userId: 'old_uid',
          startDate: DateTime(2026, 10, 1),
          completedDays: [1, 2, 3],
        ),
      ];

      await service.commitMerge(
        targetUid: 'target_uid_123',
        dates: dates,
        plans: plans,
      );

      final read20 = await firestore
          .collection('users')
          .doc('target_uid_123')
          .collection('reading')
          .doc('2026-10-20')
          .get();
      expect(read20.exists, isTrue);
      expect(read20.data()?['read'], isTrue);

      final read21 = await firestore
          .collection('users')
          .doc('target_uid_123')
          .collection('reading')
          .doc('2026-10-21')
          .get();
      expect(read21.exists, isTrue);
      expect(read21.data()?['read'], isTrue);

      final planDoc = await firestore
          .collection('users')
          .doc('target_uid_123')
          .collection('plan_progress')
          .doc('plan_nt')
          .get();
      expect(planDoc.exists, isTrue);
      expect(planDoc.data()?['completedDays'], [1, 2, 3]);
      expect(planDoc.data()?['userId'], 'target_uid_123');
    });
  });

  group('AccountLinkingService - fetchReadingDates and fetchPlanProgress', () {
    test('fetches reading dates and active plan progress', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AccountLinkingService(firestore: firestore);

      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc('2026-10-15')
          .set({'read': true});
      await firestore
          .collection('users')
          .doc('u1')
          .collection('reading')
          .doc('2026-10-16')
          .set({'read': false});

      final dates = await service.fetchReadingDates('u1');
      expect(dates, {DateTime(2026, 10, 15)});

      final plan = UserPlanProgress(
        planId: 'plan_ot',
        userId: 'u1',
        startDate: DateTime(2026, 10, 1),
        completedDays: [1],
      );
      await firestore
          .collection('users')
          .doc('u1')
          .collection('plan_progress')
          .doc('plan_ot')
          .set(plan.toFirestore());

      final plans = await service.fetchPlanProgress('u1');
      expect(plans.length, 1);
      expect(plans.first.planId, 'plan_ot');
    });
  });

  group('AccountLinkingService - linkCredential', () {
    test('succeeds when there is no collision', () async {
      final firestore = FakeFirebaseFirestore();
      final cred = _FakeCredential();
      final user = _SuccessMockUser(expectedCredential: cred);
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

      final service = AccountLinkingService(
        auth: auth,
        firestore: firestore,
      );

      final result = await service.linkCredential(cred);
      expect(result, isNotNull);
    });

    test('throws AccountCollisionException on credential-already-in-use',
        () async {
      final firestore = FakeFirebaseFirestore();
      final cred = _FakeCredential();
      final guestUser = _CollidingMockUser(expectedCredential: cred);
      final cloudUser = MockUser(uid: 'cloud_uid', isAnonymous: false);
      final auth = _CollisionAuth(
        mockUser: guestUser,
        cloudUser: cloudUser,
        signedIn: true,
      );

      // Prepopulate guest reading data
      await firestore
          .collection('users')
          .doc('guest_uid')
          .collection('reading')
          .doc('2026-10-21')
          .set({'read': true});

      // Prepopulate cloud reading data
      await firestore
          .collection('users')
          .doc('cloud_uid')
          .collection('reading')
          .doc('2026-10-22')
          .set({'read': true});

      final service = AccountLinkingService(
        auth: auth,
        firestore: firestore,
        nowProvider: () => DateTime(2026, 10, 22),
      );

      expect(
        () => service.linkCredential(cred),
        throwsA(isA<AccountCollisionException>()
            .having(
              (e) => e.dryRunData.guestDays,
              'guestDays',
              1,
            )
            .having(
              (e) => e.dryRunData.cloudDays,
              'cloudDays',
              1,
            )
            .having(
              (e) => e.dryRunData.mergedTotalDays,
              'mergedTotalDays',
              2,
            )
            .having(
              (e) => e.targetUid,
              'targetUid',
              'cloud_uid',
            )),
      );
    });
  });
}
