// Local visual aid for the navigation redesign (issue #812). CI excludes
// test/goldens/*; regenerate with:
//   flutter test --update-goldens test/goldens/nav_bar_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/app_nav_bar.dart';
import 'package:bible_read/widgets/nav_glyphs.dart';

List<NavigationDestination> _destinations(ColorScheme cs) => [
      NavigationDestination(
        icon: TodayGlyph(color: cs.onSurfaceVariant),
        selectedIcon: TodayGlyph(color: cs.primary),
        label: 'Home',
      ),
      NavigationDestination(
        icon: CircleGlyph(color: cs.onSurfaceVariant),
        selectedIcon: CircleGlyph(color: cs.primary),
        label: 'Community',
      ),
      NavigationDestination(
        icon: PathGlyph(color: cs.onSurfaceVariant),
        selectedIcon: PathGlyph(color: cs.primary),
        label: 'Journey',
      ),
    ];

Widget _wrap(ColorScheme cs, Widget child) => MaterialApp(
      theme: AppTheme.appTheme(cs),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: ColoredBox(
          color: cs.surface,
          child: Column(
            children: [
              const Spacer(),
              Align(alignment: Alignment.bottomLeft, child: child),
            ],
          ),
        ),
      ),
    );

void main() {
  for (final (name, scheme) in [
    ('light', AppTheme.designLightScheme),
    ('dark', AppTheme.designDarkScheme),
  ]) {
    testWidgets('nav bar golden ($name)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_wrap(
        scheme,
        AppNavBar(
          selectedIndex: 1,
          onDestinationSelected: (_) {},
          destinations: _destinations(scheme),
        ),
      ));
      await expectLater(
        find.byType(AppNavBar),
        matchesGoldenFile('goldens/nav_bar_$name.png'),
      );
    });

    testWidgets('nav rail golden ($name)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(200, 220));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.appTheme(scheme),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(200, 220)),
            child: ColoredBox(
              color: scheme.surface,
              child: NavigationRail(
                selectedIndex: 1,
                onDestinationSelected: (_) {},
                labelType: NavigationRailLabelType.all,
                leading: const SizedBox(height: 16),
                destinations: _destinations(scheme)
                    .map((d) => NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon ?? d.icon,
                          label: Text(d.label),
                        ))
                    .toList(),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byType(NavigationRail),
        matchesGoldenFile('goldens/nav_rail_$name.png'),
      );
    });
  }
}
