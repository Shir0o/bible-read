import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/pages/app_check_error_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows app check error message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AppCheckErrorPage()),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'App verification failed. Please reinstall or check your device.',
      ),
      findsOneWidget,
    );
  });
}
