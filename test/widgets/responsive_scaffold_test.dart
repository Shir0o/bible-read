import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_read/widgets/responsive_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Navigation icons animate when selected', (tester) async {
    int index = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return MediaQuery(
              data: const MediaQueryData(size: Size(400, 600)),
              child: ResponsiveScaffold(
                selectedIndex: index,
                onDestinationSelected: (i) => setState(() => index = i),
                pages: const [SizedBox(), SizedBox()],
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(
                      icon: Icon(Icons.settings), label: 'Settings'),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    AnimatedScale homeScale =
        tester.widget(find.widgetWithIcon(AnimatedScale, Icons.home).first);
    AnimatedScale settingsScale =
        tester.widget(find.widgetWithIcon(AnimatedScale, Icons.settings).first);
    expect(homeScale.scale, 1.2);
    expect(settingsScale.scale, 1.0);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    homeScale =
        tester.widget(find.widgetWithIcon(AnimatedScale, Icons.home).first);
    settingsScale =
        tester.widget(find.widgetWithIcon(AnimatedScale, Icons.settings).first);
    expect(homeScale.scale, 1.0);
    expect(settingsScale.scale, 1.2);
  });
}
