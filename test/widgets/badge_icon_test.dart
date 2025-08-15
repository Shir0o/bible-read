import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:bible_read/widgets/badge_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows lock icon when locked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeIcon(
            iconData: FontAwesomeIcons.star,
            locked: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('hides lock icon when unlocked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BadgeIcon(
            iconData: FontAwesomeIcons.star,
            locked: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock), findsNothing);
  });
}
