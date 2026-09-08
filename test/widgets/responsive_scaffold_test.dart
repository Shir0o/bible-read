import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/app_nav_bar.dart';
import 'package:bible_read/widgets/nav_glyphs.dart';
import 'package:bible_read/widgets/responsive_scaffold.dart';

Widget _harness({
  required Size size,
  required int selectedIndex,
  required ValueChanged<int> onDestinationSelected,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const colorScheme = AppTheme.designLightScheme;
  return MaterialApp(
    theme: AppTheme.appTheme(colorScheme),
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: textScaler),
      child: ResponsiveScaffold(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        pages: const [Text('Page 0'), Text('Page 1')],
        destinations: [
          NavigationDestination(
            icon: TodayGlyph(color: colorScheme.onSurfaceVariant),
            selectedIcon: TodayGlyph(color: colorScheme.primary),
            label: 'Today',
          ),
          NavigationDestination(
            icon: CircleGlyph(color: colorScheme.onSurfaceVariant),
            selectedIcon: CircleGlyph(color: colorScheme.primary),
            label: 'Circle',
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('narrow layout shows the bottom bar, not the rail',
      (tester) async {
    await tester.pumpWidget(_harness(
      size: const Size(400, 800),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    ));

    expect(find.byType(AppNavBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.byType(NavigationBar),
      findsNothing,
      reason: 'the Material bar with its pill indicator is replaced',
    );
  });

  testWidgets('wide layout shows the rail, not the bottom bar', (tester) async {
    await tester.pumpWidget(_harness(
      size: const Size(800, 600),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    ));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(AppNavBar), findsNothing);
  });

  testWidgets('wide rail carries the same destinations as the bar', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(
      size: const Size(800, 600),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    ));

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    // The rail shows the same drawn glyphs, not Material icons.
    expect(find.byType(CircleGlyph), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('selection stays in sync across a narrow/wide size change', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    int selectedIndex = 0;
    Widget build(Size size) => _harness(
          size: size,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => selectedIndex = index,
        );

    // Wide: select Circle through the rail.
    await tester.pumpWidget(build(const Size(800, 600)));
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    expect(selectedIndex, 1);

    // Shrink to narrow: the bar must carry the same selection.
    await tester.pumpWidget(build(const Size(400, 800)));
    final bar = tester.widget<AppNavBar>(find.byType(AppNavBar));
    expect(bar.selectedIndex, 1);

    // And back up: the rail carries it again.
    await tester.pumpWidget(build(const Size(800, 600)));
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.selectedIndex, 1);

    semantics.dispose();
  });

  testWidgets('the bar exposes each destination with name and selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_harness(
      size: const Size(400, 800),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    ));

    final home = tester.getSemantics(find.bySemanticsLabel('Today'));
    final community = tester.getSemantics(find.bySemanticsLabel('Circle'));
    expect(home.flagsCollection.isSelected, Tristate.isTrue);
    expect(home.flagsCollection.isButton, isTrue);
    expect(community.flagsCollection.isSelected, isNot(Tristate.isTrue));
    expect(community.flagsCollection.isButton, isTrue);

    semantics.dispose();
  });

  testWidgets('every bar destination is at least a 44px tap target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_harness(
      size: const Size(400, 800),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
    ));

    for (final label in ['Today', 'Circle']) {
      final rect = tester.getRect(find.bySemanticsLabel(label));
      expect(rect.width, greaterThanOrEqualTo(44), reason: '$label width');
      expect(rect.height, greaterThanOrEqualTo(44), reason: '$label height');
    }

    semantics.dispose();
  });

  testWidgets('tapping a destination selects it', (tester) async {
    int selectedIndex = 0;
    await tester.pumpWidget(_harness(
      size: const Size(400, 800),
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) => selectedIndex = index,
    ));

    await tester.tap(find.byType(CircleGlyph));
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);
  });

  testWidgets('icons do not shift when the selection changes', (tester) async {
    Widget build(int selected, ValueChanged<int> onTap) => _harness(
          size: const Size(400, 800),
          selectedIndex: selected,
          onDestinationSelected: onTap,
        );

    await tester.pumpWidget(build(0, (_) {}));
    final restRect = tester.getRect(find.byType(TodayGlyph));

    await tester.tap(find.byType(CircleGlyph));
    await tester.pumpAndSettle();

    final selectedRect = tester.getRect(find.byType(TodayGlyph));
    expect(
      selectedRect.top,
      restRect.top,
      reason: 'inactive destinations reserve the label space, so the icon '
          'holds still when another tab is selected',
    );
  });

  testWidgets('labels stay readable at large system text sizes',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_harness(
      size: const Size(400, 800),
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      textScaler: const TextScaler.linear(2.0),
    ));

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Today'), findsOneWidget);
    expect(find.bySemanticsLabel('Circle'), findsOneWidget);

    semantics.dispose();
  });
}
