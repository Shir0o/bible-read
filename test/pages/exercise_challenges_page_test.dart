import 'package:bible_read/models/exercise_challenge.dart';
import 'package:bible_read/pages/exercise_challenges_page.dart';
import 'package:bible_read/pages/main_page.dart';
import 'package:bible_read/widgets/profile_button.dart';
import 'package:bible_read/services/exercise_tracker_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingVibrationService extends VibrationService {
  int mediumCount = 0;
  int lightCount = 0;

  @override
  Future<void> mediumImpact() async {
    mediumCount += 1;
  }

  @override
  Future<void> lightImpact() async {
    lightCount += 1;
  }
}

class _FakeGoogleSignInPlatform extends GoogleSignInPlatform
    with MockPlatformInterfaceMixin {
  GoogleSignInUserData? user;

  @override
  Future<void> init({
    List<String> scopes = const <String>[],
    SignInOption signInOption = SignInOption.standard,
    String? hostedDomain,
    String? clientId,
  }) async {}

  @override
  Future<GoogleSignInUserData?> signInSilently() async => user;

  @override
  Future<GoogleSignInUserData?> signIn() async => user;

  @override
  Future<GoogleSignInTokenData> getTokens({
    required String email,
    bool? shouldRecoverAuth,
  }) async {
    return GoogleSignInTokenData(
      idToken: 'idToken',
      accessToken: 'accessToken',
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> isSignedIn() async => user != null;

  @override
  Future<void> clearAuthCache({required String token}) async {}

  @override
  Future<bool> requestScopes(List<String> scopes) async => true;

  @override
  Future<bool> canAccessScopes(List<String> scopes,
          {String? accessToken}) async =>
      true;

  @override
  Stream<GoogleSignInUserData?>? get userDataEvents => null;
}

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  _FakeFirebaseMessaging(this._token);

  final String? _token;

  @override
  Future<String?> getToken({String? vapidKey}) async => _token;

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    return const NotificationSettings(
      alert: AppleNotificationSetting.enabled,
      announcement: AppleNotificationSetting.enabled,
      authorizationStatus: AuthorizationStatus.authorized,
      badge: AppleNotificationSetting.enabled,
      carPlay: AppleNotificationSetting.enabled,
      lockScreen: AppleNotificationSetting.enabled,
      notificationCenter: AppleNotificationSetting.enabled,
      showPreviews: AppleShowPreviewSetting.always,
      timeSensitive: AppleNotificationSetting.enabled,
      criticalAlert: AppleNotificationSetting.enabled,
      sound: AppleNotificationSetting.enabled,
      providesAppNotificationSettings: AppleNotificationSetting.disabled,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  group('ExerciseChallengesPage', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late ExerciseTrackerService service;
    late MockUser user;
    late DateTime now;
    late _RecordingVibrationService vibration;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      user = MockUser(uid: 'user-1', email: 'user@test.com');
      auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      now = DateTime(2024, 5, 10, 9, 0);
      service = ExerciseTrackerService(
        firestore: firestore,
        auth: auth,
        clock: () => now,
      );
      vibration = _RecordingVibrationService();
    });

    testWidgets('creating a challenge through the form shows it in the list',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseChallengesPage(
            service: service,
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('For bodily exercise is profitable for a little'),
        findsOneWidget,
      );
      expect(find.text('1 Timothy 4:8'), findsOneWidget);
      expect(find.text('No exercise challenges yet.'), findsOneWidget);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Challenge name'),
        'Morning Ride',
      );

      await tester.tap(find.text('reps').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('minutes').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily goal'),
        '30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Total target (optional)'),
        '600',
      );

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(find.text('Morning Ride'), findsOneWidget);
      expect(
        find.text('Goal: at least 30.00 minutes per day'),
        findsOneWidget,
      );
      expect(vibration.mediumCount, 1);
    });

    testWidgets('editing a challenge updates the rendered summary',
        (tester) async {
      final existing = await service.upsertChallenge(
        ExerciseChallenge(
          id: '',
          uid: '',
          name: 'Morning Run',
          unit: 'minutes',
          dailyGoal: 30,
          targetType: ExerciseTargetType.atLeast,
          totalTarget: 200,
        ),
      );
      await service.recordDailyAmount(challenge: existing, amount: 15);

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseChallengesPage(
            service: service,
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('For bodily exercise is profitable for a little'),
        findsOneWidget,
      );
      expect(find.text('1 Timothy 4:8'), findsOneWidget);
      expect(find.text('Morning Run'), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.text('Edit'),
          matching:
              find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Challenge name'),
        'Evening Run',
      );
      await tester.tap(find.text('minutes').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom unit').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Custom unit'),
        'miles',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Daily goal'),
        '45',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Total target (optional)'),
        '900',
      );

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Evening Run'), findsOneWidget);
      expect(
        find.text('Goal: at least 45.00 miles per day'),
        findsOneWidget,
      );
      expect(vibration.mediumCount, 1);
    });

    testWidgets('deleting a challenge requires confirmation and refreshes list',
        (tester) async {
      final challenge = await service.upsertChallenge(
        ExerciseChallenge(
          id: '',
          uid: '',
          name: 'Morning Yoga',
          unit: 'minutes',
          dailyGoal: 20,
          targetType: ExerciseTargetType.atLeast,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ExerciseChallengesPage(
            service: service,
            vibrationService: vibration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Morning Yoga'), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.text('Delete'),
          matching:
              find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete challenge?'), findsOneWidget);
      expect(find.textContaining('Morning Yoga'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Morning Yoga'), findsNothing);
      expect(find.text('Morning Yoga deleted.'), findsOneWidget);
      expect(vibration.lightCount, 1);

      final doc = await service.firestore
          .collection(ExerciseTrackerPaths.users)
          .doc(challenge.uid)
          .collection(ExerciseTrackerPaths.challenges)
          .doc(challenge.id)
          .get();
      expect(doc.exists, isFalse);
    });
  });

  group('MainPage navigation', () {
    late FakeFirebaseFirestore firestore;
    late MockFirebaseAuth auth;
    late _RecordingVibrationService vibration;
    late _FakeGoogleSignInPlatform google;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'user-1', photoURL: null),
        signedIn: true,
      );
      vibration = _RecordingVibrationService();
      google = _FakeGoogleSignInPlatform();
      google.user = GoogleSignInUserData(
        email: 'user@test.com',
        id: 'user-1',
        displayName: 'User One',
      );
      GoogleSignInPlatform.instance = google;
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('menu entry opens exercise challenges page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MainPage(
            firestore: firestore,
            auth: auth,
            vibrationService: vibration,
            messaging: _FakeFirebaseMessaging('token'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Tap on the ProfileButton to open menu
      await tester.tap(find.byType(ProfileButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The AppMenuSheet should now be visible.
      // Tap on the 'Challenges' item in the menu.
      await tester.tap(find.text('Challenges'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify that the ChallengesPage is displayed.
      expect(find.text('Challenges'), findsOneWidget);

      // Switch to Exercise tab
      await tester.tap(find.text('Exercise'));
      await tester.pumpAndSettle();

      expect(find.text('No exercise challenges yet.'), findsOneWidget);
      expect(
        find.textContaining('For bodily exercise is profitable for a little'),
        findsOneWidget,
      );
      expect(find.text('1 Timothy 4:8'), findsOneWidget);
    });
  });
}
