import 'package:bible_read/pages/feedback_page.dart';
import 'package:bible_read/pages/settings_page.dart';
import 'package:bible_read/services/feedback_service.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/app_menu_sheet.dart';
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
            friendService: FriendService(
              firestore: fakeFirestore,
              notificationService: NotificationService(
                firestore: fakeFirestore,
              ),
              acceptFriendRequestFn: ({
                required fromUid,
                required toUid,
                required fromName,
                required toName,
              }) async {},
              deleteFriendRequestPairFn: (
                  {required fromUid, required toUid}) async {},
              sendNudgeNotificationFn: ({
                required fromUid,
                required toUid,
                required fromName,
              }) async =>
                  NudgeResult.sent,
            ),
            vibrationService: const _NoopVibrationService(),
            feedbackService: mockService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bugFinder = find.text('Report a Bug');
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

    testWidgets('AppMenuSheet feedback button submits feature request', (
      tester,
    ) async {
      final mockService = _MockFeedbackService();
      when(
        () => mockService.submitFeatureRequest(
          title: 'Daily reminder',
          description: 'Send me a reminder every morning.',
          reproductionSteps: null,
        ),
      ).thenAnswer((_) async {});

      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final sheetFuture = AppMenuSheet.show(
        context: capturedContext,
        onNavigate: (_) {},
        vibrationService: const _NoopVibrationService(),
        feedbackService: mockService,
      );
      await tester.pumpAndSettle();

      final feedbackFinder = find.text('Feedback');
      await tester.dragUntilVisible(
        feedbackFinder,
        find.byKey(const Key('menu_scroll_view')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(feedbackFinder);
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackPage), findsOneWidget);
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
        1,
      );

      await tester.enterText(
        find.byKey(const ValueKey('featureTitleField')),
        'Daily reminder',
      );
      await tester.enterText(
        find.byKey(const ValueKey('featureDescriptionField')),
        'Send me a reminder every morning.',
      );

      await tester.tap(find.byKey(const ValueKey('featureSubmitButton')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(
        () => mockService.submitFeatureRequest(
          title: 'Daily reminder',
          description: 'Send me a reminder every morning.',
          reproductionSteps: null,
        ),
      ).called(1);
      expect(
        find.text('Feature request submitted! Thanks for the suggestion.'),
        findsOneWidget,
      );

      await sheetFuture;
    });
  });
}
