import 'package:bible_read/services/feedback_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FeedbackService', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late FeedbackService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'user-123',
          email: 'user@example.com',
          displayName: 'Test User',
        ),
        signedIn: true,
      );
      service = FeedbackService(firestore: firestore, auth: auth);
    });

    test('submitBugReport stores feedback with reproduction steps', () async {
      await service.submitBugReport(
        title: 'Crash on launch',
        description: 'The app crashes immediately when opening.',
        reproductionSteps: 'Open the app after installing update.',
      );

      final snapshot = await firestore
          .collection(FeedbackCollections.bugReports)
          .get();
      expect(snapshot.docs, hasLength(1));
      final data = snapshot.docs.first.data();
      expect(data['uid'], equals('user-123'));
      expect(data['email'], equals('user@example.com'));
      expect(data['displayName'], equals('Test User'));
      expect(data['title'], equals('Crash on launch'));
      expect(
        data['description'],
        equals('The app crashes immediately when opening.'),
      );
      expect(
        data['reproductionSteps'],
        equals('Open the app after installing update.'),
      );
      expect(data['platform'], isNotEmpty);
      expect(data['timestamp'], isNotNull);
      expect(data['status'], equals('open'));
      expect(data['updatedAt'], isNotNull);
      expect(data['resolvedAt'], isNull);
      expect(data['resolutionNotes'], isNull);
    });

    test(
      'submitFeatureRequest stores feedback without optional steps',
      () async {
        await service.submitFeatureRequest(
          title: 'Reading reminders',
          description: 'Send a reminder when I miss two days.',
        );

        final snapshot = await firestore
            .collection(FeedbackCollections.featureRequests)
            .get();
        expect(snapshot.docs, hasLength(1));
        final data = snapshot.docs.first.data();
        expect(data['uid'], equals('user-123'));
        expect(data['email'], equals('user@example.com'));
        expect(data['displayName'], equals('Test User'));
        expect(data['title'], equals('Reading reminders'));
        expect(
          data['description'],
          equals('Send a reminder when I miss two days.'),
        );
        expect(data.containsKey('reproductionSteps'), isFalse);
        expect(data['platform'], isNotEmpty);
        expect(data['timestamp'], isNotNull);
        expect(data['status'], equals('open'));
        expect(data['updatedAt'], isNotNull);
        expect(data['resolvedAt'], isNull);
        expect(data['resolutionNotes'], isNull);
      },
    );
  });
}
