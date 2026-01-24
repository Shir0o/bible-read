import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/status_refresh_indicator.dart';

void main() {
  testWidgets('StatusRefreshIndicator triggers onRefresh and shows loading',
      (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusRefreshIndicator(
            onRefresh: () => completer.future,
            child: ListView(children: const [Text('Item 1')]),
          ),
        ),
      ),
    );

    // Initial state: no status text
    expect(find.text('Refreshing...'), findsNothing);

    // Pull to refresh
    await tester.drag(find.text('Item 1'), const Offset(0, 150));
    await tester.pump();

    // Verify loading state
    expect(find.text('Refreshing...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Clean up
    completer.complete();
    await tester.pump(); // Resume execution

    // Finish fast animation (300ms)
    await tester.pump(const Duration(milliseconds: 500));

    // Finish success delay (1s)
    await tester.pump(const Duration(seconds: 2));

    // Final settle
    await tester.pump();
  });

  testWidgets('StatusRefreshIndicator shows success message', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusRefreshIndicator(
            onRefresh: () => completer.future,
            child: ListView(children: const [Text('Item 1')]),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Item 1'), const Offset(0, 150));
    await tester.pump();

    // Complete successfully
    completer.complete();
    await tester.pump(); // Resume execution -> setState(success)
    await tester.pump(); // Trigger build

    expect(find.text('Refreshed successfully'), findsOneWidget);

    // Verify tertiary color (success)
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    final context = tester.element(find.byType(StatusRefreshIndicator));
    final expectedColor = Theme.of(context).colorScheme.tertiary;
    expect(progress.valueColor?.value, expectedColor);

    // Finish fast animation (300ms)
    await tester.pump(const Duration(milliseconds: 500));

    // Finish success delay (1s)
    await tester.pump(const Duration(seconds: 2));

    // Final settle
    await tester.pump();

    // Should be back to idle
    expect(find.text('Refreshed successfully'), findsNothing);
  });

  testWidgets('StatusRefreshIndicator shows error message', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusRefreshIndicator(
            onRefresh: () => completer.future,
            child: ListView(children: const [Text('Item 1')]),
          ),
        ),
      ),
    );

    await tester.drag(find.text('Item 1'), const Offset(0, 150));
    await tester.pump();

    // Complete with error
    completer.completeError(Exception('Fail'));
    await tester.pump(); // Resume execution -> setState(error)
    await tester.pump(); // Trigger build

    expect(find.text('Refresh failed'), findsOneWidget);

    // Verify error color
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    final context = tester.element(find.byType(StatusRefreshIndicator));
    final expectedColor = Theme.of(context).colorScheme.error;
    expect(progress.valueColor?.value, expectedColor);

    // Finish error delay (2s)
    await tester.pump(const Duration(seconds: 3));

    // Final settle
    await tester.pump();

    // Should be back to idle
    expect(find.text('Refresh failed'), findsNothing);
  });
}
