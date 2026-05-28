import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/theme/app_theme.dart';
import 'package:bible_read/widgets/common_styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('buildCard wraps child with default padding', (tester) async {
    const child = Text('content');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: CommonStyles.buildCard(context: context, child: child),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<Card>(find.byType(Card));
    expect(
      card.margin,
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
    expect(card.elevation, 0);
    expect(
      card.color,
      Theme.of(
        tester.element(find.byType(Card)),
      ).colorScheme.surfaceContainerLow,
    );

    final shape = card.shape;
    expect(shape, isA<RoundedRectangleBorder>());
    final border = shape as RoundedRectangleBorder;
    expect(border.borderRadius, BorderRadius.circular(16));

    final paddings = tester.widgetList<Padding>(
      find.descendant(of: find.byType(Card), matching: find.byType(Padding)),
    );
    expect(paddings.any((p) => p.padding == const EdgeInsets.all(16)), isTrue);
  });

  testWidgets('buildAppBar uses configured colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(appBar: CommonStyles.buildAppBar(context, 'Title'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final colorScheme = Theme.of(
      tester.element(find.byType(AppBar)),
    ).colorScheme;
    expect(appBar.backgroundColor, colorScheme.surface);

    final title = tester.widget<Text>(find.text('Title'));
    expect(title.style?.color, colorScheme.onSurface);
  });

  testWidgets('app theme defines restrained Material 3 surfaces', (
    tester,
  ) async {
    final colorScheme = AppTheme.seededColorScheme(Brightness.light);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.appTheme(colorScheme),
        home: Scaffold(
          body: TextField(),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.groups),
                label: 'Community',
              ),
            ],
          ),
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    final cardTheme = theme.cardTheme;
    expect(cardTheme.elevation, 0);
    expect(cardTheme.color, colorScheme.surfaceContainerLow);
    expect(cardTheme.shape, isA<RoundedRectangleBorder>());

    final inputBorder = theme.inputDecorationTheme.border;
    expect(inputBorder, isA<OutlineInputBorder>());
    expect(
      (inputBorder as OutlineInputBorder).borderRadius,
      BorderRadius.circular(12),
    );

    final navTheme = theme.navigationBarTheme;
    expect(navTheme.backgroundColor, colorScheme.surface);
    expect(navTheme.indicatorColor, colorScheme.secondaryContainer);
  });
}
