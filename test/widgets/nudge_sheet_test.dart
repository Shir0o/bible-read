import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/services/friend_service.dart';
import 'package:bible_read/widgets/nudge_sheet.dart';

Widget _host({required Future<NudgeResult> Function(String) onSend}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showNudgeSheet(
              context,
              person: const NudgePerson(name: 'Mona Lisa'),
              onSend: onSend,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sends a preset note and shows confirmation', (tester) async {
    String? captured;
    await tester.pumpWidget(
      _host(
        onSend: (m) async {
          captured = m;
          return NudgeResult.sent;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Nudge Mona'), findsOneWidget);
    expect(find.text(kNudgePresets.first), findsOneWidget);

    await tester.tap(find.text('Send nudge'));
    await tester.pumpAndSettle();

    expect(captured, kNudgePresets.first);
    expect(find.text('Nudge sent to Mona'), findsOneWidget);
  });

  testWidgets('write-your-own captures custom text', (tester) async {
    String? captured;
    await tester.pumpWidget(
      _host(
        onSend: (m) async {
          captured = m;
          return NudgeResult.sent;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Write your own'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Praying for you');
    await tester.pump();

    await tester.tap(find.text('Send nudge'));
    await tester.pumpAndSettle();

    expect(captured, 'Praying for you');
    expect(find.text('Nudge sent to Mona'), findsOneWidget);
  });

  testWidgets('alreadySent surfaces gentle copy without confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        onSend: (m) async {
          return NudgeResult.alreadySent;
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send nudge'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already nudged Mona'), findsOneWidget);
    expect(find.text('Nudge sent to Mona'), findsNothing);
  });
}
