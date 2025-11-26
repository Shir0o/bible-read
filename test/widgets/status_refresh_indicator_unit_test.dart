import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/status_refresh_indicator.dart';
import 'package:bible_read/theme/app_theme.dart';

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

  testWidgets('StatusRefreshIndicator clamps visual offset to maxHeight', (WidgetTester tester) async {
    final refreshCompleter = Completer<void>();
    const double maxHeight = 100.0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatusRefreshIndicator(
          maxHeight: maxHeight,
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

    final gesture = await tester.startGesture(tester.getCenter(find.byType(ListView)));

    // Drag well past the maxHeight (e.g., 300px)
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();

    // Verify the indicator container height is clamped to maxHeight
    // We can find the Container with the specific decoration color we used.
    final containerFinder = find.byWidgetPredicate((widget) {
      if (widget is Container && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        if (decoration.color == AppTheme.backgroundColor) {
          return widget.constraints?.maxHeight == maxHeight || widget.constraints?.minHeight == maxHeight;
        }
      }
      return false;
    });

    // Note: Finding by constraints is tricky because constraints are passed down.
    // Instead, let's check the OverflowBox logic or just rely on the fact that
    // if it wasn't clamped, the render object would be larger?
    // A better way is to inspect the size of the widget.

    // However, since we are inside a Stack, getting the size of the generated Container is the most direct way.
    // The Container in our widget has `height: containerHeight`.
    // Let's look for a Container with the specific decoration and verify its height.
    // But `height` property on Container is effectively what we set.

    final container = tester.widget<Container>(find.byWidgetPredicate((widget) {
       if (widget is Container && widget.decoration is BoxDecoration) {
        final decoration = widget.decoration as BoxDecoration;
        return decoration.color == AppTheme.backgroundColor;
      }
      return false;
    }));

    // We expect the Container's height to be exactly maxHeight (100.0), not 300.0.
    // Note: container.constraints might be null if height is set directly?
    // If height is set, constraints becomes BoxConstraints.tightFor(height: height).

    // The Container is created with `height: containerHeight`.
    // We need to check if we can access `height` but Container doesn't expose it directly if it's private or used in constraints.
    // Actually Container stores it in `constraints`.

    expect(container.constraints!.maxHeight, equals(maxHeight));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
