// ignore_for_file: subtype_of_sealed_class

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:fake_cloud_firestore/src/mock_document_reference.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/pages/read_log_page.dart';
import 'package:bible_read/widgets/badge_icon.dart';
import '../helpers/stub_vibration_service.dart';

class ThrowingCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    throw FirebaseException(plugin: 'firestore');
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    final base = super.collection(collectionPath)
        as MockCollectionReference<Map<String, dynamic>>;
    return ThrowingCollectionReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.root,
      base.docsData,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'read_logs') {
      return ThrowingCollectionReference(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

class ThrowingRewardsDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingRewardsDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class ThrowingRewardsCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingRewardsCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingRewardsDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingRewardsFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'daily_rewards') {
      return ThrowingRewardsCollectionReference(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

// Firestore that throws on like writes
class ThrowingWriteLikesDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingWriteLikesDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    throw FirebaseException(plugin: 'firestore');
  }

  @override
  Future<void> delete() async {
    throw FirebaseException(plugin: 'firestore');
  }
}

class ThrowingWriteLikesCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingWriteLikesCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingWriteLikesDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingWriteEntriesDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingWriteEntriesDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    final base = super.collection(collectionPath)
        as MockCollectionReference<Map<String, dynamic>>;
    if (collectionPath == 'likes') {
      return ThrowingWriteLikesCollectionReference(
        firestore as FakeFirebaseFirestore,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

class ThrowingWriteEntriesCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingWriteEntriesCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingWriteEntriesDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingWriteDateDocumentReference
    extends MockDocumentReference<Map<String, dynamic>> {
  ThrowingWriteDateDocumentReference(
    FakeFirebaseFirestore firestore,
    String path,
    String id,
    Map<String, dynamic> root,
    Map<String, dynamic> docsData,
    Map<String, dynamic> rootParent,
    Map<String, dynamic> snapshotStreamControllerRoot,
  ) : super(
          firestore,
          path,
          id,
          root,
          docsData,
          rootParent,
          snapshotStreamControllerRoot,
          null,
        );

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    final base = super.collection(collectionPath)
        as MockCollectionReference<Map<String, dynamic>>;
    if (collectionPath == 'entries') {
      return ThrowingWriteEntriesCollectionReference(
        firestore as FakeFirebaseFirestore,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

class ThrowingWriteDateCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingWriteDateCollectionReference(
    super.firestore,
    super.path,
    super.root,
    super.docsData,
    super.snapshotStreamControllerRoot,
  );

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    final base =
        super.doc(path ?? '') as MockDocumentReference<Map<String, dynamic>>;
    return ThrowingWriteDateDocumentReference(
      firestore as FakeFirebaseFirestore,
      base.path,
      base.id,
      base.root,
      base.docsData,
      base.rootParent,
      base.snapshotStreamControllerRoot,
    );
  }
}

class ThrowingWriteFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'read_logs') {
      return ThrowingWriteDateCollectionReference(
        this,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
    return base;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadLogPage', () {
    final fixedDate = DateTime(2025, 7, 15);

    test('writeReadLogEntry creates Firestore document', () async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(
        uid: '123',
        displayName: 'Test User',
        email: 'test@example.com',
      );

      await ReadLogPage.writeReadLogEntry(
        user,
        firestore: firestore,
        dateProvider: () => fixedDate,
      );

      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      final snapshot = await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc(user.uid)
          .get();

      expect(snapshot.exists, isTrue);
      expect(snapshot.data()?['name'], 'Test');
      expect(snapshot.data()?['email'], 'test@example.com');
    });

    test('writeReadLogEntry triggers markFirstReader callback', () async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      bool called = false;

      await ReadLogPage.writeReadLogEntry(
        user,
        firestore: firestore,
        dateProvider: () => fixedDate,
        markFirstReader: (
            {required String dateKey, required String uid}) async {
          called = true;
          expect(uid, 'u1');
          final expectedKey =
              '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
          expect(dateKey, expectedKey);
          return {'first': true};
        },
      );

      expect(called, isTrue);
    });

    test('writeReadLogEntry unlocks achievement when first reader', () async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1', displayName: 'Tester');

      await ReadLogPage.writeReadLogEntry(
        user,
        firestore: firestore,
        dateProvider: () => fixedDate,
        markFirstReader: (
            {required String dateKey, required String uid}) async {
          return {'first': true};
        },
      );

      final achievementDoc = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('achievements')
          .doc('firstReader')
          .get();

      expect(achievementDoc.exists, isTrue);
    });

    testWidgets('shows sign in prompt when not authenticated', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth();

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: auth,
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in to see who\'s reading today'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('loadLogs populates _logs list', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User One',
        'email': 'u1@test.com',
        'timestamp': Timestamp.now(),
      });
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .collection('likes')
          .doc('l1')
          .set({'timestamp': Timestamp.now(), 'name': 'Liker'});

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: MockFirebaseAuth(mockUser: user, signedIn: true),
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('User'), findsOneWidget);
      expect(find.text('Read today'), findsOneWidget);
      // expect(find.textContaining('sent encouragement'), findsOneWidget); // FeedCard uses specific format.
      // FeedCard: "Liker" (if 1 like) or logic.
      // FeedCard likes logic: "Liker" (if 1 like) or join.
      // _buildLikeText: "Liker".
      expect(find.text('Liker'), findsOneWidget);
      expect(find.byType(BadgeIcon), findsNothing);
    });

    testWidgets('shows first reader badge when flagged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User One',
        'email': 'u1@test.com',
        'firstReader': true,
        'timestamp': Timestamp.now(),
      });
      await firestore.collection('daily_rewards').doc(dateKey).set({
        'uid': 'u1',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: MockFirebaseAuth(mockUser: user, signedIn: true),
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      /* Gamification removed
      final badgeFinder = find.byType(BadgeIcon);
      expect(badgeFinder, findsOneWidget);

      await tester.longPress(badgeFinder);
      await tester.pumpAndSettle();

      expect(find.text('First reader'), findsOneWidget);
      */
      expect(find.byType(BadgeIcon), findsNothing);
    });

    testWidgets('renders feed when daily reward is inaccessible', (
      tester,
    ) async {
      final firestore = ThrowingRewardsFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({
        'name': 'User One',
        'email': 'u1@test.com',
        'timestamp': Timestamp.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: MockFirebaseAuth(mockUser: user, signedIn: true),
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('User'), findsOneWidget);
      expect(find.text('Read today'), findsOneWidget);
      expect(
        find.text(
          'Unable to load today\'s readers.\nPlease check your connection.',
        ),
        findsNothing,
      );
      expect(find.byType(BadgeIcon), findsNothing);
    });

    testWidgets('toggleLike adds and then removes like', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1', displayName: 'Tester One');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .set({
        'name': 'User Two',
        'email': 'u2@test.com',
        'timestamp': Timestamp.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: auth,
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Likes
      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.favorite_rounded),
        findsOneWidget,
      ); // Expect filled

      final likeDoc = await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .collection('likes')
          .doc('u1')
          .get();
      expect(likeDoc.exists, isTrue);

      // Unlikes
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.favorite_border_rounded),
        findsOneWidget,
      ); // Expect outline

      final likeDocDeleted = await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .collection('likes')
          .doc('u1')
          .get();
      expect(likeDocDeleted.exists, isFalse);
    });

    testWidgets('shows fallback text when Firestore fails', (tester) async {
      final firestore = ThrowingFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: auth,
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Unable to load today\'s readers.\nPlease check your connection.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('toggleLike handles write failure', (tester) async {
      final firestore = ThrowingWriteFirestore();
      final user = MockUser(uid: 'u1', displayName: 'User One');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      await firestore
          .collection('read_logs')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .set({
        'name': 'User Two',
        'email': 'u2@test.com',
        'timestamp': Timestamp.now(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: ReadLogPage(
            firestore: firestore,
            auth: auth,
            dateProvider: () => fixedDate,
            onSendLikeNotification: ({
              required String ownerUid,
              required String likerName,
            }) async {},
            onSendCommentNotification: ({
              required String ownerUid,
              required String commenterName,
            }) async {},
            vibrationService: const StubVibrationService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.runAsync(() async {
        final likeDoc = await firestore
            .collection('read_logs')
            .doc(dateKey)
            .collection('entries')
            .doc('u2')
            .collection('likes')
            .doc(user.uid)
            .get();
        expect(likeDoc.exists, isFalse);
      });
    });
  });
}
