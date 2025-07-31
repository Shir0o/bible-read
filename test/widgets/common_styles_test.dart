import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/common_styles.dart';
import 'package:bible_read/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('buildCard wraps child with default padding', (tester) async {
    const child = Text('content');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommonStyles.buildCard(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.margin, const EdgeInsets.symmetric(horizontal: 16, vertical: 8));

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
        home: Scaffold(appBar: CommonStyles.buildAppBar('Title')),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, AppTheme.backgroundColor);

    final title = tester.widget<Text>(find.text('Title'));
    expect(title.style?.color, Colors.white);
  });
}
