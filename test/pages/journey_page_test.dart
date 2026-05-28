import 'package:bible_read/pages/journey_page.dart';
import 'package:bible_read/widgets/journey/bible_library_grid.dart';
import 'package:bible_read/widgets/journey/consistency_calendar.dart';
import 'package:bible_read/widgets/app_header.dart';
import 'package:bible_read/widgets/journey/journey_progress_card.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = MockFirebaseAuth(signedIn: true);
    firestore = FakeFirebaseFirestore();
  });

  testWidgets('JourneyPage renders all main components', (tester) async {
    // Ignore overflow errors
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is FlutterError &&
          (details.exception as FlutterError).message.contains('overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };

    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() {
      FlutterError.onError = originalOnError;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPage(
          auth: auth,
          firestore: firestore,
          vibrationService: const VibrationService(),
          dateProvider: () => DateTime.now(),
        ),
      ),
    );

    // Allow futures to settle
    await tester.pumpAndSettle();

    expect(find.byType(AppHeader), findsOneWidget);
    expect(find.byType(JourneyProgressCard), findsOneWidget);
    expect(find.byType(BibleLibraryGrid), findsOneWidget);
    expect(find.byType(ConsistencyCalendar), findsOneWidget);
  });
}
