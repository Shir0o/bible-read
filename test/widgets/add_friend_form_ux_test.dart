import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/add_friend_form.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/notification_preferences_service.dart';
import 'package:bible_read/services/vibration_service.dart';
import '../helpers/mock_lottie_http_client.dart';

class StubPrefsService extends NotificationPreferencesService {
  StubPrefsService() : super(firestore: FakeFirebaseFirestore());

  @override
  Future<bool> fetchVibrationEnabled(String uid) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(setupLottieHttpOverrides);
  tearDownAll(resetHttpOverrides);

  testWidgets('AddFriendForm has correct UX properties', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Tester'),
      signedIn: true,
    );
    final service = FriendService(
      firestore: firestore,
      notificationService: NotificationService(firestore: firestore),
    );
    final vibrationService =
        VibrationService(auth: auth, prefsService: StubPrefsService());

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

    final textFieldFinder = find.byKey(const Key('addFriendEmailField'));
    expect(textFieldFinder, findsOneWidget);

    final textField = tester.widget<TextField>(textFieldFinder);

    // UX Checks
    expect(
        textField.keyboardType, TextInputType.emailAddress,
        reason: 'Keyboard type should be emailAddress');
    expect(
        textField.autofillHints, contains(AutofillHints.email),
        reason: 'AutofillHints should contain email');
    expect(
        textField.textInputAction, TextInputAction.send,
        reason: 'TextInputAction should be send');

    // Visual polish
    expect(textField.decoration?.prefixIcon, isNotNull, reason: 'Should have a prefix icon');
    expect((textField.decoration?.prefixIcon as Icon).icon, Icons.email_outlined, reason: 'Prefix icon should be email_outlined');

    // Check for AutofillGroup
    expect(find.ancestor(of: textFieldFinder, matching: find.byType(AutofillGroup)), findsOneWidget, reason: 'Should be wrapped in AutofillGroup');
  });

  testWidgets('AddFriendForm clear button appears and works', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Tester'),
      signedIn: true,
    );
    final service = FriendService(
      firestore: firestore,
      notificationService: NotificationService(firestore: firestore),
    );
    final vibrationService =
        VibrationService(auth: auth, prefsService: StubPrefsService());

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

    final textFieldFinder = find.byKey(const Key('addFriendEmailField'));
    final clearButtonFinder = find.byIcon(Icons.clear);

    // Initially clear button should not be visible
    expect(clearButtonFinder, findsNothing, reason: 'Clear button should initially be hidden');

    // Enter text
    await tester.enterText(textFieldFinder, 'test@example.com');
    await tester.pump();

    // Clear button should be visible
    expect(clearButtonFinder, findsOneWidget, reason: 'Clear button should appear when text is entered');

    // Tap clear button
    await tester.tap(clearButtonFinder);
    await tester.pump();

    // Text should be cleared
    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.controller?.text, isEmpty, reason: 'Text should be cleared');

    // Clear button should disappear
    expect(clearButtonFinder, findsNothing, reason: 'Clear button should disappear when text is empty');
  });
}
