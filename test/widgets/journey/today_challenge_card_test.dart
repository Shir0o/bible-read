import 'package:bible_read/pages/challenges_page.dart';
import 'package:bible_read/widgets/journey/seasonal_challenge_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/stub_vibration_service.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;
  final now = DateTime(2026, 10, 16, 9);

  setUp(() {
    auth = MockFirebaseAuth(mockUser: MockUser(uid: 'u1'), signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpApp(
      Scaffold(
        body: TodayChallengeCard(
          firestore: firestore,
          auth: auth,
          vibrationService: StubVibrationService(),
          dateProvider: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders nothing without an active season', (tester) async {
    await pumpCard(tester);

    expect(find.byKey(const Key('today-challenge-card')), findsNothing);
    expect(find.textContaining('Seasonal challenge'), findsNothing);
  });

  testWidgets('an active season shows a slim card that opens challenges', (
    tester,
  ) async {
    await firestore.collection('seasons').doc('s1').set({
      'title': 'Advent Journey',
      'description': 'Walk toward the manger.',
      'startDate': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'endDate': Timestamp.fromDate(DateTime(2026, 10, 20)),
    });
    await pumpCard(tester);

    expect(find.text('Advent Journey'), findsOneWidget);
    expect(find.text('Seasonal challenge · 4 days left'), findsOneWidget);

    await tester.tap(find.byKey(const Key('today-challenge-card')));
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));
    expect(find.byType(ChallengesPage), findsOneWidget);
  });
}
