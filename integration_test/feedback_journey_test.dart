import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/feedback_page.dart';
import 'package:bible_read/pages/admin/feedback_admin_page.dart';
import 'package:bible_read/services/feedback_service.dart';
import 'package:bible_read/services/admin_role_service.dart';
import 'helpers/screenshot_helper.dart';

void main() {
  initScreenshotBinding();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('Feedback Journey', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late MockUser user;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      user = MockUser(
        uid: 'u1',
        email: 'test@example.com',
        displayName: 'Test User',
      );
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    });

    testWidgets('submit a bug report and a feature request', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FeedbackPage(
                          feedbackService:
                              FeedbackService(auth: auth, firestore: firestore),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Feedback'),
                ),
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Feedback Page
      await tester.tap(find.text('Open Feedback'));
      await tester.pumpAndSettle();

      // Submit Bug Report
      await tester.enterText(
          find.byKey(const ValueKey('bugTitleField')), 'Crash on home');
      await tester.enterText(find.byKey(const ValueKey('bugDescriptionField')),
          'The app crashes when I tap home.');
      await tester.enterText(find.byKey(const ValueKey('bugStepsField')),
          '1. Open app\n2. Tap home');

      final submitBugButton = find.byKey(const ValueKey('bugSubmitButton'));
      await tester.ensureVisible(submitBugButton);
      await tester.tap(submitBugButton);
      await tester.pumpAndSettle();

      // Verify bug report in Firestore
      final bugDocs = await firestore.collection('bugReports').get();
      expect(bugDocs.docs.length, 1);
      expect(bugDocs.docs.first.data()['title'], 'Crash on home');
      expect(bugDocs.docs.first.data()['status'], 'open');

      // FeedbackPage should have popped back to home
      expect(find.text('Open Feedback'), findsOneWidget);

      // Open Feedback Page again for Feature Request
      await tester.tap(find.text('Open Feedback'));
      await tester.pumpAndSettle();

      // Tap Feature tab
      await tester.tap(find.text('Request a Feature'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const ValueKey('featureTitleField')), 'Dark mode');
      await tester.enterText(
          find.byKey(const ValueKey('featureDescriptionField')),
          'I want dark mode.');

      final submitFeatureButton =
          find.byKey(const ValueKey('featureSubmitButton'));
      await tester.ensureVisible(submitFeatureButton);
      await tester.tap(submitFeatureButton);
      await tester.pumpAndSettle();

      // Verify feature request in Firestore
      final featureDocs = await firestore.collection('featureRequests').get();
      expect(featureDocs.docs.length, 1);
      expect(featureDocs.docs.first.data()['title'], 'Dark mode');
    });

    testWidgets('admin can triage and resolve feedback', (tester) async {
      // Seed some feedback
      final docRef = await firestore.collection('bugReports').add({
        'uid': 'u1',
        'title': 'Test Bug',
        'description': 'Description',
        'status': 'open',
        'timestamp': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      // Mock admin user
      final adminUser = MockUser(uid: 'admin1', email: 'admin@test.com');
      final adminAuth = MockFirebaseAuth(mockUser: adminUser, signedIn: true);

      // Set admin role in Firestore
      await firestore.collection('users').doc('admin1').set({
        'role': 'admin',
      });

      final adminRoleService =
          AdminRoleService(auth: adminAuth, firestore: firestore);

      await tester.pumpWidget(
        MaterialApp(
          home: FeedbackAdminPage(
            firestore: firestore,
            adminRoleService: adminRoleService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Feedback Inbox'), findsOneWidget);
      expect(find.text('Test Bug'), findsOneWidget);

      // Find "Mark Resolved" button
      final resolveButton = find.byKey(ValueKey('resolveButton_${docRef.id}'));
      expect(resolveButton, findsOneWidget);
      await tester.tap(resolveButton);
      await tester.pumpAndSettle();

      // Enter notes in dialog
      expect(
          find.byKey(const ValueKey('resolutionNotesField')), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('resolutionNotesField')), 'Fixed in v1.1');

      // Find the "Mark Resolved" button IN THE DIALOG
      // The dialog also has a "Mark Resolved" button from the `confirmLabel`
      final dialogButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mark Resolved'),
      );
      await tester.tap(dialogButton);
      await tester.pumpAndSettle();

      // Verify update in Firestore
      final bugDocs = await firestore.collection('bugReports').get();
      expect(bugDocs.docs.first.data()['status'], 'resolved');
      expect(bugDocs.docs.first.data()['resolutionNotes'], 'Fixed in v1.1');
    });

    testWidgets('admin can mark feedback as not applicable', (tester) async {
      // Seed some feedback
      final docRef = await firestore.collection('featureRequests').add({
        'uid': 'u2',
        'title': 'Test Feature',
        'description': 'Something impossible',
        'status': 'open',
        'timestamp': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      // Mock admin user
      final adminUser = MockUser(uid: 'admin2', email: 'admin2@test.com');
      final adminAuth = MockFirebaseAuth(mockUser: adminUser, signedIn: true);
      await firestore.collection('users').doc('admin2').set({'role': 'admin'});
      final adminRoleService =
          AdminRoleService(auth: adminAuth, firestore: firestore);

      await tester.pumpWidget(
        MaterialApp(
          home: FeedbackAdminPage(
            firestore: firestore,
            adminRoleService: adminRoleService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Feature Requests tab
      await tester.tap(find.text('Feature Requests'));
      await tester.pumpAndSettle();

      expect(find.text('Test Feature'), findsOneWidget);

      // Find "Mark Not Applicable" button
      final naButton = find.byKey(ValueKey('notApplicableButton_${docRef.id}'));
      expect(naButton, findsOneWidget);
      await tester.tap(naButton);
      await tester.pumpAndSettle();

      // Enter notes in dialog
      await tester.enterText(
          find.byKey(const ValueKey('resolutionNotesField')), 'Out of scope');

      final dialogButton = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mark Not Applicable'),
      );
      await tester.tap(dialogButton);
      await tester.pumpAndSettle();

      // Verify update in Firestore
      final featureDocs = await firestore.collection('featureRequests').get();
      expect(featureDocs.docs.first.data()['status'], 'notApplicable');
      expect(featureDocs.docs.first.data()['resolutionNotes'], 'Out of scope');
    });
  });
}
