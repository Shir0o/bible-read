import 'package:bible_read/pages/admin/feedback_admin_page.dart';
import 'package:bible_read/services/admin_role_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:bible_read/services/error_logger.dart';

class _AdminRoleStub extends AdminRoleService {
  _AdminRoleStub(
    this._isAdmin, {
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  }) : super(auth: auth, firestore: firestore);

  final bool _isAdmin;

  @override
  Future<bool> isAdmin({bool allowStale = true}) async => _isAdmin;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FeedbackAdminPage', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;

    setUp(() {
      ErrorLogger.muteForTest = true;
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'admin-1', email: 'admin@example.com'),
      );
    });

    Future<void> pumpPage(
      WidgetTester tester, {
      required AdminRoleService adminRoleService,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FeedbackAdminPage(
            firestore: firestore,
            adminRoleService: adminRoleService,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('denies access when user is not admin', (tester) async {
      final service = _AdminRoleStub(false, auth: auth, firestore: firestore);

      await pumpPage(tester, adminRoleService: service);

      expect(find.textContaining('do not have permission'), findsOneWidget);
    });

    testWidgets('marking an item resolved updates status and notes', (
      tester,
    ) async {
      final service = _AdminRoleStub(true, auth: auth, firestore: firestore);
      final timestamp = Timestamp.now();
      await firestore.collection('bugReports').doc('bug1').set({
        'title': 'Crash on launch',
        'description': 'The app crashes when opening.',
        'status': 'open',
        'timestamp': timestamp,
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
        'displayName': 'Reporter',
        'email': 'reporter@example.com',
      });

      await pumpPage(tester, adminRoleService: service);

      expect(find.byKey(const ValueKey('feedbackStatus_bug1')), findsOneWidget);
      expect(find.text('Status: open'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('resolveButton_bug1')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('resolutionNotesField')),
        'Fixed in build 123',
      );
      await tester.tap(find.byKey(const ValueKey('submitResolutionNotes')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('statusFilter_bugReports')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolved').last);
      await tester.pumpAndSettle();

      expect(find.text('Status: resolved'), findsOneWidget);
      expect(find.text('Resolution notes: Fixed in build 123'), findsOneWidget);

      final updated = await firestore
          .collection('bugReports')
          .doc('bug1')
          .get();
      expect(updated.data()?['status'], 'resolved');
      expect(updated.data()?['resolutionNotes'], 'Fixed in build 123');
      expect(updated.data()?['resolvedAt'], isA<Timestamp>());
    });

    testWidgets('marking not applicable updates status and filter', (
      tester,
    ) async {
      final service = _AdminRoleStub(true, auth: auth, firestore: firestore);
      final timestamp = Timestamp.now();
      await firestore.collection('featureRequests').doc('feature1').set({
        'title': 'Add offline mode',
        'description': 'Allow reading offline.',
        'status': 'open',
        'timestamp': timestamp,
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
        'displayName': 'User One',
        'email': 'user1@example.com',
      });

      await pumpPage(tester, adminRoleService: service);
      await tester.tap(find.text('Feature Requests'));
      await tester.pumpAndSettle();

      await tester.pump();
      expect(
        find.byKey(const ValueKey('notApplicableButton_feature1')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('notApplicableButton_feature1')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('resolutionNotesField')),
        'Not aligned with roadmap',
      );
      await tester.tap(find.byKey(const ValueKey('submitResolutionNotes')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('statusFilter_featureRequests')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not Applicable').last);
      await tester.pumpAndSettle();

      expect(find.text('Status: notApplicable'), findsOneWidget);
      expect(
        find.text('Resolution notes: Not aligned with roadmap'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('feedbackCard_feature1')),
        findsOneWidget,
      );

      final updated = await firestore
          .collection('featureRequests')
          .doc('feature1')
          .get();
      expect(updated.data()?['status'], 'notApplicable');
      expect(updated.data()?['resolutionNotes'], 'Not aligned with roadmap');
      expect(updated.data()?['resolvedAt'], isA<Timestamp>());
    });

    testWidgets('failed update shows error and reverts optimistic state', (
      tester,
    ) async {
      final service = _AdminRoleStub(true, auth: auth, firestore: firestore);
      final timestamp = Timestamp.now();
      final docRef = firestore.collection('bugReports').doc('bug-error');
      await docRef.set({
        'title': 'Feedback to fail',
        'description': 'Trigger a Firestore error.',
        'status': 'open',
        'timestamp': timestamp,
        'updatedAt': timestamp,
        'resolvedAt': null,
        'resolutionNotes': null,
        'displayName': 'Debugger',
        'email': 'debugger@example.com',
      });

      whenCalling(Invocation.method(#update, [anything]))
          .on(docRef)
          .thenThrow(
            FirebaseException(
              plugin: 'FakeFirestore',
              code: 'permission-denied',
              message: 'Simulated failure',
            ),
          );

      await pumpPage(tester, adminRoleService: service);

      await tester.tap(find.byKey(const ValueKey('resolveButton_bug-error')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('resolutionNotesField')),
        'Attempted fix',
      );
      await tester.tap(find.byKey(const ValueKey('submitResolutionNotes')));

      await tester.pump();
      await tester.pump();
      expect(find.text('Status: open'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('resolveButton_bug-error')),
        findsOneWidget,
      );

      expect(
        find.text('Failed to update feedback. Please try again.'),
        findsOneWidget,
      );

      final snapshot = await docRef.get();
      expect(snapshot.data()?['status'], 'open');
      expect(snapshot.data()?['resolutionNotes'], isNull);
    });
  });
}
