// ignore_for_file: subtype_of_sealed_class

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:fake_cloud_firestore/src/mock_collection_reference.dart';
import 'package:fake_cloud_firestore/src/mock_document_reference.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bible_read/pages/read_log_page.dart';
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
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource? source,
  }) {
    return Stream.error(FirebaseException(plugin: 'firestore'));
  }

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
    // Only the feed reads throw — keep other subtrees usable.
    if (collectionPath == 'read_log' || collectionPath == 'entries') {
      return ThrowingCollectionReference(
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

class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final base =
        super.collection(path) as MockCollectionReference<Map<String, dynamic>>;
    if (path == 'groups') {
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
    if (collectionPath == 'read_log') {
      // The like path runs groups/{g}/read_log/{date}/entries/{uid}/likes —
      // every level must keep handing back wrappers or the throw never fires.
      return ThrowingWriteReadLogCollectionReference(
        firestore as FakeFirebaseFirestore,
        base.path,
        base.root,
        base.docsData,
        base.snapshotStreamControllerRoot,
      );
    }
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

/// read_log collection reached from a group document; its date documents are
/// [ThrowingWriteDateDocumentReference]s.
class ThrowingWriteReadLogCollectionReference
    extends MockCollectionReference<Map<String, dynamic>> {
  ThrowingWriteReadLogCollectionReference(
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
    if (path == 'groups') {
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

/// Seeds g1 with [ownerUid] owning it and [memberUid] as a member, so the
/// reader's membership resolves and the per-Group feed stream attaches.
Future<void> _seedGroupEntry(
  FakeFirebaseFirestore firestore, {
  required String groupId,
  required String ownerUid,
  required String memberUid,
  required String dateKey,
}) async {
  await firestore.collection('groups').doc(groupId).set({
    'name': 'Group $groupId',
    'ownerUid': ownerUid,
    'memberCount': 2,
  });
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc(memberUid)
      .set({'uid': memberUid, 'role': 'member'});
  await firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc(ownerUid)
      .set({'uid': ownerUid, 'role': 'owner'});
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadLogPage', () {
    final fixedDate = DateTime(2025, 7, 15);


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

    testWidgets("feed streams entries from the reader's Groups", (tester) async {
      final firestore = FakeFirebaseFirestore();
      final user = MockUser(uid: 'u1');
      final dateKey =
          '${fixedDate.year}-${fixedDate.month.toString().padLeft(2, '0')}-${fixedDate.day.toString().padLeft(2, '0')}';
      // u1 belongs to g1; their co-member u2 marked today there. A global
      // path has no entries: the feed reads per Group (ADR-0004).
      await firestore.collection('groups').doc('g1').set({
        'name': 'Group g1',
        'ownerUid': 'u2',
        'memberCount': 2,
      });
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'role': 'member'});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('u2')
          .set({'uid': 'u2', 'role': 'owner'});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .set({'uid': 'u1', 'name': 'User', 'dateId': dateKey});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .set({'uid': 'u2', 'name': 'User Two', 'dateId': dateKey});
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u1')
          .collection('likes')
          .doc('u2')
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

      // Two cards render; like the second reader's card (u2's).
      await tester.tap(find.byIcon(Icons.favorite_border_rounded).last);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.favorite_rounded),
        findsOneWidget,
      ); // Expect filled

      final likeDoc = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .collection('likes')
          .doc('u1')
          .get();
      expect(likeDoc.exists, isTrue);

      // Unlike the same card.
      await tester.tap(find.byIcon(Icons.favorite_rounded).last);
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.favorite_border_rounded),
        findsNWidgets(2),
      ); // Both cards back to outline

      final likeDocDeleted = await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .collection('likes')
          .doc('u1')
          .get();
      expect(likeDocDeleted.exists, isFalse);
    });

    testWidgets('shows fallback text when the feed stream fails', (tester) async {
      final firestore = ThrowingFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );
      // A membership for u1 in g1, so the merged stream attaches to a Group
      // and its failing entry snapshot surfaces as a stream error rather
      // than an empty list.
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('members')
          .doc('u1')
          .set({'uid': 'u1', 'role': 'member'});

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
      await _seedGroupEntry(firestore,
          groupId: 'g1', ownerUid: 'u2', memberUid: 'u1', dateKey: dateKey);
      await firestore
          .collection('groups')
          .doc('g1')
          .collection('read_log')
          .doc(dateKey)
          .collection('entries')
          .doc('u2')
          .set({'uid': 'u2', 'name': 'User Two', 'dateId': dateKey});

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
            .collection('groups')
            .doc('g1')
            .collection('read_log')
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
