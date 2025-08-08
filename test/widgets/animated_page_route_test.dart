import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_read/widgets/animated_page_route.dart';

class _DummyPage extends StatelessWidget {
  const _DummyPage();

  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}

void main() {
  testWidgets('animatedPageRoute builds fade and scale transitions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final route = animatedPageRoute(const _DummyPage());
    final animation = const AlwaysStoppedAnimation<double>(0.5);
    final transition = route.transitionsBuilder(
      tester.element(find.byType(Scaffold)),
      animation,
      animation,
      const SizedBox(),
    );
    expect(transition, isA<FadeTransition>());
    final fade = transition as FadeTransition;
    expect(fade.child, isA<ScaleTransition>());
  });
}
