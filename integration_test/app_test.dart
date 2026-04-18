import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:bible_read/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end smoke test', (tester) async {
    app.skipMessagingSetup = true;
    app.main();
    await tester.pumpAndSettle();

    // Verify we are either on Welcome Page or Home Page
    // This basic smoke test ensures the app launches without crashing.
    final welcomeFinder = find.text('Get Started');
    final homeFinder = find.text('Home');

    // Wait for async initialization
    await Future.delayed(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    final foundWelcome = welcomeFinder.evaluate().isNotEmpty;
    final foundHome = homeFinder.evaluate().isNotEmpty;
    final foundError = find.textContaining('App verification failed').evaluate().isNotEmpty;

    if (foundError) {
      debugPrint('STUCK ON APP CHECK ERROR PAGE');
    }

    expect(foundWelcome || foundHome, isTrue,
        reason: 'Should be on Welcome or Home page. Currently found: Welcome=$foundWelcome, Home=$foundHome, Error=$foundError');
  });
}
