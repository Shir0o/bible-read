import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/status_refresh_indicator.dart';

void main() {
  testWidgets('StatusRefreshIndicator shows "Pull to refresh" and "Release to refresh" text', (WidgetTester tester) async {
    final refreshCompleter = Completer<void>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatusRefreshIndicator(
          onRefresh: () => refreshCompleter.future,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            children: const [
              SizedBox(height: 1000, child: Text('Content')),
            ],
          ),
        ),
      ),
    ));

    // Start gesture
    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));

    // Drag down 50px (Status: dragging, not armed)
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();

    // Should see "Pull to refresh"
    expect(find.text('Pull to refresh'), findsOneWidget);
    expect(find.text('Release to refresh'), findsNothing);

    // Drag down another 150px (Total 200px, > 100px threshold) (Status: dragging, armed)
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump();

    // Should see "Release to refresh"
    // Note: In some test environments, physics might interfere, but we observed this passing
    // when using 'isArmed' property in the widget.
    expect(find.text('Release to refresh'), findsOneWidget);
    expect(find.text('Pull to refresh'), findsNothing);

    // Clean up
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
