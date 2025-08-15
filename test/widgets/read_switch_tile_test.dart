import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/read_switch_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('noAnimation constructor builds', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReadSwitchTile.noAnimation(
          value: false,
          onChanged: null,
        ),
      ),
    ));

    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('Tapping the tile toggles the switch and calls onChanged',
      (tester) async {
    var value = false;
    bool? callbackValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ReadSwitchTile(
              value: value,
              onChanged: (newValue) {
                callbackValue = newValue;
                setState(() => value = newValue);
              },
            ),
          ),
        ),
      ),
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(ReadSwitchTile));
    await tester.pumpAndSettle();

    expect(callbackValue, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('Animations render without throwing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReadSwitchTile(
          value: false,
          onChanged: null,
        ),
      ),
    ));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReadSwitchTile(
          value: true,
          onChanged: null,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
