import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/add_friend_form.dart';
import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/services/error_logger.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:mocktail/mocktail.dart';

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
    if (throwError) throw Exception('fail');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  late RecordingFriendService service;
  late MockFirebaseAuth auth;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = RecordingFriendService(firestore: firestore);
    auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Tester'),
      signedIn: true,
    );
    ErrorLogger.crashlytics = MockCrashlytics();
  });

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddFriendForm(friendService: service, auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sends lowercase email and clears field on success',
      (tester) async {
    await pumpForm(tester);
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
        find.byKey(const Key('addFriendEmailField')), 'Friend@Example.COM');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(service.lastEmail, 'friend@example.com');
    expect(find.text('Request sent'), findsOneWidget);
    final textField =
        tester.widget<TextField>(find.byKey(const Key('addFriendEmailField')));
    expect(textField.controller!.text, isEmpty);
  });

  testWidgets('shows error snackbar and re-enables button on failure',
      (tester) async {
    service.throwError = true;
    await pumpForm(tester);
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });

    await tester.enterText(
        find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    final buttonFinder = find.widgetWithText(ElevatedButton, 'Send');
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(service.lastEmail, 'friend@example.com');
    expect(
        find.text('Failed to send request. Please try again.'), findsOneWidget);
    final textField =
        tester.widget<TextField>(find.byKey(const Key('addFriendEmailField')));
    expect(textField.controller!.text, 'friend@example.com');
    expect(tester.widget<ElevatedButton>(buttonFinder).onPressed, isNotNull);
  });
}
