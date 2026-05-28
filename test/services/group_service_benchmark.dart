// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bible_read/services/group_service.dart';

// Mocks
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference<T> extends Mock
    implements CollectionReference<T> {}

class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}

class MockQuerySnapshot<T> extends Mock implements QuerySnapshot<T> {}

class MockDocumentSnapshot<T> extends Mock implements DocumentSnapshot<T> {}

class MockQueryDocumentSnapshot<T> extends Mock
    implements QueryDocumentSnapshot<T> {}

class MockWriteBatch extends Mock implements WriteBatch {}

class MockQuery<T> extends Mock implements Query<T> {}

void main() {
  group('GroupService Benchmark', () {
    late MockFirebaseFirestore mockFirestore;
    late GroupService groupService;
    late MockCollectionReference<Map<String, dynamic>> groupsCollection;
    late MockDocumentReference<Map<String, dynamic>> groupDoc;
    late MockCollectionReference<Map<String, dynamic>> membersCollection;
    late MockDocumentReference<Map<String, dynamic>> memberDoc;
    late MockDocumentSnapshot<Map<String, dynamic>> memberSnap;
    late MockDocumentSnapshot<Map<String, dynamic>> groupSnap;
    late MockWriteBatch mockBatch;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      groupsCollection = MockCollectionReference();
      groupDoc = MockDocumentReference();
      membersCollection = MockCollectionReference();
      memberDoc = MockDocumentReference();
      memberSnap = MockDocumentSnapshot();
      groupSnap = MockDocumentSnapshot();
      mockBatch = MockWriteBatch();

      // Register fallback values
      registerFallbackValue(groupDoc);
      registerFallbackValue(memberDoc); // For batch.delete(memberRef)

      when(
        () => mockFirestore.collection(GroupCollections.groups),
      ).thenReturn(groupsCollection);
      when(() => groupsCollection.doc(any())).thenReturn(groupDoc);
      when(
        () => groupDoc.collection(GroupCollections.members),
      ).thenReturn(membersCollection);
      when(() => membersCollection.doc(any())).thenReturn(memberDoc);
      when(() => memberDoc.get()).thenAnswer((_) async => memberSnap);
      when(() => memberSnap.exists).thenReturn(true);

      // EnsureMemberCount setup
      when(() => groupDoc.get()).thenAnswer((_) async => groupSnap);
      when(() => groupSnap.exists).thenReturn(true);
      when(() => groupSnap.data()).thenReturn({'memberCount': 10});

      when(() => mockFirestore.batch()).thenReturn(mockBatch);
      when(() => mockBatch.commit()).thenAnswer((_) async {});

      // Cleanup progress summary
      final summaryCollection = MockCollectionReference<Map<String, dynamic>>();
      final summaryDoc = MockDocumentReference<Map<String, dynamic>>();
      final entriesCollection = MockCollectionReference<Map<String, dynamic>>();
      final entryDoc = MockDocumentReference<Map<String, dynamic>>();

      when(
        () => groupDoc.collection('progressSummary'),
      ).thenReturn(summaryCollection);
      when(() => summaryCollection.doc('data')).thenReturn(summaryDoc);
      when(
        () => summaryDoc.collection('entries'),
      ).thenReturn(entriesCollection);
      when(() => entriesCollection.doc(any())).thenReturn(entryDoc);
      when(() => entryDoc.delete()).thenAnswer((_) async {});

      groupService = GroupService(firestore: mockFirestore);
    });

    test('leaveGroup uses batch writes and avoids N+1 deletes', () async {
      final progressCollection =
          MockCollectionReference<Map<String, dynamic>>();
      final datesQuerySnapshot = MockQuerySnapshot<Map<String, dynamic>>();

      when(
        () => groupDoc.collection('progress'),
      ).thenReturn(progressCollection);
      when(
        () => progressCollection.get(),
      ).thenAnswer((_) async => datesQuerySnapshot);

      // Setup 2 dates
      final dateDoc1 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final dateDoc2 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final dateRef1 = MockDocumentReference<Map<String, dynamic>>();
      final dateRef2 = MockDocumentReference<Map<String, dynamic>>();

      when(() => datesQuerySnapshot.docs).thenReturn([dateDoc1, dateDoc2]);
      when(() => dateDoc1.reference).thenReturn(dateRef1);
      when(() => dateDoc2.reference).thenReturn(dateRef2);

      // Each date has entries collection
      final entriesRef1 = MockCollectionReference<Map<String, dynamic>>();
      final entriesRef2 = MockCollectionReference<Map<String, dynamic>>();
      when(() => dateRef1.collection('entries')).thenReturn(entriesRef1);
      when(() => dateRef2.collection('entries')).thenReturn(entriesRef2);

      final entryDocRef1 = MockDocumentReference<Map<String, dynamic>>();
      final entryDocRef2 = MockDocumentReference<Map<String, dynamic>>();
      when(() => entriesRef1.doc(any())).thenReturn(entryDocRef1);
      when(() => entriesRef2.doc(any())).thenReturn(entryDocRef2);

      // Each entry has items collection
      final itemsCollection1 = MockCollectionReference<Map<String, dynamic>>();
      final itemsCollection2 = MockCollectionReference<Map<String, dynamic>>();
      when(() => entryDocRef1.collection('items')).thenReturn(itemsCollection1);
      when(() => entryDocRef2.collection('items')).thenReturn(itemsCollection2);

      final itemsSnapshot1 = MockQuerySnapshot<Map<String, dynamic>>();
      final itemsSnapshot2 = MockQuerySnapshot<Map<String, dynamic>>();
      when(
        () => itemsCollection1.get(),
      ).thenAnswer((_) async => itemsSnapshot1);
      when(
        () => itemsCollection2.get(),
      ).thenAnswer((_) async => itemsSnapshot2);

      // 2 items in date 1, 3 items in date 2
      final itemDoc1_1 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final itemDoc1_2 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final itemDocRef1_1 = MockDocumentReference<Map<String, dynamic>>();
      final itemDocRef1_2 = MockDocumentReference<Map<String, dynamic>>();
      when(() => itemDoc1_1.reference).thenReturn(itemDocRef1_1);
      when(() => itemDoc1_2.reference).thenReturn(itemDocRef1_2);
      when(() => itemsSnapshot1.docs).thenReturn([itemDoc1_1, itemDoc1_2]);

      // Stub delete calls just in case, but we verify they are NOT called
      when(() => itemDocRef1_1.delete()).thenAnswer((_) async {});
      when(() => itemDocRef1_2.delete()).thenAnswer((_) async {});

      final itemDoc2_1 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final itemDoc2_2 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final itemDoc2_3 = MockQueryDocumentSnapshot<Map<String, dynamic>>();
      final itemDocRef2_1 = MockDocumentReference<Map<String, dynamic>>();
      final itemDocRef2_2 = MockDocumentReference<Map<String, dynamic>>();
      final itemDocRef2_3 = MockDocumentReference<Map<String, dynamic>>();
      when(() => itemDoc2_1.reference).thenReturn(itemDocRef2_1);
      when(() => itemDoc2_2.reference).thenReturn(itemDocRef2_2);
      when(() => itemDoc2_3.reference).thenReturn(itemDocRef2_3);
      when(
        () => itemsSnapshot2.docs,
      ).thenReturn([itemDoc2_1, itemDoc2_2, itemDoc2_3]);

      when(() => itemDocRef2_1.delete()).thenAnswer((_) async {});
      when(() => itemDocRef2_2.delete()).thenAnswer((_) async {});
      when(() => itemDocRef2_3.delete()).thenAnswer((_) async {});

      // Entry docs deletion
      when(() => entryDocRef1.delete()).thenAnswer((_) async {});
      when(() => entryDocRef2.delete()).thenAnswer((_) async {});

      await groupService.leaveGroup(groupId: 'g1', uid: 'u1');

      // Verify NO individual deletes
      verifyNever(() => itemDocRef1_1.delete());
      verifyNever(() => itemDocRef1_2.delete());
      verifyNever(() => itemDocRef2_1.delete());
      verifyNever(() => itemDocRef2_2.delete());
      verifyNever(() => itemDocRef2_3.delete());
      verifyNever(() => entryDocRef1.delete());
      verifyNever(() => entryDocRef2.delete());

      // Verify batch commits
      // 1. Initial member removal
      // 2. Cleanup of progress items (1 batch for 7 items)
      verify(() => mockBatch.commit()).called(2);

      // Verify batch deletes included the items
      verify(() => mockBatch.delete(itemDocRef1_1)).called(1);
      verify(() => mockBatch.delete(itemDocRef1_2)).called(1);
      verify(() => mockBatch.delete(itemDocRef2_1)).called(1);
      verify(() => mockBatch.delete(itemDocRef2_2)).called(1);
      verify(() => mockBatch.delete(itemDocRef2_3)).called(1);
      verify(() => mockBatch.delete(entryDocRef1)).called(1);
      verify(() => mockBatch.delete(entryDocRef2)).called(1);
    });
  });
}
