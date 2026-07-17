import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/reflect_sheet.dart';

Widget _host({
  String? initialText,
  required Future<void> Function(String) onSave,
  VoidCallback? onSkip,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showReflectSheet(
              context,
              initialText: initialText,
              prompt: 'What stayed with you?',
              onSave: onSave,
              onSkip: onSkip,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('saves the entered text and closes the sheet', (tester) async {
    String? captured;
    await tester.pumpWidget(_host(onSave: (text) async {
      captured = text;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('What stayed with you?'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField),
      'Rest isn’t earned here.',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(captured, 'Rest isn’t earned here.');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Save is disabled until text is entered', (tester) async {
    var saveCalled = false;
    await tester.pumpWidget(_host(onSave: (text) async {
      saveCalled = true;
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('skip closes the sheet without saving', (tester) async {
    var saveCalled = false;
    var skipCalled = false;
    await tester.pumpWidget(_host(
      onSave: (text) async {
        saveCalled = true;
      },
      onSkip: () => skipCalled = true,
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Skip for today'), findsOneWidget);
    await tester.tap(find.text('Skip for today'));
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
    expect(skipCalled, isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('editing an existing reflection pre-fills the field and shows Cancel',
      (tester) async {
    await tester.pumpWidget(_host(
      initialText: 'Wrote it on a sticky note for my monitor.',
      onSave: (text) async {},
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Wrote it on a sticky note for my monitor.'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Skip for today'), findsNothing);
  });
}
