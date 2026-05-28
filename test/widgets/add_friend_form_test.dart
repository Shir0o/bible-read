import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/add_friend_form.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bible_read/widgets/animated_action_button.dart';
import 'package:bible_read/widgets/success_animation.dart';
import 'package:bible_read/services/vibration_service.dart';
import '../helpers/mock_lottie_http_client.dart';

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

class RecordingFriendService extends FriendService {
  RecordingFriendService({required FakeFirebaseFirestore firestore})
    : super(
        firestore: firestore,
        notificationService: NotificationService(firestore: firestore),
      );

  String? lastEmail;
  bool throwError = false;

  @override
  Future<void> sendFriendRequestByEmail({
    required String fromUid,
    required String fromName,
    required String toEmail,
  }) async {
    lastEmail = toEmail;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (throwError) throw Exception('fail');
  }
}

class StubPrefsService extends NotificationPreferencesService {
  StubPrefsService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<bool> fetchVibrationEnabled(String uid) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupLottieHttpOverrides);
  tearDownAll(resetHttpOverrides);

  late FakeFirebaseFirestore firestore;
  late RecordingFriendService service;
  late MockFirebaseAuth auth;

  tearDown(() {
    ErrorLogger.resetForTest();
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = RecordingFriendService(firestore: firestore);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Tester'),
      signedIn: true,
    );
    ErrorLogger.muteForTest = true;
    ErrorLogger.crashlytics = MockCrashlytics();
    when(
      () => ErrorLogger.crashlytics!.recordError(
        any(),
        any(),
        fatal: any(named: 'fatal'),
      ),
    ).thenAnswer((_) async {});
  });

  Future<void> pumpForm(WidgetTester tester) async {
    final vibrationService = VibrationService(
      auth: auth,
      prefsService: StubPrefsService(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddFriendForm(
            friendService: service,
            auth: auth,
            vibrationService: vibrationService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends lowercase email and clears field on success', (
    tester,
  ) async {
    await pumpForm(tester);
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
      find.byKey(const Key('addFriendEmailField')),
      'Friend@Example.COM',
    );
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(find.byKey(const ValueKey('spinner')), findsOneWidget);
    expect(find.text('Request sent'), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(service.lastEmail, 'friend@example.com');
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.byType(SuccessAnimation), findsOneWidget);
    expect(find.byKey(const ValueKey('spinner')), findsNothing);
    final textField = tester.widget<TextField>(
      find.byKey(const Key('addFriendEmailField')),
    );
    expect(textField.controller!.text, isEmpty);
    ScaffoldMessenger.of(
      tester.element(find.byType(SnackBar)),
    ).hideCurrentSnackBar();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows error snackbar and re-enables button on failure', (
    tester,
  ) async {
    service.throwError = true;
    await pumpForm(tester);
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
      find.byKey(const Key('addFriendEmailField')),
      'friend@example.com',
    );
    final buttonFinder = find.byType(AnimatedActionButton);
    tester.takeException(); // Clear any leftovers
    await tester.tap(buttonFinder);
    await tester.pump();

    expect(find.byKey(const ValueKey('spinner')), findsOneWidget);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      tester.takeException();
    });
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
    expect(
      find.text('Failed to send request. Please try again.'),
      findsOneWidget,
    );
    final textField = tester.widget<TextField>(
      find.byKey(const Key('addFriendEmailField')),
    );
    expect(textField.controller!.text, 'friend@example.com');
    expect(find.byKey(const ValueKey('spinner')), findsNothing);
    expect(
      tester.widget<AnimatedActionButton>(buttonFinder).onPressed,
      isNotNull,
    );
  });
}
