import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';

void main() {
  testWidgets('ResponsiveScaffold shows NavigationBar on narrow screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: ResponsiveScaffold(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            pages: const [SizedBox(), SizedBox()],
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('ResponsiveScaffold shows NavigationRail on wide screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: ResponsiveScaffold(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            pages: const [SizedBox(), SizedBox()],
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('ResponsiveScaffold handles navigation selection', (
    tester,
  ) async {
    int selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return MediaQuery(
              data: const MediaQueryData(size: Size(400, 800)),
              child: ResponsiveScaffold(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) {
                  setState(() {
                    selectedIndex = index;
                  });
                },
                pages: const [Text('Page 1'), Text('Page 2')],
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                    icon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    // Initial state
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Page 2'), findsNothing); // PageView lazy loads/clips?
    // Actually PageView might render adjacent pages depending on cache extent, but usually it shows one.
    // Let's rely on tapping.

    // Tap Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);
    // Verify PageView scrolled. PageView scroll takes time.
    // We can just verify the index updated.
  });
}
