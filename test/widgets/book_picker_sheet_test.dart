import 'package:bible_read/widgets/book_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stub_vibration_service.dart';

/// "Choose books": a sheet of book tiles, quick sets and sections that
/// resolves to the picked books in Bible order.
void main() {
  List<String>? result;
  var closed = false;

  Future<void> openSheet(
    WidgetTester tester, {
    List<String> selected = const [],
  }) async {
    result = null;
    closed = false;
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showBookPickerSheet(
                context,
                selected: selected,
                vibrationService: const StubVibrationService(),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  bool doneEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(BookPickerKeys.done)).enabled;

  testWidgets('picks books and returns them in Bible order', (tester) async {
    await openSheet(tester);

    expect(find.text('Choose books'), findsOneWidget);
    expect(find.text('0 books · 0 chapters'), findsOneWidget);
    expect(find.text('Read in Bible order'), findsOneWidget);
    expect(doneEnabled(tester), isFalse);

    await tester.tap(find.byKey(BookPickerKeys.quickSet('Gospels')));
    await tester.tap(find.byKey(BookPickerKeys.tile('Genesis')));
    await tester.pumpAndSettle();

    expect(find.text('5 books · 139 chapters'), findsOneWidget);
    expect(doneEnabled(tester), isTrue);
    await tester.tap(find.byKey(BookPickerKeys.done));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, ['Genesis', 'Matthew', 'Mark', 'Luke', 'John']);
  });

  testWidgets('quick sets and sections add and remove whole groups', (
    tester,
  ) async {
    await openSheet(tester, selected: const ['Romans']);

    // A partly picked set adds the rest; a complete one removes them all.
    final paul = find.byKey(BookPickerKeys.quickSet("Paul's letters"));
    await tester.ensureVisible(paul);
    await tester.pumpAndSettle();
    await tester.tap(paul);
    await tester.pumpAndSettle();
    expect(find.text('13 books · 87 chapters'), findsOneWidget);
    await tester.tap(paul);
    await tester.pumpAndSettle();
    expect(find.text('0 books · 0 chapters'), findsOneWidget);

    expect(find.text('Add all'), findsWidgets);
    await tester.tap(find.byKey(BookPickerKeys.sectionToggle('The Law')));
    await tester.pumpAndSettle();
    expect(find.text('5 books · 187 chapters'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(BookPickerKeys.sectionToggle('The Law')),
        matching: find.text('Remove all'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(BookPickerKeys.clear));
    await tester.pumpAndSettle();
    expect(find.text('0 books · 0 chapters'), findsOneWidget);
  });

  testWidgets('search narrows the tiles', (tester) async {
    await openSheet(tester);

    await tester.enterText(find.byKey(BookPickerKeys.search), 'john');
    await tester.pumpAndSettle();

    expect(find.byKey(BookPickerKeys.tile('John')), findsOneWidget);
    expect(find.byKey(BookPickerKeys.tile('1 John')), findsOneWidget);
    expect(find.byKey(BookPickerKeys.tile('Genesis')), findsNothing);
    expect(find.text('The Law'), findsNothing);
  });

  testWidgets('closing the sheet resolves to null', (tester) async {
    await openSheet(tester, selected: const ['Ruth']);

    await tester.tap(find.byKey(BookPickerKeys.tile('Jonah')));
    await tester.tap(find.byKey(BookPickerKeys.close));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
  });
}
