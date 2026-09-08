// The navigation rename (issue #813): the three destinations read
// Today / Circle / Path, tapping each shows the right screen, and every
// user-facing string in the widget tree avoids the retired tab names.
//
// Behaviour seams (history stack, haptics, guards) are covered by
// main_page_test.dart and main_page_back_button_test.dart; this file asserts
// what a reader sees, plus the vocabulary guard the issue asks for.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/pages/main_page.dart';
import '../helpers/fake_google_sign_in_platform.dart';
import '../helpers/stub_vibration_service.dart';

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  @override
  Future<String?> getToken({String? vapidKey}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  setUp(() {
    GoogleSignInPlatform.instance = FakeGoogleSignInPlatform();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpMainPage(
    WidgetTester tester, {
    Size viewport = const Size(1200, 3000),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          messaging: _FakeFirebaseMessaging(),
          vibrationService: StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.byType(CheckInPage).evaluate().isNotEmpty) {
      tester.widget<CheckInPage>(find.byType(CheckInPage)).onClose();
      await tester.pumpAndSettle();
    }
  }
  testWidgets('the rail reads Today, Circle, Path top to bottom', (
    tester,
  ) async {
    await pumpMainPage(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);

    final todayY = tester.getCenter(find.text('Today')).dy;
    final circleY = tester.getCenter(find.text('Circle')).dy;
    final pathY = tester.getCenter(find.text('Path')).dy;
    expect(todayY, lessThan(circleY));
    expect(circleY, lessThan(pathY));

    // No retired name survives on the rail.
    expect(find.text('Home'), findsNothing);
    expect(find.text('Community'), findsNothing);
    expect(find.text('Journey'), findsNothing);
  });

  testWidgets('the bar reads Today, Circle, Path left to right', (
    tester,
  ) async {
    await pumpMainPage(tester, viewport: const Size(390, 844));

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('Path'), findsOneWidget);

    final todayX = tester.getCenter(find.text('Today')).dx;
    final circleX = tester.getCenter(find.text('Circle')).dx;
    final pathX = tester.getCenter(find.text('Path')).dx;
    expect(todayX, lessThan(circleX));
    expect(circleX, lessThan(pathX));

    // No retired name survives on the bar.
    expect(find.text('Home'), findsNothing);
    expect(find.text('Community'), findsNothing);
    expect(find.text('Journey'), findsNothing);
  });

  testWidgets('tapping each destination shows the right screen and marks it', (
    tester,
  ) async {
    await pumpMainPage(tester);

    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(find.text('Circle'), findsWidgets); // rail label + header title
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Path'));
    await tester.pumpAndSettle();
    expect(find.byType(JourneyPage), findsOneWidget);
  });

  testWidgets('taps are ignored when signed out', (tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: FakeFirebaseFirestore(),
          messaging: _FakeFirebaseMessaging(),
          vibrationService: StubVibrationService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Signed out: welcome/auth flow, no destinations to tap.
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.text('Circle'), findsNothing);
    expect(find.text('Path'), findsNothing);
  });

  testWidgets('no user-facing string reads Community or Journey', (
    tester,
  ) async {
    final forbidden = RegExp(r'^(community|journey)$', caseSensitive: false);

    Future<void> checkTree() async {
      final texts = tester.widgetList<Text>(
        find.byType(Text, skipOffstage: false),
      );
      for (final text in texts) {
        final value = text.data ?? text.textSpan?.toPlainText();
        if (value == null) continue;
        expect(
          forbidden.hasMatch(value.trim()),
          isFalse,
          reason: 'retired tab name in user-facing copy: "$value"',
        );
      }
      // Semantics labels are user-facing too (screen readers).
      final semantics = tester.widgetList<Semantics>(
        find.byType(Semantics, skipOffstage: false),
      );
      for (final node in semantics) {
        final label = node.properties.label;
        if (label == null || label.isEmpty) continue;
        expect(
          forbidden.hasMatch(label.trim()),
          isFalse,
          reason: 'retired tab name in semantics label: "$label"',
        );
      }
    }

    await pumpMainPage(tester);
    await checkTree();

    for (final destination in ['Circle', 'Path']) {
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      await checkTree();
    }
  });
}