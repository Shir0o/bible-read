import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:bible_read/widgets/achievement_list_item.dart';
import 'package:bible_read/models/achievement_definition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const def = AchievementDefinition(
    id: 'test',
    title: 'Testing',
    description: 'Earned by testing.',
    icon: FontAwesomeIcons.star,
  );

  testWidgets('shows lock icon and text when locked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementListItem(
            definition: def,
            unlocked: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(def.title), findsOneWidget);
    expect(find.text(def.description), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('hides lock icon when unlocked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AchievementListItem(
            definition: def,
            unlocked: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(def.title), findsOneWidget);
    expect(find.text(def.description), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
