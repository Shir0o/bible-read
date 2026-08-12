// Verifies the reflection editor opens ON TOP of the check-in screen ("draws
// up") instead of popping back to Home first — so the user can reflect and
// then finish with "Done" on the check-in page itself.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/check_in_page.dart';
import 'package:bible_read/pages/home_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/services/bible_progress_service.dart';
import 'helpers/mock_lottie_http_client.dart';

class _StubBibleProgressService extends BibleProgressService {
  _StubBibleProgressService() : super(firestore: FakeFirebaseFirestore());
}

Widget _host(Widget home) => MaterialApp(
      theme:
          ThemeData(useMaterial3: true, splashFactory: NoSplash.splashFactory),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
    setupLottieHttpOverrides();
  });
  tearDownAll(resetHttpOverrides);

  testWidgets(
    'reflection sheet draws up over the check-in page, then Done returns home',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'u1'),
        signedIn: true,
      );

      await tester.pumpWidget(
        _host(
          HomePage(
            firestore: firestore,
            auth: auth,
            vibrationService: const VibrationService(),
            bibleProgressService: _StubBibleProgressService(),
            dateProvider: () => DateTime.now(),
          ),
        ),
      );
      // Initial load, then the CheckInPage auto-opens (not read today).
      await tester.pumpAndSettle(const Duration(milliseconds: 1500));

      expect(find.byType(CheckInPage), findsOneWidget);
      expect(find.text('I READ'), findsOneWidget);

      // Mark as read on the check-in screen.
      await tester.tap(find.text('I READ'));
      await tester.pumpAndSettle();
      expect(find.text('Thank you for being here'), findsOneWidget);

      // Open the reflection editor — it must draw up OVER the check-in page,
      // not pop back to Home first.
      await tester.tap(find.text('Add a reflection'));
      await tester.pumpAndSettle();

      expect(
        find.byType(CheckInPage),
        findsOneWidget,
        reason: 'Opening the reflection must keep the check-in page on stage',
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('REFLECTION'), findsOneWidget);

      // Save a reflection; the sheet closes but the check-in page remains.
      await tester.enterText(
        find.byType(TextField),
        'Showing up is the whole thing.',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CheckInPage), findsOneWidget);
      expect(find.text('Thank you for being here'), findsOneWidget);

      // Only now does Done leave the check-in screen and return to Home.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(CheckInPage), findsNothing);
      expect(find.text('Thank you for being here'), findsNothing);
    },
  );
}
