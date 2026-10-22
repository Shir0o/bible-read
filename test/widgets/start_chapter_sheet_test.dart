import 'package:bible_read/widgets/group_plan_keys.dart';
import 'package:bible_read/widgets/start_chapter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stub_vibration_service.dart';

/// "Day one begins at": picks a chapter and, where the caller allows it, says
/// whether the chapters before it are left out or already read.
void main() {
  Future<Future<StartChapterChoice?> Function()> pumpSheet(
    WidgetTester tester, {
    String currentRef = 'Genesis 1',
    bool allowMarkAsRead = false,
  }) async {
    StartChapterChoice? result;
    var closed = false;
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showStartChapterSheet(
                context,
                books: const ['Genesis', 'Exodus'],
                currentRef: currentRef,
                allowMarkAsRead: allowMarkAsRead,
                vibrationService: const StubVibrationService(),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    return () async {
      expect(closed, isTrue);
      return result;
    };
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('at the very beginning nothing is left out', (tester) async {
    final result = await pumpSheet(tester);
    await open(tester);

    expect(find.text('Day one begins at'), findsOneWidget);
    expect(find.text('Pick a book, then a chapter.'), findsOneWidget);
    expect(
      find.text('This is the very beginning. Nothing is left out.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Begin at Genesis 1'));
    await tester.pumpAndSettle();

    final choice = await result();
    expect(choice!.ref, 'Genesis 1');
    expect(choice.markEarlierRead, isFalse);
  });

  testWidgets('without allowMarkAsRead earlier chapters are left out', (
    tester,
  ) async {
    final result = await pumpSheet(tester);
    await open(tester);

    await tester.tap(find.byKey(GroupPlanKeys.startSheetChapter(5)));
    await tester.pumpAndSettle();

    expect(find.text('4 chapters come before Genesis 5'), findsOneWidget);
    expect(find.text('Leave them out'), findsOneWidget);
    expect(find.text('Day one is Genesis 5.'), findsOneWidget);
    expect(find.byKey(GroupPlanKeys.startSheetMarkRead), findsNothing);
    await tester.tap(find.text('Begin at Genesis 5'));
    await tester.pumpAndSettle();

    final choice = await result();
    expect(choice!.ref, 'Genesis 5');
    expect(choice.markEarlierRead, isFalse);
  });

  testWidgets("with allowMarkAsRead the reader can say they've read them", (
    tester,
  ) async {
    final result = await pumpSheet(tester, allowMarkAsRead: true);
    await open(tester);

    await tester.tap(find.byKey(GroupPlanKeys.startSheetBookPill('Exodus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupPlanKeys.startSheetChapter(1)));
    await tester.pumpAndSettle();

    expect(find.text('50 chapters come before Exodus 1'), findsOneWidget);
    expect(
      find.text('They count as read, and you pick up at Exodus 1 today.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(GroupPlanKeys.startSheetMarkRead));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(GroupPlanKeys.startSheetCta));
    await tester.pumpAndSettle();

    final choice = await result();
    expect(choice!.ref, 'Exodus 1');
    expect(choice.markEarlierRead, isTrue);
  });

  testWidgets('closing the sheet resolves to null', (tester) async {
    final result = await pumpSheet(tester, currentRef: 'Exodus 3');
    await open(tester);

    await tester.tap(find.byKey(GroupPlanKeys.startSheetClose));
    await tester.pumpAndSettle();

    expect(await result(), isNull);
  });
}
