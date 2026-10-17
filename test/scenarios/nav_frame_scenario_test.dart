// The navigation frame (issue #982): every tab is labelled, each tab wears the
// shared header with its title, Circle and Path carry an action pill (Today
// does not), and the avatar carries the unread-notification count.
//
// The avatar sheet's contents are covered in app_menu_sheet_test.dart.

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
import 'package:bible_read/models/app_notification.dart';
import 'package:bible_read/models/notification_preferences.dart';
import 'package:bible_read/pages/create_plan_page.dart';
import 'package:bible_read/services/notification_service.dart';
import 'package:bible_read/widgets/app_header.dart';
import 'package:bible_read/widgets/app_nav_bar.dart';
import 'package:bible_read/pages/main_page.dart';
import '../helpers/fake_google_sign_in_platform.dart';
import '../helpers/stub_vibration_service.dart';

class _FakeFirebaseMessaging extends Fake implements FirebaseMessaging {
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async =>
      null;
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
    Size viewport = const Size(390, 844),
    FakeFirebaseFirestore? firestore,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'u1', displayName: 'Test User'),
      signedIn: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MainPage(
          auth: auth,
          firestore: firestore ?? FakeFirebaseFirestore(),
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

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(AppNavBar), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  AppHeader header(WidgetTester tester) =>
      tester.widget<AppHeader>(find.byType(AppHeader));

  testWidgets('the bottom bar labels every tab, selected or not', (
    tester,
  ) async {
    await pumpMainPage(tester);

    for (final label in ['Today', 'Circle', 'Path']) {
      expect(
        find.descendant(
          of: find.byType(AppNavBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: '$label label missing from the bar',
      );
    }

    // Selected tab: primary + w700; others onSurfaceVariant + w600.
    final scheme = Theme.of(tester.element(find.byType(AppNavBar))).colorScheme;
    TextStyle? styleOf(String label) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(AppNavBar),
            matching: find.text(label),
          ),
        )
        .style;
    expect(styleOf('Today')!.color, scheme.primary);
    expect(styleOf('Today')!.fontWeight, FontWeight.w700);
    expect(styleOf('Circle')!.color, scheme.onSurfaceVariant);
    expect(styleOf('Circle')!.fontWeight, FontWeight.w600);
  });

  testWidgets('the wide rail labels every tab', (tester) async {
    await pumpMainPage(tester, viewport: const Size(1200, 3000));

    final rail = find.byType(NavigationRail);
    for (final label in ['Today', 'Circle', 'Path']) {
      expect(
        find.descendant(of: rail, matching: find.text(label)),
        findsOneWidget,
      );
    }
  });

  testWidgets('each tab shows the shared header with its title', (
    tester,
  ) async {
    await pumpMainPage(tester);

    // Today: the greeting, no action pill.
    expect(find.byType(AppHeader), findsOneWidget);
    expect(header(tester).title, startsWith('Good '));
    expect(header(tester).action, isNull);

    await openTab(tester, 'Circle');
    expect(header(tester).title, 'Circle');

    await openTab(tester, 'Path');
    expect(header(tester).title, 'Path');
  });

  testWidgets('action pill: Invite on Circle, New plan on Path, none on Today',
      (
    tester,
  ) async {
    await pumpMainPage(tester);

    expect(find.text('Invite'), findsNothing);
    expect(find.text('New plan'), findsNothing);

    await openTab(tester, 'Circle');
    expect(find.text('Invite'), findsOneWidget);
    expect(find.text('New plan'), findsNothing);

    await openTab(tester, 'Path');
    expect(find.text('New plan'), findsOneWidget);
    expect(find.text('Invite'), findsNothing);
  });

  testWidgets('Path\'s New plan action opens plan creation', (tester) async {
    // Wider than a phone so the form's rows have room in the test font,
    // still narrow enough for the bottom bar.
    await pumpMainPage(tester, viewport: const Size(599, 1600));
    await openTab(tester, 'Path');

    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();

    expect(find.byType(CreatePlanPage), findsOneWidget);
  });

  testWidgets('no separate bell remains in any header', (tester) async {
    await pumpMainPage(tester);
    for (final tab in ['Today', 'Circle', 'Path']) {
      await openTab(tester, tab);
      expect(find.byTooltip('Notifications'), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
    }
  });

  testWidgets('the avatar badge counts unread notifications', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = NotificationService(firestore: firestore);
    for (var i = 0; i < 3; i++) {
      await service.addNotification(
        'u1',
        AppNotification(
          id: 'n$i',
          type: NotificationType.nudge,
          message: 'm$i',
          timestamp: DateTime(2026, 1, 1, 8, i),
          read: i == 0,
        ),
      );
    }
    await pumpMainPage(tester, firestore: firestore);

    expect(
      find.bySemanticsLabel('Open menu, 2 unread notifications'),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('with nothing unread the avatar carries no badge', (
    tester,
  ) async {
    await pumpMainPage(tester);

    expect(find.bySemanticsLabel('Open menu'), findsOneWidget);
    expect(find.textContaining('unread'), findsNothing);
  });
}
