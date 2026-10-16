import 'package:bible_read/pages/feedback_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/services/feedback_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFeedbackService extends Mock implements FeedbackService {}

class _NoopVibrationService extends VibrationService {
  const _NoopVibrationService();

  @override
  Future<void> tap() async {}

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> heavyImpact() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Feedback flows', () {
    testWidgets('SettingsPage bug feedback flow submits report', (
      tester,
    ) async {
      final mockService = _MockFeedbackService();
      when(
        () => mockService.submitBugReport(
          title: 'Crash on load',
          description: 'The app crashes after opening.',
          reproductionSteps: 'Open the app and wait 5 seconds.',
        ),
      ).thenAnswer((_) async {});

      final mockAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'user-1',
          email: 'user@example.com',
          displayName: 'Test User',
        ),
      );
      final fakeFirestore = FakeFirebaseFirestore();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            auth: mockAuth,
            firestore: fakeFirestore,
            vibrationService: const _NoopVibrationService(),
            feedbackService: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bugFinder = find.text('Report a bug');
      await tester.ensureVisible(bugFinder);
      await tester.tap(bugFinder);
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackPage), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('bugTitleField')),
        'Crash on load',
      );
      await tester.enterText(
        find.byKey(const ValueKey('bugDescriptionField')),
        'The app crashes after opening.',
      );
      await tester.enterText(
        find.byKey(const ValueKey('bugStepsField')),
        'Open the app and wait 5 seconds.',
      );

      await tester.tap(find.byKey(const ValueKey('bugSubmitButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(
        () => mockService.submitBugReport(
          title: 'Crash on load',
          description: 'The app crashes after opening.',
          reproductionSteps: 'Open the app and wait 5 seconds.',
        ),
      ).called(1);
      expect(
        find.text('Bug report submitted! Thank you for letting us know.'),
        findsOneWidget,
      );
    });
  });
}
