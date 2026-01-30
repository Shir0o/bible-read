import 'package:bible_read/services/vibration_service.dart';
import 'package:bible_read/widgets/feedback_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopVibrationService extends VibrationService {
  const _NoopVibrationService();
}

void main() {
  group('FeedbackForm UX', () {
    testWidgets('Fields have correct configuration and clear buttons',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackForm(
              tab: FeedbackTab.bug,
              onSubmit: (t, d, s) async {},
              parentMessenger: null,
              vibrationService: const _NoopVibrationService(),
            ),
          ),
        ),
      );

      // Helper to get TextField from TextFormField key
      TextField getTextField(String key) {
        return tester.widget<TextField>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(TextField),
          ),
        );
      }

      // Check Title Field
      final titleField = getTextField('bugTitleField');
      expect(titleField.textCapitalization, TextCapitalization.sentences,
          reason: 'Title should capitalize sentences');
      // Title default keyboard type is typically text, but checking explicit assignment or default

      // Check Description Field
      final descField = getTextField('bugDescriptionField');
      expect(descField.textCapitalization, TextCapitalization.sentences,
          reason: 'Description should capitalize sentences');
      expect(descField.keyboardType, TextInputType.multiline,
          reason: 'Description should have multiline keyboard type');

      // Check Steps Field
      final stepsField = getTextField('bugStepsField');
      expect(stepsField.textCapitalization, TextCapitalization.sentences,
          reason: 'Steps should capitalize sentences');
      expect(stepsField.keyboardType, TextInputType.multiline,
          reason: 'Steps should have multiline keyboard type');

      // Verify Clear Button Logic for Description
      // Initially empty, no clear button
      expect(find.byIcon(Icons.clear), findsNothing);

      // Enter text into description
      await tester.enterText(find.byKey(const ValueKey('bugDescriptionField')),
          'Some bug description');
      await tester.pump();

      // Clear button should appear
      final clearButtonFinder = find.widgetWithIcon(IconButton, Icons.clear);
      expect(clearButtonFinder, findsOneWidget,
          reason: 'Clear button should appear when text is entered');

      // Tap clear
      await tester.tap(clearButtonFinder);
      await tester.pump();

      // Text should be cleared
      expect(find.text('Some bug description'), findsNothing);
      expect(getTextField('bugDescriptionField').controller?.text, isEmpty);

      // Clear button should disappear
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });
}
