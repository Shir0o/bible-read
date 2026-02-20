import 'package:bible_read/pages/login_page.dart';
import 'package:bible_read/services/vibration_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:network_image_mock/network_image_mock.dart';

class MockVibrationService extends Mock implements VibrationService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });

  testWidgets('LoginPage email field has autofocus', (tester) async {
    await mockNetworkImagesFor(() async {
      final auth = MockFirebaseAuth();
      final vibrationService = MockVibrationService();
      when(() => vibrationService.lightImpact()).thenAnswer((_) async {});
      when(() => vibrationService.mediumImpact()).thenAnswer((_) async {});
      when(() => vibrationService.heavyImpact()).thenAnswer((_) async {});

      await tester.pumpWidget(MaterialApp(
        home: LoginPage(
          auth: auth,
          vibrationService: vibrationService,
        ),
      ));

      // Wait for the autofocus to kick in.
      await tester.pump();

      // Find the TextField inside the TextFormField with the key 'loginEmailField'
      final emailFieldFinder = find.descendant(
        of: find.byKey(const Key('loginEmailField')),
        matching: find.byType(TextField),
      );

      expect(emailFieldFinder, findsOneWidget);

      // Verify focus by finding the EditableText child which exposes the effective focusNode
      final editableTextFinder = find.descendant(
        of: emailFieldFinder,
        matching: find.byType(EditableText),
      );

      expect(editableTextFinder, findsOneWidget);

      final editableText = tester.widget<EditableText>(editableTextFinder);
      expect(editableText.focusNode.hasFocus, isTrue,
          reason: 'Email field should have focus');
    });
  });
}
