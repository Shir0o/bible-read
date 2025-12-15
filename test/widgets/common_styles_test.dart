import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/common_styles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('buildCard wraps child with default padding', (tester) async {
    const child = Text('content');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: CommonStyles.buildCard(context: context, child: child),
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<Card>(find.byType(Card));
    expect(
        card.margin, const EdgeInsets.symmetric(horizontal: 16, vertical: 8));

    final paddings = tester.widgetList<Padding>(
      find.descendant(of: find.byType(Card), matching: find.byType(Padding)),
    );
    expect(
      paddings.any((p) => p.padding == const EdgeInsets.all(16)),
      isTrue,
    );
  });

  testWidgets('buildAppBar uses configured colors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            appBar: CommonStyles.buildAppBar(context, 'Title'),
          );
        }),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final colorScheme =
        Theme.of(tester.element(find.byType(AppBar))).colorScheme;
    expect(appBar.backgroundColor, colorScheme.surface);

    final title = tester.widget<Text>(find.text('Title'));
    expect(title.style?.color, colorScheme.onSurface);
  });
}
