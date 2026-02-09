import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mocktail/mocktail.dart';

import 'package:bible_read/widgets/achievement_summary.dart';
import 'package:bible_read/widgets/badge_icon.dart';
import 'package:bible_read/widgets/success_animation.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/pages/achievements_page.dart';
import '../helpers/mock_lottie_http_client.dart';

class _TestVibrationService extends VibrationService {
  const _TestVibrationService() : super();

  @override
  Future<void> tap() async {}

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> heavyImpact() async {}
}

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

class FakeRoute extends Fake implements Route {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    setupLottieHttpOverrides();
    registerFallbackValue(FakeRoute());
  });
  tearDownAll(resetHttpOverrides);

  const vibration = _TestVibrationService();

  testWidgets('returns empty widget when no user', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(signedIn: false);

    await tester.pumpWidget(
      MaterialApp(
        home: AchievementSummary(
          firestore: firestore,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SizedBox), findsOneWidget);
  });

  testWidgets('shows count and badge when achievements exist', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u1');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('a1')
        .set({
      'title': 'First',
      'type': 'test',
      'dateUnlocked': Timestamp.fromDate(DateTime(2023)),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AchievementSummary(
          firestore: firestore,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Achievements'), findsOneWidget);
    expect(find.byType(BadgeIcon), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('shows message when no achievements', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u2');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: AchievementSummary(
          firestore: firestore,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No achievements yet'), findsOneWidget);
  });

  testWidgets('shows success animation when achievement unlocked',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u3');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);

    await tester.pumpWidget(
      MaterialApp(
        home: AchievementSummary(
          firestore: firestore,
          auth: auth,
          vibrationService: vibration,
        ),
      ),
    );
    await tester.pump();

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('achievements')
        .doc('a1')
        .set({
      'title': 'First',
      'type': 'test',
      'dateUnlocked': Timestamp.fromDate(DateTime(2023)),
    });

    await tester.pump();
    await tester.pump();

    expect(find.byType(SuccessAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    addTearDown(() async {
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
    });
  });

  testWidgets('navigates to achievements page on tap', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final user = MockUser(uid: 'u4');
    final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
    final observer = MockNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        home: AchievementSummary(
          firestore: firestore,
          auth: auth,
          vibrationService: vibration,
        ),
        navigatorObservers: [observer],
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state
    expect(find.text('No achievements yet'), findsOneWidget);

    // Tap the widget
    await tester.tap(find.text('No achievements yet'));
    await tester.pumpAndSettle();

    // Verify navigation
    verify(() => observer.didPush(any(), any())).called(greaterThan(0));
    expect(find.byType(AchievementsPage), findsOneWidget);
  });
}
